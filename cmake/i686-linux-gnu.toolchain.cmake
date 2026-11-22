set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR i686)

# Use the host compiler when the host already targets 32-bit x86, otherwise
# use the cross toolchain wrapper (e.g. gcc-i686-linux-gnu on Debian/Ubuntu).
# This prevents a host compiler for another architecture (e.g. aarch64) from
# being used when cross-compiling to x86.
if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "^(i[3-6]86|x86)$")
  # Leave CMAKE_C_COMPILER/CMAKE_CXX_COMPILER unset so CMake picks the
  # default host compiler (or honors CC/CXX).
else()
  set(CMAKE_C_COMPILER "i686-linux-gnu-gcc")
  set(CMAKE_CXX_COMPILER "i686-linux-gnu-g++")

  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
endif()

set(CMAKE_C_FLAGS "-march=i686")
set(CMAKE_CXX_FLAGS "-march=i686")

# cache flags
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS}" CACHE STRING "c flags")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}" CACHE STRING "c++ flags")
