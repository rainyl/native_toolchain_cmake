# Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
# Apache-2.0 license that can be found in the LICENSE file.

# Adds a `<NAME>_treeshake` variant of an existing shared library that exports
# only the symbols listed in a keep-list file. The keep-list is written by the
# package's link hook (package:native_toolchain_cmake, `CMakeBuilder.runLink`),
# which is the only hook that knows which native functions the compiled Dart
# code actually uses.
#
# The target is excluded from the default build: it can only be linked once the
# keep-list exists, which is during the link hook. `CMakeBuilder.runLink` builds
# it (`cmake --build <build dir> --target <NAME>_treeshake`) and copies the
# staged library into the link hook's output directory.
#
# Usage, after the shared library target exists:
#
#   include(${DNTCM_CMAKE_DIR}/treeshake.cmake)
#   dntcm_add_treeshake_target(NAME mylib TARGET mylib)
#
# `DNTCM_CMAKE_DIR` is passed by `CMakeBuilder` (`-DDNTCM_CMAKE_DIR=<this dir>`).
#
# The tree-shaken library is staged in `${CMAKE_BINARY_DIR}/dntcm_treeshake/` as
# `<prefix><OUTPUT_NAME><suffix>` (e.g. `libmylib.so`), which is where `runLink`
# expects it. Exports are restricted per platform:
#   - Apple: `-exported_symbols_list` + `-dead_strip`
#   - ELF:   `--version-script` + `--gc-sections`
#   - MSVC:  `/DEF:` + `/OPT:REF` + `WINDOWS_EXPORT_ALL_SYMBOLS OFF`
# and the sources are compiled with one section per function/data item, so the
# unreachable ones can be garbage-collected.
#
# The target is *mirrored*: the properties of TARGET are copied onto the
# tree-shaken variant. That covers what a normal library target sets through
# `target_*` commands (sources, include directories, compile definitions/options,
# link libraries/options, link directories, standards, rpath, MSVC runtime), but
# not directory-scope settings (`add_compile_definitions`,
# `add_link_options`, ...) or the version/`DEBUG_POSTFIX` properties. A target
# that relies on those, or whose SOURCES contain generator expressions
# (`$<TARGET_OBJECTS:...>`), gets a warning - extend the copy list in
# _dntcm_mirror_target or configure the variant yourself.

if (DEFINED _DNTCM_TREESHAKE_CMAKE_INCLUDED)
  return ()
endif ()
set(_DNTCM_TREESHAKE_CMAKE_INCLUDED TRUE)
set_property(GLOBAL PROPERTY DNTCM_TREESHAKE_MODULE_DIR "${CMAKE_CURRENT_LIST_DIR}")

# Where the tree-shaken libraries and their export files are staged. The
# keep-list itself is one file per library (`dntcm_keep_symbols_<name>.txt`),
# written by the link hook; dntcm_add_treeshake_target defaults KEEP_SYMBOLS to
# that name. Keep both in sync with `lib/src/builder/build_info.dart`.
set(DNTCM_TREESHAKE_STAGE_DIR
  "${CMAKE_BINARY_DIR}/dntcm_treeshake"
  CACHE INTERNAL "Directory the tree-shaken libraries and their export files are staged in")

# dntcm_add_treeshake_target(
#   NAME <name>          # base name; the target is `<NAME>_treeshake`
#   TARGET <target>      # the existing shared library to mirror
#   [OUTPUT_NAME <name>] # base name of the staged library, defaults to <NAME>
#   [STAGE_DIR <dir>]    # defaults to DNTCM_TREESHAKE_STAGE_DIR
#   [KEEP_SYMBOLS <file>]# defaults to <build dir>/dntcm_keep_symbols_<OUTPUT_NAME>.txt
#   [NO_TRIM])           # do not add -ffunction-sections/... (already set)
function(dntcm_add_treeshake_target)
  cmake_parse_arguments(PARSE_ARGV 0 _arg "NO_TRIM" "NAME;TARGET;OUTPUT_NAME;STAGE_DIR;KEEP_SYMBOLS" "")
  if (NOT _arg_NAME OR NOT _arg_TARGET)
    message(FATAL_ERROR "dntcm_add_treeshake_target: NAME and TARGET are required")
  endif ()
  if (NOT TARGET ${_arg_TARGET})
    message(FATAL_ERROR "dntcm_add_treeshake_target: no such target: ${_arg_TARGET}")
  endif ()

  get_target_property(_type ${_arg_TARGET} TYPE)
  if (NOT _type STREQUAL "SHARED_LIBRARY")
    message(FATAL_ERROR "dntcm_add_treeshake_target: ${_arg_TARGET} is a ${_type}, expected SHARED_LIBRARY")
  endif ()
  get_target_property(_sources ${_arg_TARGET} SOURCES)
  if (NOT _sources)
    message(FATAL_ERROR "dntcm_add_treeshake_target: ${_arg_TARGET} has no sources to compile")
  endif ()

  set(_output_name "${_arg_OUTPUT_NAME}")
  if (NOT _output_name)
    set(_output_name "${_arg_NAME}")
  endif ()
  # One keep-list per library: several libraries can live in one build
  # directory, and their keep-lists differ.
  set(_keep_symbols "${_arg_KEEP_SYMBOLS}")
  if (NOT _keep_symbols)
    set(_keep_symbols "${CMAKE_BINARY_DIR}/dntcm_keep_symbols_${_output_name}.txt")
  endif ()
  set(_stage_dir "${_arg_STAGE_DIR}")
  if (NOT _stage_dir)
    set(_stage_dir "${DNTCM_TREESHAKE_STAGE_DIR}")
  endif ()

  set(_target "${_arg_NAME}_treeshake")

  # EXCLUDE_FROM_ALL: the target can only be built once the link hook has
  # written the keep-list, so it must not make a plain `cmake --build .` fail.
  add_library(${_target} SHARED EXCLUDE_FROM_ALL ${_sources})
  # A distinct file name: with the original OUTPUT_NAME the two targets would
  # write the same file, and the tree-shaken build would overwrite the
  # unrestricted library (which the link hook falls back to).
  set_target_properties(${_target} PROPERTIES OUTPUT_NAME "${_target}")

  # Mirror how the original target compiles and links. Usage requirements are
  # enough (nothing links against the tree-shaken library): the property values
  # already contain the original target's public and private settings.
  foreach (_pair "INCLUDE_DIRECTORIES;include_directories" "COMPILE_DEFINITIONS;compile_definitions"
                 "COMPILE_OPTIONS;compile_options" "LINK_LIBRARIES;link_libraries"
                 "LINK_OPTIONS;link_options")
    list(GET _pair 0 _property)
    list(GET _pair 1 _command)
    get_target_property(_value ${_arg_TARGET} ${_property})
    if (_value)
      if (_command STREQUAL "include_directories")
        target_include_directories(${_target} SYSTEM PRIVATE ${_value})
      elseif (_command STREQUAL "compile_definitions")
        target_compile_definitions(${_target} PRIVATE ${_value})
      elseif (_command STREQUAL "compile_options")
        target_compile_options(${_target} PRIVATE ${_value})
      elseif (_command STREQUAL "link_libraries")
        target_link_libraries(${_target} PRIVATE ${_value})
      elseif (_command STREQUAL "link_options")
        target_link_options(${_target} PRIVATE ${_value})
      endif ()
    endif ()
  endforeach ()
  foreach (_property LINK_DIRECTORIES COMPILE_FLAGS LINK_FLAGS POSITION_INDEPENDENT_CODE
                     C_STANDARD C_STANDARD_REQUIRED C_EXTENSIONS
                     CXX_STANDARD CXX_STANDARD_REQUIRED CXX_EXTENSIONS
                     C_VISIBILITY_PRESET CXX_VISIBILITY_PRESET
                     BUILD_RPATH INSTALL_RPATH BUILD_WITH_INSTALL_RPATH
                     MSVC_RUNTIME_LIBRARY)
    get_target_property(_value ${_arg_TARGET} ${_property})
    if (_value)
      set_target_properties(${_target} PROPERTIES ${_property} "${_value}")
    endif ()
  endforeach ()

  foreach (_source IN LISTS _sources)
    if (_source MATCHES "\\$<")
      message(WARNING
        "dntcm_add_treeshake_target: ${_arg_TARGET} has a generated source '${_source}'; "
        "the tree-shaken variant compiles the same source list and may fail or differ.")
    endif ()
  endforeach ()
  get_target_property(_link_dirs ${_arg_TARGET} LINK_DIRECTORIES)
  if (_link_dirs AND NOT _link_dirs STREQUAL "_link_dirs-NOTFOUND")
    message(STATUS "dntcm: copying LINK_DIRECTORIES ${_link_dirs} to ${_target}")
  endif ()

  if (NOT _arg_NO_TRIM)
    if (MSVC)
      # /Gy puts functions in COMDATs, /Gw does the same for data. Both are
      # needed so /OPT:REF can remove unreferenced functions *and* the data
      # they reference (e.g. large constant blobs).
      target_compile_options(${_target} PRIVATE /Gy /Gw)
    else ()
      target_compile_options(${_target} PRIVATE -ffunction-sections -fdata-sections)
    endif ()
  endif ()

  # The keep-list is a plain list of C symbols; each platform needs it in a
  # different shape, converted at build time (see treeshake_symbols.cmake) so
  # that a new keep-list relinks instead of reconfiguring.
  get_property(_module_dir GLOBAL PROPERTY DNTCM_TREESHAKE_MODULE_DIR)
  if (MSVC)
    set(_exports "${_stage_dir}/${_output_name}_exports.def")
    set(_format msvc)
  elseif (APPLE)
    set(_exports "${_stage_dir}/${_output_name}_exports.txt")
    set(_format apple)
  else ()
    set(_exports "${_stage_dir}/${_output_name}_exports.lds")
    set(_format gnu)
  endif ()

  add_custom_command(
    OUTPUT "${_exports}"
    COMMAND "${CMAKE_COMMAND}"
      "-DDNTCM_KEEP_SYMBOLS=${_keep_symbols}"
      "-DDNTCM_EXPORTS=${_exports}"
      "-DDNTCM_FORMAT=${_format}"
      -P "${_module_dir}/treeshake_symbols.cmake"
    DEPENDS "${_keep_symbols}"
    COMMENT "Restricting the exports of ${_target} to the symbols in ${_keep_symbols}"
    VERBATIM
  )
  add_custom_target(${_target}_exports DEPENDS "${_exports}")
  add_dependencies(${_target} ${_target}_exports)
  # Relink when the keep-list changes, not only when the sources change.
  set_property(TARGET ${_target} APPEND PROPERTY LINK_DEPENDS "${_exports}")

  if (MSVC)
    # WINDOWS_EXPORT_ALL_SYMBOLS would override the .def file.
    set_target_properties(${_target} PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS OFF)
    target_link_options(${_target} PRIVATE "/DEF:${_exports}" /OPT:REF /OPT:ICF)
  elseif (APPLE)
    target_link_options(${_target} PRIVATE
      "LINKER:-exported_symbols_list,${_exports}"
      "LINKER:-dead_strip")
  else ()
    target_link_options(${_target} PRIVATE
      "LINKER:--version-script=${_exports}"
      "LINKER:--gc-sections")
  endif ()

  # Stage the library under the name `runLink` looks for: the platform's
  # library file name of OUTPUT_NAME.
  set(_staged "${_stage_dir}/${CMAKE_SHARED_LIBRARY_PREFIX}${_output_name}${CMAKE_SHARED_LIBRARY_SUFFIX}")
  add_custom_command(TARGET ${_target} POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${_stage_dir}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different "$<TARGET_FILE:${_target}>" "${_staged}"
    COMMENT "Staging the tree-shaken library in ${_stage_dir}"
    VERBATIM
  )
  message(STATUS "dntcm: ${_target} exports only the symbols listed in ${_keep_symbols}")
endfunction()
