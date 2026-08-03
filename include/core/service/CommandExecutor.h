#pragma once

#include <string>

#include "devices/device_command.h"

enum class CommandExecutionStatus
{
    Success,
    DeviceNotFound,
    DeviceLoadFailed,
    DeviceDisabled,
    CommandNotFound,
    CommandDisabled,
    InvalidMapping,
    TransportDataNotFound,
    TransportDataInvalid,
    TransmissionFailed
};

struct CommandExecutionResult
{
    CommandExecutionStatus status =
        CommandExecutionStatus::TransmissionFailed;

    TransportType transport = TransportType::IR;
    std::string message;

    bool succeeded() const
    {
        return status == CommandExecutionStatus::Success;
    }
};

class CommandExecutor
{
public:
    CommandExecutionResult execute(
        const std::string& deviceId,
        const std::string& commandId);

    CommandExecutionResult execute(
        const DeviceCommand& command);

private:
    CommandExecutionResult executeIR(
        const DeviceCommand& command);

    CommandExecutionResult executeRF(
        const DeviceCommand& command);
};
