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
    Unknown
};

Command parseCommand(const char* text);
