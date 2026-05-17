cmake_minimum_required(VERSION 3.22.1)

project(sd_jni)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Android 15 16KB page size compliance
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,-z,max-page-size=16384")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,-z,max-page-size=16384")

# Vulkan is enabled on Android with runtime Adreno detection and CPU fallback.
# Adreno GPUs are blacklisted due to known GGML shader compiler crashes.
# NOTE: Building with SD_VULKAN=ON on Windows requires a host C++ compiler
# (Visual Studio, MinGW, or LLVM) to build the vulkan-shaders-gen tool.
set(SD_VULKAN OFF CACHE BOOL "Enable Vulkan backend" FORCE)

# Use custom FindVulkan that works with Android NDK cross-compilation
list(INSERT CMAKE_MODULE_PATH 0 "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

if(SD_VULKAN)
    find_package(Vulkan REQUIRED)
    add_definitions(-DSD_JNI_HAVE_VULKAN=1)
endif()

# Disable OpenMP to avoid libomp.so packaging issues on Android
set(GGML_OPENMP OFF CACHE BOOL "Disable OpenMP to avoid packaging libomp.so" FORCE)

# Add stable-diffusion.cpp
set(SD_BUILD_EXAMPLES OFF CACHE BOOL "Disable SD examples")
set(SD_BUILD_SHARED_LIBS OFF CACHE BOOL "Build SD as static")
add_subdirectory(src/main/cpp/stable-diffusion.cpp)

# ggml-base is linked as a standalone shared object and contains C++ sources.
# On Android/NDK it must explicitly link libc++ or symbols such as operator new
# and std::runtime_error stay unresolved during the native build.
if(ANDROID)
    foreach(target ggml-base ggml stable-diffusion)
        if(TARGET ${target})
            target_link_libraries(${target} PRIVATE c++_shared)
        endif()
    endforeach()
endif()

# JNI wrapper library
add_library(sd_jni SHARED
    src/main/cpp/sd_jni_wrapper.cpp
)

target_link_libraries(sd_jni PRIVATE
    stable-diffusion
    c++_shared
    android
    log
)

if(SD_VULKAN)
    target_link_libraries(sd_jni PRIVATE Vulkan::Vulkan)
endif()

target_include_directories(sd_jni PRIVATE
    src/main/cpp/stable-diffusion.cpp/include
    src/main/cpp/stable-diffusion.cpp/src
)

if(SD_VULKAN)
    target_include_directories(sd_jni PRIVATE ${Vulkan_INCLUDE_DIRS})
endif()
