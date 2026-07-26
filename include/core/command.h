#pragma once

enum class Command
{
    Version,
    Receive,
    Monitor,
    Service,
    Send,
    Learn,
    LearnKernel,
    Replay,
    Config,
    Sensor,
	Temperature,
    Device,
    LogicalCommand,
    Execute,
    Unknown
};

Command parseCommand(const char* text);
