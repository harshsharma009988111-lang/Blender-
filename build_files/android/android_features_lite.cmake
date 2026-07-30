# SPDX-FileCopyrightText: 2026 Blender Authors
#
# SPDX-License-Identifier: GPL-2.0-or-later
#
# LITE Android config — for weak devices / day-to-day modeling. Drops the heavy
# subsystems: no Cycles, no video editing, no USD/OpenVDB/Alembic/MaterialX,
# no LLVM. Keeps modeling, Eevee/Workbench, Python, image/color, fonts, subdiv.

include(${CMAKE_CURRENT_LIST_DIR}/android_features_common.cmake)

set(WITH_CYCLES OFF CACHE BOOL "" FORCE)
set(WITH_CYCLES_EMBREE OFF CACHE BOOL "" FORCE)
set(WITH_CODEC_FFMPEG OFF CACHE BOOL "" FORCE)
set(WITH_USD OFF CACHE BOOL "" FORCE)
set(WITH_MATERIALX OFF CACHE BOOL "" FORCE)
set(WITH_OPENVDB OFF CACHE BOOL "" FORCE)
set(WITH_ALEMBIC OFF CACHE BOOL "" FORCE)
set(WITH_LLVM OFF CACHE BOOL "" FORCE)
set(WITH_RUBBERBAND OFF CACHE BOOL "" FORCE)
