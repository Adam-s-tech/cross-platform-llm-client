import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:typed_data';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:sd_flutter_android/sd_flutter_android.dart';
import '../core/constants.dart';
import '../ffi/sd_ffi_bindings.dart';
import 'hive_service.dart';
import 'sd_isolate_processor.dart';

class LocalImageService extends GetxService {
  final HiveService _hive = Get.find<HiveService>();

  final isModelLoaded = false.obs;
  final isLoadingModel = false.obs;
  final isGenerating = false.obs;
  final progress = 0.0.obs;
  final loadedModelName = ''.obs;
  final gpuVendor = 'unknown'.obs;
  final isUsingGpu = false.obs;
  final latestLog = ''.obs;
  final currentBackend = Backend.cpu.obs;
  final currentQuantization = QuantizationType.q4_0.obs;

  SdIsolateProcessor? _processor;

  String? get lastModelPath =>
      _hive.getSetting<String>(AppConstants.keyImageModelPath);
  String? get lastModelName =>
      _hive.getSetting<String>(AppConstants.keyImageModelName);

  @override
  void onInit() {
    super.onInit();
    // Restore saved backend / quantization preferences
    final savedBackendIndex = _hive.getSetting<int>(AppConstants.keyImageGenBackend,
        defaultValue: Backend.cpu.index);
    final savedQuantIndex = _hive.getSetting<int>(AppConstants.keyImageGenQuantization,
        defaultValue: QuantizationType.f16.index);
    if (savedBackendIndex != null && savedBackendIndex >= 0 && savedBackendIndex < Backend.values.length) {
      currentBackend.value = Backend.values[savedBackendIndex];
    }
    if (savedQuantIndex != null && savedQuantIndex >= 0 && savedQuantIndex < QuantizationType.values.length) {
      currentQuantization.value = QuantizationType.values[savedQuantIndex];
    }
  }

  Future<String> loadModel(String modelPath, {String? modelName, String? taesdPath}) async {
    if (isLoadingModel.value) return 'ERROR: Model is already loading.';
    
    try {
      if (isModelLoaded.value) {
        await unloadModel();
      }

      isLoadingModel.value = true;
      progress.value = 0.0;

      print('[LocalImageService] loadModel called with path: $modelPath');
      if (taesdPath != null) {
        print('[LocalImageService] TAESD path: $taesdPath');
      }

      // Debug: check file existence and size from Dart side
      try {
        final file = File(modelPath);
        final exists = await file.exists();
        print('[LocalImageService] File exists: $exists');
        if (exists) {
          final length = await file.length();
          print('[LocalImageService] File size: $length bytes');
        }
      } catch (e) {
        print('[LocalImageService] File check error: $e');
      }

      // Detect GPU vendor and decide backend
      String vendor = 'unknown';
      bool useGpu = true;
      if (Platform.isAndroid) {
        try {
          vendor = await SdFlutterAndroid.detectGpuVendor();
          gpuVendor.value = vendor;
          print('[LocalImageService] GPU vendor detected: $vendor');
        } catch (e) {
          print('[LocalImageService] GPU detection failed: $e');
        }
        // Adreno GPUs are blacklisted due to known GGML Vulkan shader compiler crashes
        if (vendor == 'adreno') {
          useGpu = false;
          print('[LocalImageService] Adreno detected — forcing CPU fallback');
        }
      }
      // Check user override to force CPU
      final forceCpu = _hive.getSetting<bool>(AppConstants.keyImageGenForceCpu,
          defaultValue: false) ?? false;
      if (forceCpu) {
        useGpu = false;
        print('[LocalImageService] User override — forcing CPU');
      }
      isUsingGpu.value = useGpu;

      // Determine backend: user saved > auto-detect > CPU fallback
      Backend backend = currentBackend.value;
      if (!useGpu && backend != Backend.cpu) {
        backend = Backend.cpu;
      }
      // If the chosen backend library isn't built yet, SdFfiBindings falls back to CPU
      currentBackend.value = backend;

      // Detect device RAM and set VRAM limit (prevent OOM on low-RAM devices)
      int totalRamMb = 4096;
      if (Platform.isAndroid) {
        try {
          totalRamMb = await SdFlutterAndroid.getDeviceMemory();
          print('[LocalImageService] Device RAM: ${totalRamMb}MB');
        } catch (e) {
          print('[LocalImageService] Memory detection failed: $e');
        }
      }
      // Cap VRAM at 70% of total RAM to leave headroom for OS + app
      final maxVram = (totalRamMb * 0.7).clamp(1024.0, 8192.0);
      print('[LocalImageService] Max VRAM limit: ${maxVram.toStringAsFixed(0)}MB');

      // Create isolate processor
      print('[LocalImageService] Creating SdIsolateProcessor (backend=${backend.displayName}, quant=${currentQuantization.value.displayName})...');
      _processor = SdIsolateProcessor(
        modelPath: modelPath,
        nThreads: 0, // auto
        flashAttn: true, // reduces memory, speeds up attention
        vaeTiling: true, // crucial for mobile VAE decode
        taesdPath: taesdPath,
        backend: backend,
        quantizationType: currentQuantization.value,
        enableMmap: true, // memory-map model file instead of loading into RAM
        maxVram: maxVram,
      );

      // Pipe logs to latestLog observable
      _processor!.logStream.listen((log) {
        latestLog.value = log.message;
      });

      // Wait for model to load in isolate
      final modelLoaded = await _processor!.modelLoaded
          .timeout(const Duration(seconds: 120), onTimeout: () => false);

      if (modelLoaded) {
        isModelLoaded.value = true;
        isLoadingModel.value = false;
        loadedModelName.value = modelName ?? modelPath.split('/').last;
        await _hive.setSetting(AppConstants.keyImageModelPath, modelPath);
        await _hive.setSetting(AppConstants.keyImageModelName, loadedModelName.value);
        await _hive.setSetting(AppConstants.keyImageGenBackend, currentBackend.value.index);
        await _hive.setSetting(AppConstants.keyImageGenQuantization, currentQuantization.value.index);
        return 'Image model loaded successfully.';
      } else {
        await _processor?.dispose();
        _processor = null;
        isModelLoaded.value = false;
        isLoadingModel.value = false;
        return 'Could not load this model. Try CyberRealistic, Realistic Vision, or AbsoluteReality — these work reliably on most devices.\n\nTechnical detail: Model initialization timed out or failed in isolate.';
      }
    } catch (e) {
      isModelLoaded.value = false;
      isLoadingModel.value = false;
      return 'Could not load this model. Try CyberRealistic, Realistic Vision, or AbsoluteReality — these work reliably on most devices.\n\nTechnical detail: $e';
    }
  }

  Future<void> unloadModel() async {
    await _processor?.dispose();
    _processor = null;
    isModelLoaded.value = false;
    loadedModelName.value = '';
    gpuVendor.value = 'unknown';
    isUsingGpu.value = false;
    await _hive.setSetting(AppConstants.keyImageModelPath, '');
    await _hive.setSetting(AppConstants.keyImageModelName, '');
  }

  /// Change the inference backend (CPU / Vulkan / etc).
  /// The new backend takes effect on the next [loadModel] call.
  void setBackend(Backend backend) {
    currentBackend.value = backend;
    _hive.setSetting(AppConstants.keyImageGenBackend, backend.index);
  }

  /// Change the model quantization type.
  /// The new quantization takes effect on the next [loadModel] call.
  void setQuantization(QuantizationType type) {
    currentQuantization.value = type;
    _hive.setSetting(AppConstants.keyImageGenQuantization, type.index);
  }

  void cancelGeneration() {
    if (isGenerating.value) {
      print('[LocalImageService] Generation cancelled by user');
      isGenerating.value = false;
    }
  }

  Future<Uint8List?> generateImage({
    required String prompt,
    void Function(int step, int totalSteps)? onProgress,
  }) async {
    if (!isModelLoaded.value || _processor == null) return null;
    if (isGenerating.value) return null;

    isGenerating.value = true;
    StreamSubscription? progressSub;
    StreamSubscription? logSub;

    try {
      final steps = _hive.getSetting<int>(AppConstants.keyImageSteps,
          defaultValue: AppConstants.defaultImageSteps) ??
          AppConstants.defaultImageSteps;

      print('[LocalImageService] generateImage start: prompt="$prompt", steps=$steps');

      // Subscribe to progress and log streams
      progressSub = _processor!.progressStream.listen((update) {
        print('[LocalImageService] Progress: step ${update.step}/${update.totalSteps}');
        onProgress?.call(update.step, update.totalSteps);
      });
      logSub = _processor!.logStream.listen((log) {
        print('[LocalImageService] Log [L${log.level}]: ${log.message}');
        latestLog.value = log.message;
      });

      final result = await _processor!.generate(
        prompt: prompt,
        steps: steps,
        // Future: expose width, height, seed, cfg, negativePrompt, sampleMethod from settings
      );

      await progressSub.cancel();
      await logSub.cancel();

      print('[LocalImageService] Generation result: error=${result.error}, bytes=${result.rgbBytes?.length}, ${result.width}x${result.height}');

      if (result.error != null || result.rgbBytes == null) {
        print('[LocalImageService] Generation failed: ${result.error}');
        isGenerating.value = false;
        return null;
      }

      // Convert raw RGB to PNG
      // TODO: switch to ui.decodeImageFromPixels for GPU-accelerated decode
      print('[LocalImageService] Encoding ${result.width}x${result.height} RGB to PNG...');
      final image = img.Image.fromBytes(
        width: result.width,
        height: result.height,
        bytes: result.rgbBytes!.buffer,
        numChannels: 3,
      );
      final pngBytes = Uint8List.fromList(img.encodePng(image));
      print('[LocalImageService] PNG encoded: ${pngBytes.length} bytes');

      isGenerating.value = false;
      return pngBytes;
    } catch (e, stack) {
      await progressSub?.cancel();
      await logSub?.cancel();
      isGenerating.value = false;
      print('[LocalImageService] Native Generation Error: $e');
      print('[LocalImageService] Stack: $stack');
      return null;
    }
  }
}
