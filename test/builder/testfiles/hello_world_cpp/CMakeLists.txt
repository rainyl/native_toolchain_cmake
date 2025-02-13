cmake_minimum_required(VERSION 3.11)
project(hello_world_cpp VERSION 1.0 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 11)

add_executable(hello_world_cpp 
    src/hello_world_cpp.cc
)
