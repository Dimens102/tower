cmake_minimum_required(VERSION 3.16)

project(tower VERSION 0.1.0 LANGUAGES CXX)

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
)

target_include_directories(tower PRIVATE
    include
    external
)
target_link_libraries(tower PRIVATE gpiod)
