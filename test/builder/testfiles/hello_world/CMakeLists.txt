cmake_minimum_required(VERSION 3.11)
project(hello_world VERSION 1.0)

set(CMAKE_C_STANDARD 11)

add_executable(hello_world 
    src/hello_world.c
)
