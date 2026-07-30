# SPDX-FileCopyrightText: 2026 Blender Authors
#
# SPDX-License-Identifier: GPL-2.0-or-later

# Platform setup for Android (arm64), consuming the harvested dependency
# prefix produced by build_files/android/deps/build.sh.
#
# WIP: establishes LIBDIR and the per-package <Pkg>_ROOT hints, and disables
# desktop-only features. Full configure is being brought up incrementally.

if(NOT DEFINED LIBDIR)
  # Sibling of the source tree, matching the deps builder's default.
  set(LIBDIR "${CMAKE_SOURCE_DIR}/../lib/android_arm64")
endif()
if(NOT EXISTS "${LIBDIR}")
  message(FATAL_ERROR "Android LIBDIR not found: ${LIBDIR}\n"
    "Build dependencies first: build_files/android/deps/build.sh")
endif()
message(STATUS "Android LIBDIR = ${LIBDIR}")

# NDK libc++ lacks std::atomic_ref (C++20); force-include a polyfill.
string(APPEND CMAKE_CXX_FLAGS
  " -include ${CMAKE_SOURCE_DIR}/build_files/android/compat/atomic_ref_compat.hpp")

# The NDK ships older Vulkan headers; use our up-to-date Vulkan-Headers first.
include_directories(BEFORE SYSTEM ${LIBDIR}/vulkan/include)
set(VULKAN_INCLUDE_DIR ${LIBDIR}/vulkan/include)
set(VULKAN_INCLUDE_DIRS ${LIBDIR}/vulkan/include)
find_library(VULKAN_LIBRARY vulkan REQUIRED)
set(VULKAN_LIBRARIES ${VULKAN_LIBRARY})
set(VULKAN_FOUND ON)

# Find harvested libs by rooting into their prefixes, never host paths.
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM BOTH)
file(GLOB _android_dep_prefixes "${LIBDIR}/*")
list(APPEND CMAKE_FIND_ROOT_PATH ${_android_dep_prefixes})

# Per-package root hints for find_package().
set(ZLIB_ROOT ${LIBDIR}/zlib)
set(ZSTD_ROOT ${LIBDIR}/zstd)
set(Imath_ROOT ${LIBDIR}/imath)
set(fmt_ROOT ${LIBDIR}/fmt)
set(TBB_ROOT ${LIBDIR}/tbb)
set(OpenEXR_ROOT ${LIBDIR}/openexr)
set(PNG_ROOT ${LIBDIR}/png)
set(JPEG_ROOT ${LIBDIR}/jpeg)
set(TIFF_ROOT ${LIBDIR}/tiff)
set(WebP_ROOT ${LIBDIR}/webp)
set(Freetype_ROOT ${LIBDIR}/freetype)
set(HARFBUZZ_ROOT ${LIBDIR}/harfbuzz)
set(OpenImageIO_ROOT ${LIBDIR}/openimageio)
set(OpenColorIO_ROOT ${LIBDIR}/opencolorio)
set(OpenSubdiv_ROOT ${LIBDIR}/opensubdiv)
set(OpenVDB_ROOT ${LIBDIR}/openvdb)
set(Alembic_ROOT ${LIBDIR}/alembic)
set(MaterialX_ROOT ${LIBDIR}/materialx)
set(Embree_ROOT ${LIBDIR}/embree)
set(pxr_ROOT ${LIBDIR}/usd)
set(PYTHON_ROOT ${LIBDIR}/python)
set(LLVM_ROOT_DIR ${LIBDIR}/llvm)
set(CLANG_ROOT_DIR ${LIBDIR}/llvm)
set(SQLite3_ROOT ${LIBDIR}/sqlite)
set(Potrace_ROOT ${LIBDIR}/potrace)
set(FFMPEG_ROOT ${LIBDIR}/ffmpeg)
set(Robinmap_ROOT ${LIBDIR}/robinmap)
set(PUGIXML_ROOT ${LIBDIR}/pugixml)
set(EXPAT_ROOT ${LIBDIR}/expat)
set(yaml-cpp_ROOT ${LIBDIR}/yamlcpp)
set(Blosc_ROOT ${LIBDIR}/blosc)
set(OpenJPEG_ROOT ${LIBDIR}/openjpeg)
set(pystring_ROOT ${LIBDIR}/pystring)
set(Eigen3_ROOT ${LIBDIR}/eigen)
set(absl_ROOT ${LIBDIR}/abseil)
set(Fribidi_ROOT ${LIBDIR}/fribidi)
set(SSE2NEON_INCLUDE_DIR ${LIBDIR}/sse2neon/include)
set(LibFFI_ROOT ${LIBDIR}/libffi)
set(OpenSSL_ROOT ${LIBDIR}/openssl)

# Vulkan surface from the NDK sysroot.
set(WITH_VULKAN_BACKEND ON)
set(WITH_GHOST_ANDROID ON)

# -----------------------------------------------------------------------------
# Cross-compiled build tools (makesdna, makesrna, datatoc, msgfmt, shader_tool).
# These generate source at build time and must run on the host, so they are
# built natively (macOS arm64 == Android arm64 data model, so DNA/RNA offsets
# match) and imported here. Build them first:
#   cmake -S . -B ../build_host_tools -G Ninja -DWITH_CYCLES=OFF
#   ninja -C ../build_host_tools makesdna makesrna datatoc msgfmt shader_tool
set(WITH_CROSSCOMPILED_TOOLS ON)
if(NOT DEFINED CROSSCOMPILE_TOOLDIR)
  set(CROSSCOMPILE_TOOLDIR "${CMAKE_SOURCE_DIR}/../build_host_tools/bin")
endif()
foreach(_tool makesdna makesrna datatoc msgfmt shader_tool)
  if(NOT EXISTS "${CROSSCOMPILE_TOOLDIR}/${_tool}")
    message(FATAL_ERROR "Host tool missing: ${CROSSCOMPILE_TOOLDIR}/${_tool}\n"
      "Build host tools first (see platform_android.cmake header).")
  endif()
  add_executable(${_tool} IMPORTED GLOBAL)
  set_property(TARGET ${_tool} PROPERTY IMPORTED_LOCATION "${CROSSCOMPILE_TOOLDIR}/${_tool}")
endforeach()

# Desktop-only or not-yet-ported features: keep off for Android.
set(WITH_GHOST_X11 OFF)
set(WITH_GHOST_WAYLAND OFF)
set(WITH_GHOST_SDL OFF)
set(WITH_X11 OFF)
set(WITH_OPENGL_BACKEND OFF)
set(WITH_GHOST_XDND OFF)
set(WITH_INPUT_NDOF OFF)
set(WITH_XR_OPENXR OFF)
set(WITH_AUDASPACE ON)
set(WITH_JACK OFF)
set(WITH_PULSEAUDIO OFF)
set(WITH_COREAUDIO OFF)
set(WITH_SDL OFF)
set(WITH_OPENAL OFF)
set(WITH_OPENMP OFF)
set(WITH_LIBMV OFF)
set(WITH_CYCLES_OSL OFF)
set(WITH_HYDRA OFF)

# Optional / not-yet-ported features: disabled for the first Android configure.
set(WITH_OPENSUBDIV ON)
set(WITH_POTRACE ON)
set(WITH_HARU OFF)
set(WITH_MOD_OCEANSIM OFF)
set(WITH_GMP OFF)
set(WITH_FFTW3 OFF)
set(WITH_CODEC_SNDFILE OFF)
set(WITH_CODEC_FFMPEG ON)
set(WITH_DRACO OFF)
set(WITH_GLTF OFF)
set(WITH_LIBMV OFF)
set(WITH_LIBMV_SCHUR_SPECIALIZATIONS OFF)
set(WITH_OPENIMAGEDENOISE OFF)
set(WITH_CYCLES_PATH_GUIDING OFF)
set(WITH_CYCLES_EMBREE ON)
set(WITH_MOD_FLUID OFF)
set(WITH_MANIFOLD OFF)
set(WITH_VECTOR_GRAPHICS OFF)
set(WITH_HARFBUZZ ON)
set(WITH_FRIBIDI ON)
set(WITH_OPENCOLLADA OFF)
set(WITH_IO_WAVEFRONT_OBJ ON)
set(WITH_TBB ON)
set(WITH_USD ON)
set(WITH_MATERIALX ON)
set(WITH_OPENVDB ON)
set(WITH_ALEMBIC ON)
set(WITH_OPENIMAGEIO ON)
set(WITH_LLVM ON)
set(WITH_PYTHON ON)
set(WITH_PYTHON_INSTALL OFF)
set(WITH_PYTHON_MODULE OFF)
set(WITH_DOC_MANPAGE OFF)
set(WITH_CYCLES_HYDRA_RENDER_DELEGATE OFF)

# Shared feature toggles (must match the host codegen-tools build exactly).
include(${CMAKE_SOURCE_DIR}/build_files/android/android_features.cmake)

# -----------------------------------------------------------------------------
# Locate the harvested dependencies (mirrors platform_unix for our subset).

macro(find_package_wrapper)
  find_package(${ARGV})
endmacro()

find_package_wrapper(JPEG REQUIRED)
find_package_wrapper(PNG REQUIRED)
find_package_wrapper(ZLIB REQUIRED)
find_package_wrapper(Zstd REQUIRED)
find_package_wrapper(fmt REQUIRED)
find_package(Eigen3 REQUIRED)
find_package_wrapper(Freetype REQUIRED)
find_package_wrapper(Brotli REQUIRED)
find_package_wrapper(Harfbuzz)
find_package_wrapper(Fribidi)

if(WITH_PYTHON)
  set(PYTHON_VERSION 3.13)
  set(PYTHON_INCLUDE_DIR ${LIBDIR}/python/include/python3.13)
  set(PYTHON_INCLUDE_CONFIG_DIR ${LIBDIR}/python/include/python3.13)
  set(PYTHON_LIBRARY ${LIBDIR}/python/lib/libpython3.13.so)
  set(PYTHON_LIBPATH ${LIBDIR}/python/lib)
  find_package(PythonLibsUnix REQUIRED)
  # Build-time scripts (discover_nodes.py, etc.) must run on the HOST, so
  # PYTHON_EXECUTABLE points to a host interpreter, not the arm64 target one.
  find_program(HOST_PYTHON_EXECUTABLE NAMES python3.13 python3 python
    NO_CMAKE_FIND_ROOT_PATH)
  if(NOT HOST_PYTHON_EXECUTABLE)
    message(FATAL_ERROR "No host python3 found for build-time scripts")
  endif()
  set(PYTHON_EXECUTABLE "${HOST_PYTHON_EXECUTABLE}" CACHE FILEPATH "" FORCE)

  # numpy (cross-compiled into the target site-packages).
  set(_np ${LIBDIR}/python/lib/python3.13/site-packages/numpy/_core/include)
  if(EXISTS ${_np}/numpy/ndarrayobject.h)
    set(WITH_PYTHON_NUMPY ON)
    set(PYTHON_NUMPY_INCLUDE_DIRS ${_np})
    set(PYTHON_NUMPY_PATH ${LIBDIR}/python/lib/python3.13/site-packages)
  endif()
endif()

find_package_wrapper(OpenEXR REQUIRED)
find_package_wrapper(OpenJPEG)
find_package_wrapper(WebP)
find_package_wrapper(PugiXML)
find_package_wrapper(TBB)
if(NOT TBB_LIBRARIES)
  set(TBB_LIBRARIES TBB::tbb)
endif()
find_package_wrapper(OpenImageIO REQUIRED)
# OIIO built without tools; stub the tool target (not executed in this config).
if(NOT TARGET OpenImageIO::oiiotool)
  add_executable(OpenImageIO::oiiotool IMPORTED)
  set_target_properties(OpenImageIO::oiiotool PROPERTIES
    IMPORTED_LOCATION "${LIBDIR}/openimageio/bin/oiiotool")
endif()
find_package_wrapper(OpenColorIO 2.0.0 REQUIRED)
test_neon_support()  # sets SUPPORTS_NEON_BUILD, so Cycles uses sse2neon not -msse
find_package_wrapper(sse2neon REQUIRED)
find_package_wrapper(OpenVDB)
find_package_wrapper(NanoVDB)
find_package_wrapper(Alembic)
find_package_wrapper(USD)
find_package_wrapper(MaterialX)
find_package_wrapper(OpenSubdiv)
find_package_wrapper(Potrace)

if(WITH_CYCLES_EMBREE)
  find_package(Embree 4.0.0 REQUIRED)
endif()

if(WITH_LLVM)
  find_package_wrapper(LLVM)
endif()

if(WITH_CODEC_FFMPEG)
  find_package(FFmpeg)
endif()
