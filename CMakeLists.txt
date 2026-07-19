cmake_minimum_required(VERSION 3.16)

project(tower VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(tower
    include/devices/device.h
    include/devices/device_database.h
    src/main.cpp
    src/core/gpio.cpp
    src/core/command.cpp
    src/core/rf_receiver.cpp
    src/commands/version.cpp
    src/commands/send.cpp
    src/commands/learn.cpp
    src/commands/learn_kernel.cpp
    src/commands/replay.cpp
    src/commands/receive.cpp
    src/commands/config.cpp
    src/commands/device.cpp
    src/commands/command.cpp
	src/commands/command_list.cpp
    src/commands/command_create.cpp
	src/commands/command_show.cpp
    src/commands/command_set.cpp
	src/commands/command_delete.cpp
	src/commands/device_list.cpp
	src/commands/device_show.cpp
	src/commands/device_create.cpp
	src/commands/device_set.cpp
	src/commands/device_alias.cpp
    src/commands/device_delete.cpp
    src/devices/device.cpp
	src/devices/device_database.cpp	
	src/devices/device_editor.cpp
    src/ir/ir_database.cpp
    src/ir/ir_transmitter_database.cpp
    src/ir/ir_sender.cpp
    src/ir/ir_receiver.cpp
    src/ir/ir_kernel_receiver.cpp
    src/rf/rf_database.cpp
    src/rf/rf_sender.cpp
)

target_include_directories(tower PRIVATE
    include
    external
)
target_link_libraries(tower PRIVATE gpiod)
