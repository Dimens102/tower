#include "core/command.h"

#include <cstring>

Command parseCommand(const char* text)
{
    if (text == nullptr) return Command::Unknown;

    if (std::strcmp(text, "version") == 0) return Command::Version;
    if (std::strcmp(text, "receive") == 0) return Command::Receive;
    if (std::strcmp(text, "send") == 0) return Command::Send;
    if (std::strcmp(text, "learn") == 0) return Command::Learn;
    if (std::strcmp(text, "replay") == 0) return Command::Replay;
    if (std::strcmp(text, "config") == 0) return Command::Config;

    return Command::Unknown;
}
