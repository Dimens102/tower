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
    Unknown
};

Command parseCommand(const char* text);
