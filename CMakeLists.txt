cmake_minimum_required(VERSION 3.16)

project(tower VERSION 0.10.2 LANGUAGES C CXX)

find_package(CURL REQUIRED)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

file(GLOB_RECURSE TOWER_SOURCES CONFIGURE_DEPENDS
    src/*.cpp
)

file(GLOB_RECURSE TOWER_HEADERS CONFIGURE_DEPENDS
    include/*.h
)

add_executable(tower
    ${TOWER_SOURCES}
    ${TOWER_HEADERS}
    external/bme68x/bme68x.c
)

target_include_directories(tower PRIVATE
    include
    external
    external/bme68x
)

target_link_libraries(tower PRIVATE
    CURL::libcurl
    gpiod
    i2c
)
