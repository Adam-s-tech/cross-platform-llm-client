import 'dart:async';
import 'dart:io' show File, Platform;
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

      print('[LocalImageService] Calling SdFlutterAndroid.initModel...');
      final rawResult = await SdFlutterAndroid.initModelRaw(modelPath);
      print('[LocalImageService] initModel raw result: $rawResult');

      final success = rawResult is bool ? rawResult : (rawResult is String && rawResult == 'true');

      if (success) {
        isModelLoaded.value = true;
        isLoadingModel.value = false;
        loadedModelName.value = modelName ?? modelPath.split('/').last;
        await _hive.setSetting(AppConstants.keyImageModelPath, modelPath);
        await _hive.setSetting(AppConstants.keyImageModelName, loadedModelName.value);
        return 'SUCCESS: Native Image Engine loaded.';
      } else {
        isModelLoaded.value = false;
        isLoadingModel.value = false;
        final errorDetail = rawResult is String ? rawResult : 'Native Engine failed to initialize model.';
        return 'ERROR: $errorDetail';
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
    await _hive.setSetting(AppConstants.keyImageModelPath, '');
    await _hive.setSetting(AppConstants.keyImageModelName, '');
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
