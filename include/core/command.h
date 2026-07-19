#pragma once

enum class Command
{
    Version,
    Receive,
    Send,
    Learn,
    LearnKernel,
    Replay,
    Config,
    Device,
	LogicalCommand,
    Execute,
    Unknown
};

Command parseCommand(const char* text);
