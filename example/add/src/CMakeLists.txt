cmake_minimum_required(VERSION 3.11)
project(test_add VERSION 1.0 LANGUAGES C)

add_library(add SHARED src/add.c)
if(ANDROID)
    target_link_options(add PRIVATE "-Wl,-z,max-page-size=16384")
endif()

file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/add.txt" "This is a data asset!")

file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/assets")

file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/assets/asset1.txt" "asset1")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/assets/asset2.txt" "asset2")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/assets/asset3.txt" "asset3")

install(TARGETS add DESTINATION lib)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/add.txt" DESTINATION lib)
install(DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/assets/" DESTINATION assets)
