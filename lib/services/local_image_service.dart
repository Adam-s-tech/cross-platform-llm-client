import 'dart:async';
import 'dart:typed_data';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:sd_flutter_android/sd_flutter_android.dart';
import '../core/constants.dart';
import 'hive_service.dart';

class LocalImageService extends GetxService {
  final HiveService _hive = Get.find<HiveService>();
  
  final isModelLoaded = false.obs;
  final isLoadingModel = false.obs;
  final isGenerating = false.obs;
  final progress = 0.0.obs;
  final loadedModelName = ''.obs;

  Future<String> loadModel(String modelPath, {String? modelName}) async {
    if (isLoadingModel.value) return 'ERROR: Model is already loading.';
    
    try {
      if (isModelLoaded.value) {
        await unloadModel();
      }

      isLoadingModel.value = true;
      progress.value = 0.0;

      // ── Vulkan 1.2 safety gate ──
      try {
        final gpu = await LlamaController().detectGpu();
        if (!gpu.vulkanSupported || gpu.vulkanApiVersion < 0x00402000) {
          isLoadingModel.value = false;
          final versionHex = '0x${gpu.vulkanApiVersion.toRadixString(16)}';
          return 'ERROR: Local image generation requires Vulkan 1.2. '
              'This device reports Vulkan $versionHex — image models are not supported.';
        }
      } catch (e) {
        // If GPU detection itself fails, proceed and let native layer handle it
      }

      final success = await SdFlutterAndroid.initModel(modelPath);

      if (success) {
        isModelLoaded.value = true;
        isLoadingModel.value = false;
        loadedModelName.value = modelName ?? modelPath.split('/').last;
        return 'SUCCESS: Native Image Engine loaded.';
      } else {
        isModelLoaded.value = false;
        isLoadingModel.value = false;
        return 'ERROR: Native Engine failed to initialize model.';
      }
    } catch (e) {
      isModelLoaded.value = false;
      isLoadingModel.value = false;
      return 'ERROR: Failed to load native engine — $e';
    }
  }

  Future<void> unloadModel() async {
    await SdFlutterAndroid.unloadModel();
    isModelLoaded.value = false;
    loadedModelName.value = '';
  }

  Future<Uint8List?> generateImage({
    required String prompt,
    void Function(int step, int totalSteps)? onProgress,
  }) async {
    if (!isModelLoaded.value) return null;
    if (isGenerating.value) return null;

    isGenerating.value = true;
    try {
      final steps = _hive.getSetting<int>(AppConstants.keyImageSteps,
          defaultValue: AppConstants.defaultImageSteps) ??
          AppConstants.defaultImageSteps;
      
      final rawBytes = await SdFlutterAndroid.generateImage(
        prompt, 
        steps: steps,
        onProgress: (step, total) {
          onProgress?.call(step, total);
        }
      );

      if (rawBytes == null) {
        isGenerating.value = false;
        return null;
      }

      // Convert raw RGB (512x512x3) to PNG
      // Note: This is computationally expensive in Dart, but necessary for now
      final image = img.Image.fromBytes(
        width: 512,
        height: 512,
        bytes: rawBytes.buffer,
        numChannels: 3,
      );
      final pngBytes = Uint8List.fromList(img.encodePng(image));

      isGenerating.value = false;
      return pngBytes;
    } catch (e) {
      isGenerating.value = false;
      print('Native Generation Error: $e');
      return null;
    }
  }
}
