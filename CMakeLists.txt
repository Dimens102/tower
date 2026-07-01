cmake_minimum_required(VERSION 3.16)

project(tower VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(tower
    src/main.cpp
    src/core/gpio.cpp
    src/core/command.cpp
    src/core/rf_receiver.cpp
    src/commands/version.cpp
    src/commands/send.cpp
    src/commands/learn.cpp
    src/commands/replay.cpp
    src/commands/receive.cpp
    src/commands/config.cpp
    src/ir/ir_database.cpp
    src/ir/ir_receiver.cpp
)

target_include_directories(tower PRIVATE include)
target_link_libraries(tower PRIVATE gpiod)
