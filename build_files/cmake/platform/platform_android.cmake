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

# Vulkan surface from the NDK sysroot.
set(WITH_VULKAN_BACKEND ON)
set(WITH_GHOST_ANDROID ON)

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

# Not yet cross-compiled — disable until their recipes land.
set(WITH_OPENSUBDIV ON)
set(WITH_POTRACE ON)
set(WITH_HARU OFF)
set(WITH_MOD_OCEANSIM OFF)
