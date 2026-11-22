cmake_minimum_required(VERSION 3.15)
project(treeshake_test VERSION 1.0 LANGUAGES C)

# Provided by CMakeBuilder (-DDNTCM_CMAKE_DIR=...).
include(${DNTCM_CMAKE_DIR}/treeshake.cmake)

# Two libraries in one build directory: their keep-lists, build info records and
# tree-shaken artifacts must not collide.
foreach(_name IN ITEMS treeshake_test treeshake_test2)
  add_library(${_name} SHARED src/${_name}.c)
  target_compile_definitions(${_name} PUBLIC DART_SHARED_LIB)
  install(TARGETS ${_name} DESTINATION lib)
  dntcm_add_treeshake_target(NAME ${_name} TARGET ${_name})
endforeach()
