cmake_minimum_required(VERSION 3.11)
project(defines)

add_executable(defines src/defines.c)
target_compile_definitions(defines PUBLIC FOO=BAR)
