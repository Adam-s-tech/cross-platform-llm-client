import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:typed_data';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:sd_flutter_android/sd_flutter_android.dart';
import '../core/constants.dart';
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

  SdIsolateProcessor? _processor;

  String? get lastModelPath =>
      _hive.getSetting<String>(AppConstants.keyImageModelPath);
  String? get lastModelName =>
      _hive.getSetting<String>(AppConstants.keyImageModelName);

  Future<String> loadModel(String modelPath, {String? modelName}) async {
    if (isLoadingModel.value) return 'ERROR: Model is already loading.';
    
    try {
      if (isModelLoaded.value) {
        await unloadModel();
      }

      isLoadingModel.value = true;
      progress.value = 0.0;

      print('[LocalImageService] loadModel called with path: $modelPath');

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

      // Create isolate processor
      print('[LocalImageService] Creating SdIsolateProcessor...');
      _processor = SdIsolateProcessor(
        modelPath: modelPath,
        nThreads: 0, // auto
        flashAttn: false,
        vaeTiling: false,
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

    try {
      final steps = _hive.getSetting<int>(AppConstants.keyImageSteps,
          defaultValue: AppConstants.defaultImageSteps) ??
          AppConstants.defaultImageSteps;

      // Subscribe to progress stream
      progressSub = _processor!.progressStream.listen((update) {
        onProgress?.call(update.step, update.totalSteps);
      });

      final result = await _processor!.generate(
        prompt: prompt,
        steps: steps,
        // Future: expose width, height, seed, cfg, negativePrompt, sampleMethod from settings
      );

      await progressSub.cancel();

      if (result.error != null || result.rgbBytes == null) {
        print('Generation failed: ${result.error}');
        isGenerating.value = false;
        return null;
      }

      // Convert raw RGB to PNG
      // TODO: switch to ui.decodeImageFromPixels for GPU-accelerated decode
      final image = img.Image.fromBytes(
        width: result.width,
        height: result.height,
        bytes: result.rgbBytes!.buffer,
        numChannels: 3,
      );
      final pngBytes = Uint8List.fromList(img.encodePng(image));

      isGenerating.value = false;
      return pngBytes;
    } catch (e) {
      await progressSub?.cancel();
      isGenerating.value = false;
      print('Native Generation Error: $e');
      return null;
    }
  }
}
