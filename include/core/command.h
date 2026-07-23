#pragma once

enum class Command
{
    Version,
    Receive,
	Monitor,
    Send,
    Learn,
    LearnKernel,
    Replay,
    Config,
	Sensor,
    Device,
	LogicalCommand,
    Execute,
    Unknown
};

Command parseCommand(const char* text);
