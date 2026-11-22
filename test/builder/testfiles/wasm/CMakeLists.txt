cmake_minimum_required(VERSION 3.11)
project(test_wasm_add VERSION 1.0 LANGUAGES C)

add_executable(add src/add.c)
target_link_options(add PRIVATE
  "-sMODULARIZE=1"
  "-sEXPORT_NAME=addModule"
  "-sEXPORTED_FUNCTIONS=['_add']"
  "-sEXPORTED_RUNTIME_METHODS=['ccall','cwrap']"
  "-sENVIRONMENT=web,node"
  "-sALLOW_MEMORY_GROWTH=1"
  "-sFILESYSTEM=0"
  "-O2"
  "--no-entry"
)
