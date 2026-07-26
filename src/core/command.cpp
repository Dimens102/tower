#include "core/command.h"

#include <cstring>

Command parseCommand(const char* text)
{
    if (text == nullptr) return Command::Unknown;

    if (std::strcmp(text, "version") == 0) return Command::Version;
    if (std::strcmp(text, "receive") == 0) return Command::Receive;
	if (std::strcmp(text, "monitor") == 0) return Command::Monitor;
	if (std::strcmp(text, "service") == 0) return Command::Service;
    if (std::strcmp(text, "send") == 0) return Command::Send;
    if (std::strcmp(text, "learn") == 0) return Command::Learn;
    if (std::strcmp(text, "learn-kernel") == 0) return Command::LearnKernel;
    if (std::strcmp(text, "replay") == 0) return Command::Replay;
    if (std::strcmp(text, "config") == 0) return Command::Config;
	if (std::strcmp(text, "sensor") == 0) return Command::Sensor;
	if (std::strcmp(text, "temperature") == 0) return Command::Temperature;
    if (std::strcmp(text, "device") == 0) return Command::Device;
    if (std::strcmp(text, "command") == 0) return Command::LogicalCommand;	
	if (std::strcmp(text, "execute") == 0) return Command::Execute;

    return Command::Unknown;
}
