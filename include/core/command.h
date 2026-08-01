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
    IRReceivers,
    IRCapture,
    IRAnalyze,
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
