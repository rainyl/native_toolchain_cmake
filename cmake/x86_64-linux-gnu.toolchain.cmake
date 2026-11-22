set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

# Use the host compiler when the host already targets x86_64, otherwise use
# the cross toolchain wrapper (e.g. gcc-x86-64-linux-gnu on Debian/Ubuntu).
# This prevents a host compiler for another architecture (e.g. aarch64) from
# being used when cross-compiling to x86_64.
if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64|AMD64)$")
  # Leave CMAKE_C_COMPILER/CMAKE_CXX_COMPILER unset so CMake picks the
  # default host compiler (or honors CC/CXX).
else()
  set(CMAKE_C_COMPILER "x86_64-linux-gnu-gcc")
  set(CMAKE_CXX_COMPILER "x86_64-linux-gnu-g++")

  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
endif()

set(CMAKE_C_FLAGS "-march=x86-64")
set(CMAKE_CXX_FLAGS "-march=x86-64")

# cache flags
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS}" CACHE STRING "c flags")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}" CACHE STRING "c++ flags")
