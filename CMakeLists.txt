cmake_minimum_required(VERSION 3.24)
# CMake's iOS platform otherwise turns upstream command-line tools into app
# bundles and tries to sign compiler capability probes.
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(CMAKE_MACOSX_BUNDLE OFF)
    set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
endif()
project(LlamaPad LANGUAGES C CXX OBJC OBJCXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON ON CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS ON CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER ON CACHE BOOL "" FORCE)
set(LLAMA_BUILD_APP OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_UI OFF CACHE BOOL "" FORCE)
set(LLAMA_USE_PREBUILT_UI OFF CACHE BOOL "" FORCE)
set(LLAMA_SUBPROCESS OFF CACHE BOOL "" FORCE)
set(LLAMA_OPENSSL OFF CACHE BOOL "" FORCE)
set(GGML_RPC ON CACHE BOOL "" FORCE)
set(GGML_RPC_RDMA OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_CPU_KLEIDIAI OFF CACHE BOOL "" FORCE)
set(GGML_ACCELERATE ON CACHE BOOL "" FORCE)
set(GGML_BLAS ON CACHE BOOL "" FORCE)
set(GGML_BLAS_VENDOR Apple CACHE STRING "" FORCE)
set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    # Common M-series CPU baseline. Metal dispatch independently selects the
    # best GPU kernels on each device, including M5 tensor acceleration.
    set(GGML_CPU_ARM_ARCH "armv8.4-a+dotprod+fp16" CACHE STRING "" FORCE)
    unset(HAVE_FP16_VECTOR_ARITHMETIC CACHE)
    set(GGML_METAL_TARGET_OS "ios" CACHE STRING "" FORCE)
endif()

file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/upstream.lock" LLAMAPAD_REVISION LIMIT_COUNT 1)
set(LLAMA_BUILD_COMMIT "${LLAMAPAD_REVISION}" CACHE STRING "Pinned engine revision" FORCE)
set(LLAMA_BUILD_NUMBER 0 CACHE STRING "Source archive build" FORCE)
add_subdirectory(vendor/llama.cpp)
add_library(llamapad-native STATIC
    Native/runtime.cpp
    Native/platform.mm
    vendor/llama.cpp/tools/server/server-http.cpp)
target_include_directories(llamapad-native PUBLIC Native/include)
target_include_directories(llamapad-native PRIVATE
    vendor/llama.cpp/tools/server
    vendor/llama.cpp/common
    vendor/llama.cpp)
target_link_libraries(llamapad-native PUBLIC server-context llama-ui cpp-httplib ggml-rpc "-framework Foundation")
if(GGML_METAL)
    target_compile_definitions(llamapad-native PRIVATE LP_HAS_METAL=1)
    target_link_libraries(llamapad-native PUBLIC "-framework Metal")
endif()
target_compile_definitions(llamapad-native PRIVATE LLAMAPAD_REVISION="${LLAMAPAD_REVISION}")

if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(LLAMAPAD_ARCHIVE_FILES "")
    foreach(target IN ITEMS llamapad-native server-context llama-common llama-common-base mtmd
            llama ggml ggml-base ggml-cpu ggml-blas ggml-metal ggml-rpc llama-ui cpp-httplib vendor-hash)
        string(APPEND LLAMAPAD_ARCHIVE_FILES "$<TARGET_FILE:${target}>\n")
    endforeach()
    file(GENERATE OUTPUT "${CMAKE_BINARY_DIR}/llamapad-archives.txt" CONTENT "${LLAMAPAD_ARCHIVE_FILES}")
endif()

if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
    add_executable(llamapad-host Native/host.cpp)
    target_link_libraries(llamapad-host PRIVATE llamapad-native)
endif()
