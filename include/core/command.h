#pragma once

enum class Command
{
    Version,
    Receive,
    Send,
    Learn,
    Replay,
    Config,
    Unknown
};

Command parseCommand(const char* text);
