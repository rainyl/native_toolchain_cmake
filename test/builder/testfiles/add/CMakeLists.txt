cmake_minimum_required(VERSION 3.11)
project(test_add VERSION 1.0 LANGUAGES C)

add_library(add SHARED src/add.c src/add.h)
target_compile_definitions(add PUBLIC DART_SHARED_LIB)
if(ANDROID)
    target_link_options(add PRIVATE "-Wl,-z,max-page-size=16384")
endif()

install(TARGETS add DESTINATION lib)
