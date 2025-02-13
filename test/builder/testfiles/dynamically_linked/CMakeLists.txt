cmake_minimum_required(VERSION 3.11)
project(dynamically_linked VERSION 1.0)

set(CMAKE_C_STANDARD 11)

add_library(dynamically_linked SHARED 
    src/dynamically_linked.c
    src/math.c
    src/debug.c
)
