import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

// ---------------------------------------------------------------------------
// Enums (must match stable-diffusion.h)
// ---------------------------------------------------------------------------

enum SampleMethod {
  euler,
  eulerA,
  heun,
  dpm2,
  dpmpp2sA,
  dpmpp2m,
  dpmpp2mv2,
  ipndm,
  ipndmV,
  lcm,
  ddimTrailing,
  tcd,
  resMultistep,
  res2s,
  erSde,
}

enum Schedule {
  discrete,
  karras,
  exponential,
  ays,
  gits,
  sgmUniform,
  simple,
  smoothstep,
  klOptimal,
  lcm,
  bongTangent,
}

// ---------------------------------------------------------------------------
// Native typedefs
// ---------------------------------------------------------------------------

typedef ProgressCallbackNative = Void Function(
    Int32 step, Int32 steps, Float time);
typedef LogCallbackNative = Void Function(Int32 level, Pointer<Utf8> text);

typedef SdFfiSetProgressCallbackNative = Void Function(
    Pointer<NativeFunction<ProgressCallbackNative>> cb);
typedef SdFfiSetProgressCallback = void Function(
    Pointer<NativeFunction<ProgressCallbackNative>> cb);

typedef SdFfiSetLogCallbackNative = Void Function(
    Pointer<NativeFunction<LogCallbackNative>> cb);
typedef SdFfiSetLogCallback = void Function(
    Pointer<NativeFunction<LogCallbackNative>> cb);

typedef SdFfiInitNative = Pointer<Void> Function(
    Pointer<Utf8> modelPath,
    Int32 nThreads,
    Bool flashAttn,
    Bool vaeTiling,
);
typedef SdFfiInit = Pointer<Void> Function(
    Pointer<Utf8> modelPath,
    int nThreads,
    bool flashAttn,
    bool vaeTiling,
);

typedef SdFfiFreeNative = Void Function(Pointer<Void> ctx);
typedef SdFfiFree = void Function(Pointer<Void> ctx);

typedef SdFfiGenerateNative = Pointer<Uint8> Function(
    Pointer<Void> ctx,
    Pointer<Utf8> prompt,
    Pointer<Utf8> negativePrompt,
    Int32 width,
    Int32 height,
    Int32 steps,
    Int64 seed,
    Float cfgScale,
    Int32 sampleMethod,
    Int32 schedule,
    Bool vaeTiling,
    Pointer<IntPtr> outSize,
);
typedef SdFfiGenerate = Pointer<Uint8> Function(
    Pointer<Void> ctx,
    Pointer<Utf8> prompt,
    Pointer<Utf8> negativePrompt,
    int width,
    int height,
    int steps,
    int seed,
    double cfgScale,
    int sampleMethod,
    int schedule,
    bool vaeTiling,
    Pointer<IntPtr> outSize,
);

typedef SdFfiGetCoresNative = Int32 Function();
typedef SdFfiGetCores = int Function();

// ---------------------------------------------------------------------------
// Global isolate communication
// ---------------------------------------------------------------------------

SendPort? _globalSendPort;

void _staticProgressCallback(int step, int steps, double time) {
  _globalSendPort?.send({
    'type': 'progress',
    'step': step,
    'steps': steps,
    'time': time,
  });
}

void _staticLogCallback(int level, Pointer<Utf8> text) {
  _globalSendPort?.send({
    'type': 'log',
    'level': level,
    'message': text.toDartString(),
  });
}

// ---------------------------------------------------------------------------
// FFI Bindings singleton
// ---------------------------------------------------------------------------

class SdFfiBindings {
  static DynamicLibrary? _lib;

  static late SdFfiSetProgressCallback setProgressCallback;
  static late SdFfiSetLogCallback setLogCallback;
  static late SdFfiInit init;
  static late SdFfiFree freeCtx;
  static late SdFfiGenerate generate;
  static late SdFfiGetCores getCores;

  static Pointer<NativeFunction<ProgressCallbackNative>>? _progressPtr;
  static Pointer<NativeFunction<LogCallbackNative>>? _logPtr;

  static void initialize() {
    if (_lib != null) return;

    if (Platform.isAndroid) {
      _lib = DynamicLibrary.open('libsd_jni.so');
    } else {
      throw UnsupportedError('SdFfiBindings only supports Android');
    }

    setProgressCallback = _lib!.lookupFunction<
        SdFfiSetProgressCallbackNative,
        SdFfiSetProgressCallback>('sd_ffi_set_progress_callback');

    setLogCallback = _lib!.lookupFunction<
        SdFfiSetLogCallbackNative,
        SdFfiSetLogCallback>('sd_ffi_set_log_callback');

    init = _lib!.lookupFunction<SdFfiInitNative, SdFfiInit>('sd_ffi_init');

    freeCtx = _lib!.lookupFunction<SdFfiFreeNative, SdFfiFree>('sd_ffi_free');

    generate = _lib!.lookupFunction<SdFfiGenerateNative, SdFfiGenerate>(
        'sd_ffi_generate');

    getCores = _lib!.lookupFunction<SdFfiGetCoresNative, SdFfiGetCores>(
        'sd_ffi_get_cores');
  }

  static void setupCallbacks(SendPort sendPort) {
    _globalSendPort = sendPort;

    _progressPtr ??=
        Pointer.fromFunction<ProgressCallbackNative>(_staticProgressCallback);
    _logPtr ??= Pointer.fromFunction<LogCallbackNative>(_staticLogCallback);

    setProgressCallback(_progressPtr!);
    setLogCallback(_logPtr!);
  }

  static void clearCallbacks() {
    setProgressCallback(nullptr);
    setLogCallback(nullptr);
    _globalSendPort = null;
  }
}
