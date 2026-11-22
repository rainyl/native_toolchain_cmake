# Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
# Apache-2.0 license that can be found in the LICENSE file.

# Converts the plain keep-list written by the link hook
# (`CMakeBuilder.runLink` -> `dntcm_keep_symbols_<lib>.txt`, one C symbol per line) into
# the export file of the target platform. Run as a build step of
# `dntcm_add_treeshake_target` (see treeshake.cmake).
#
# Inputs:
#   DNTCM_KEEP_SYMBOLS - the keep-list (plain C symbol names)
#   DNTCM_EXPORTS      - the file to write
#   DNTCM_FORMAT       - msvc | apple | gnu

if (NOT DEFINED DNTCM_KEEP_SYMBOLS OR NOT DEFINED DNTCM_EXPORTS OR NOT DEFINED DNTCM_FORMAT)
  message(FATAL_ERROR "treeshake_symbols.cmake: DNTCM_KEEP_SYMBOLS, DNTCM_EXPORTS and DNTCM_FORMAT are required")
endif ()
if (NOT EXISTS "${DNTCM_KEEP_SYMBOLS}")
  message(FATAL_ERROR
    "The keep-list ${DNTCM_KEEP_SYMBOLS} does not exist. It is written by the link hook "
    "(`CMakeBuilder.runLink`), so this target can only be built from a link hook.")
endif ()

file(STRINGS "${DNTCM_KEEP_SYMBOLS}" _symbols)
set(_keep "")
foreach (_symbol IN LISTS _symbols)
  string(STRIP "${_symbol}" _symbol)
  if (_symbol)
    list(APPEND _keep "${_symbol}")
  endif ()
endforeach ()
if (NOT _keep)
  message(FATAL_ERROR "The keep-list ${DNTCM_KEEP_SYMBOLS} is empty")
endif ()

if (DNTCM_FORMAT STREQUAL "msvc")
  # x64 export names are unmangled.
  set(_content "EXPORTS\n")
  foreach (_symbol IN LISTS _keep)
    string(APPEND _content "    ${_symbol}\n")
  endforeach ()
elseif (DNTCM_FORMAT STREQUAL "apple")
  # Mach-O symbols carry a leading underscore; the keep-list holds plain C names.
  set(_content "")
  foreach (_symbol IN LISTS _keep)
    string(APPEND _content "_${_symbol}\n")
  endforeach ()
elseif (DNTCM_FORMAT STREQUAL "gnu")
  # A version script both restricts the exports and roots the listed symbols for
  # --gc-sections.
  set(_content "{\n  global:\n")
  foreach (_symbol IN LISTS _keep)
    string(APPEND _content "    ${_symbol};\n")
  endforeach ()
  string(APPEND _content "  local:\n    *;\n};\n")
else ()
  message(FATAL_ERROR "treeshake_symbols.cmake: unknown DNTCM_FORMAT '${DNTCM_FORMAT}'")
endif ()

get_filename_component(_directory "${DNTCM_EXPORTS}" DIRECTORY)
file(MAKE_DIRECTORY "${_directory}")
file(WRITE "${DNTCM_EXPORTS}" "${_content}")
