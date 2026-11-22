set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR riscv64)

# Use the host compiler when the host already targets riscv64, otherwise use
# the cross toolchain wrapper (e.g. gcc-riscv64-linux-gnu on Debian/Ubuntu).
if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "^(riscv64|RISCV64)$")
  # Leave CMAKE_C_COMPILER/CMAKE_CXX_COMPILER unset so CMake picks the
  # default host compiler (or honors CC/CXX).
else()
  set(CMAKE_C_COMPILER "riscv64-linux-gnu-gcc")
  set(CMAKE_CXX_COMPILER "riscv64-linux-gnu-g++")

  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
endif()

set(CMAKE_C_FLAGS "-march=rv64gc")
set(CMAKE_CXX_FLAGS "-march=rv64gc")

# cache flags
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS}" CACHE STRING "c flags")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}" CACHE STRING "c++ flags")
