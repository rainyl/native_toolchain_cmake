cmake_minimum_required(VERSION 3.11)
project(test_add VERSION 1.0 LANGUAGES C)

if(EMSCRIPTEN)
  # WebAssembly build. The native_toolchain_cmake CMakeWasmBuilder expects an
  # executable named after the builder name, producing add.js/add.wasm.
  add_executable(add src/add.c)
  target_link_options(add PRIVATE
    "-sMODULARIZE=1"
    "-sEXPORT_NAME=addModule"
    "-sEXPORTED_FUNCTIONS=['_math_add']"
    "-sEXPORTED_RUNTIME_METHODS=['ccall','cwrap']"
    "-sENVIRONMENT=web"
    "-sALLOW_MEMORY_GROWTH=1"
    "-sFILESYSTEM=0"
    "-O3"
    "--no-entry"
  )
else()
  add_library(add SHARED src/add.c)
  if(ANDROID)
    target_link_options(add PRIVATE "-Wl,-z,max-page-size=16384")
  endif()

  install(TARGETS add DESTINATION lib)
endif()
