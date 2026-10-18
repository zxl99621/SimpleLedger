cmake_minimum_required(VERSION 3.22.1)

project(llama_jni)

# Set C++17
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Android 15 16KB page size compliance
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,-z,max-page-size=16384")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,-z,max-page-size=16384")

# ARM64 optimizations
if(ANDROID_ABI STREQUAL "arm64-v8a")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O3 -march=armv8-a+crc")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -march=armv8-a+crc")
endif()

# ---------------------------------------------------------------------------
# Vulkan backend support (SimpleLedger fork)
#
# Upstream 0.2.3 disabled GGML_VULKAN because NDK 27 lacked vulkan.hpp and the
# shader generator failed on Windows cross-compiles. We vendor Vulkan-Headers /
# SPIRV-Headers under third_party/ and reuse the NDK's own glslc, so the backend
# can be built without a separate Vulkan SDK installation.
# ---------------------------------------------------------------------------
if(CMAKE_HOST_WIN32)
    set(_vk_host "windows-x86_64")
    set(_vk_exe ".exe")
elseif(CMAKE_HOST_APPLE)
    set(_vk_host "darwin-x86_64")
    set(_vk_exe "")
else()
    set(_vk_host "linux-x86_64")
    set(_vk_exe "")
endif()

set(Vulkan_GLSLC_EXECUTABLE
    "${ANDROID_NDK}/shader-tools/${_vk_host}/glslc${_vk_exe}"
    CACHE FILEPATH "" FORCE)
get_filename_component(_vk_third_party
    "${CMAKE_CURRENT_SOURCE_DIR}/../third_party" ABSOLUTE)
set(Vulkan_INCLUDE_DIR
    "${_vk_third_party}/vulkan/include"
    CACHE PATH "" FORCE)
# The NDK keeps the Vulkan stub under the target triple, not under `clang/`.
# ggml-vulkan uses Vulkan 1.1 entry points (e.g. vkGetPhysicalDeviceFeatures2)
# that the API 26 stub does not export; SimpleLedger's app minSdk is 30.
set(_vk_triple "aarch64-linux-android")
set(_vk_api 30)
set(Vulkan_LIBRARY
    "${ANDROID_NDK}/toolchains/llvm/prebuilt/${_vk_host}/sysroot/usr/lib/${_vk_triple}/${_vk_api}/libvulkan.so"
    CACHE FILEPATH "" FORCE)
include_directories(BEFORE ${_vk_third_party}/vulkan/include)
include_directories(BEFORE ${_vk_third_party}/spirv/include)

# llama.cpp options
set(GGML_CPU_AARCH64 ON CACHE BOOL "Enable ARM64 support")
set(GGML_DOTPROD ON CACHE BOOL "Enable ARM NEON dot product")
# CPU-only build for the Mali crash workaround. The Vulkan backend crashes in
# ggml_backend_alloc_ctx_tensors_from_buft / ggml_backend_sched_reserve on
# RMX3560 (Mali) even with n_gpu_layers=0, so it must not be compiled in.
set(GGML_VULKAN OFF CACHE BOOL "Enable Vulkan GPU backend" FORCE)
set(GGML_STATIC OFF CACHE BOOL "Build as shared library")
set(BUILD_SHARED_LIBS ON CACHE BOOL "Build shared libraries")

# Disable unused features
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "Disable tests")
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "Disable examples")
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "Disable server")

# Add llama.cpp
add_subdirectory(src/main/cpp/llama.cpp)

# JNI wrapper library - simplified without common library
add_library(llama_jni SHARED
    src/main/cpp/jni_wrapper.cpp
)

# Link against the same (API 30) stub that FindVulkan uses.
set(VULKAN_LIB "${Vulkan_LIBRARY}")

target_link_libraries(llama_jni
    llama
    android
    log
    ${VULKAN_LIB}
)

target_include_directories(llama_jni PRIVATE
    src/main/cpp/llama.cpp/include
    src/main/cpp/llama.cpp/ggml/include
)
