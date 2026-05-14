#include <jni.h>
#include <string>
#include <vector>
#include <android/log.h>
#include "stable-diffusion.h"

#define TAG "SD_JNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

static sd_ctx_t* g_sd_ctx = nullptr;
static JavaVM* g_jvm = nullptr;
static jobject g_progress_callback = nullptr;
static std::string g_model_path;

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* reserved) {
    g_jvm = vm;
    return JNI_VERSION_1_6;
}

void sd_log_cb(enum sd_log_level_t level, const char* text, void* data) {
    LOGI("[SD Core] %s", text);
}

// Thread-local guard: attaches a native worker thread to the JVM once and
// automatically detaches it when the thread exits. This prevents the JNI
// thread-leak that crashes ART when stable-diffusion.cpp spawns many
// short-lived worker threads for inference.
struct JniEnvGuard {
    JNIEnv* env = nullptr;
    bool attached = false;

    ~JniEnvGuard() {
        if (attached && g_jvm) {
            g_jvm->DetachCurrentThread();
        }
    }

    JNIEnv* get() {
        if (env) {
            // Make sure we are still attached (in case something else detached us)
            JNIEnv* current = nullptr;
            if (g_jvm->GetEnv((void**)&current, JNI_VERSION_1_6) == JNI_OK) {
                return env;
            }
            env = nullptr;
            attached = false;
        }
        jint ret = g_jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
        if (ret == JNI_EDETACHED) {
            if (g_jvm->AttachCurrentThread(&env, nullptr) == JNI_OK) {
                attached = true;
            } else {
                env = nullptr;
            }
        } else if (ret != JNI_OK) {
            env = nullptr;
        }
        return env;
    }
};

void sd_progress_cb(int step, int steps, float time, void* data) {
    if (!g_progress_callback || !g_jvm) return;

    thread_local JniEnvGuard guard;
    JNIEnv* env = guard.get();
    if (!env) return;

    jclass clazz = env->GetObjectClass(g_progress_callback);
    if (!clazz) return;

    jmethodID method = env->GetMethodID(clazz, "onProgress", "(II)V");
    if (method) {
        env->CallVoidMethod(g_progress_callback, method, (jint)step, (jint)steps);
        if (env->ExceptionCheck()) {
            env->ExceptionClear();
        }
    }
    env->DeleteLocalRef(clazz);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_sd_1flutter_1android_SdFlutterAndroidPlugin_initModel(
    JNIEnv* env, jobject thiz, jstring model_path) {

    if (g_sd_ctx) {
        free_sd_ctx(g_sd_ctx);
        g_sd_ctx = nullptr;
    }

    const char* path = env->GetStringUTFChars(model_path, nullptr);

    sd_set_log_callback(sd_log_cb, nullptr);
    sd_set_progress_callback(sd_progress_cb, nullptr);

    sd_ctx_params_t params;
    sd_ctx_params_init(&params);
    params.model_path = path;

    // Limit threads on mobile to reduce memory pressure and thermal throttling.
    int cores = sd_get_num_physical_cores();
    params.n_threads = (cores > 4) ? 4 : cores;

    // Match iOS behaviour: keep buffers alive between generations.
    params.free_params_immediately = false;

    LOGI("Initializing SD model from: %s (threads=%d)", path, params.n_threads);
    g_sd_ctx = new_sd_ctx(&params);

    env->ReleaseStringUTFChars(model_path, path);

    return g_sd_ctx != nullptr ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_example_sd_1flutter_1android_SdFlutterAndroidPlugin_generateImage(
    JNIEnv* env, jobject thiz, jstring prompt, jint steps, jobject callback) {

    if (!g_sd_ctx) {
        LOGE("SD context not initialized");
        return nullptr;
    }

    // Store callback as global ref so it remains valid across threads
    if (g_progress_callback) {
        env->DeleteGlobalRef(g_progress_callback);
    }
    g_progress_callback = env->NewGlobalRef(callback);

    const char* p_str = env->GetStringUTFChars(prompt, nullptr);

    sd_img_gen_params_t params;
    sd_img_gen_params_init(&params);
    params.prompt = p_str;
    params.sample_params.sample_steps = steps;
    params.width = 512;
    params.height = 512;
    params.sample_params.sample_method = EULER_A_SAMPLE_METHOD;

    // Distilled models (SDXS, LCM, etc.) break with standard CFG=7.0
    if (g_model_path.find("distilled") != std::string::npos ||
        g_model_path.find("sdxs") != std::string::npos ||
        g_model_path.find("lcm") != std::string::npos) {
        params.sample_params.guidance.txt_cfg = 1.0f;
        LOGI("Distilled model detected — using CFG=1.0");
    }

    LOGI("Generating image for prompt: %s", p_str);
    sd_image_t* result = generate_image(g_sd_ctx, &params);

    if (result) {
        LOGI("Image generated: %dx%d channels=%d", result->width, result->height, result->channel);
        if (result->channel >= 3 && result->data) {
            LOGI("First pixel RGB: %d %d %d", result->data[0], result->data[1], result->data[2]);
        }
    }

    env->ReleaseStringUTFChars(prompt, p_str);

    if (g_progress_callback) {
        env->DeleteGlobalRef(g_progress_callback);
        g_progress_callback = nullptr;
    }

    if (!result) {
        LOGE("Generation failed");
        return nullptr;
    }

    size_t size = result->width * result->height * result->channel;
    jbyteArray array = env->NewByteArray(size);
    if (!array) {
        LOGE("Failed to allocate ByteArray of size %zu (OOM?)", size);
        free(result->data);
        free(result);
        return nullptr;
    }
    env->SetByteArrayRegion(array, 0, size, (jbyte*)result->data);

    free(result->data);
    free(result);

    return array;
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_sd_1flutter_1android_SdFlutterAndroidPlugin_unloadModel(
    JNIEnv* env, jobject thiz) {
    if (g_sd_ctx) {
        free_sd_ctx(g_sd_ctx);
        g_sd_ctx = nullptr;
    }
    if (g_progress_callback) {
        env->DeleteGlobalRef(g_progress_callback);
        g_progress_callback = nullptr;
    }
}
