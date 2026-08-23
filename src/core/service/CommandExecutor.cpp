#include "core/service/CommandExecutor.h"

#include "devices/device.h"
#include "devices/device_database.h"
#include "devices/ir/ir_code.h"
#include "devices/ir/ir_database.h"
#include "devices/ir/ir_sender.h"
#include "devices/ir/ir_transmitter.h"
#include "devices/ir/ir_transmitter_database.h"
#include "devices/rf/rf_database.h"
#include "devices/rf/rf_device.h"
#include "devices/rf/rf_sender.h"

#include <algorithm>
#include <exception>

namespace
{
CommandExecutionResult result(
    CommandExecutionStatus status,
    const std::string& message,
    TransportType transport = TransportType::IR)
{
    CommandExecutionResult executionResult;
    executionResult.status = status;
    executionResult.transport = transport;
    executionResult.message = message;
    return executionResult;
}
}

CommandExecutionResult CommandExecutor::execute(
    const std::string& deviceId,
    const std::string& commandId)
{
    DeviceDatabase database;
    Device device;

    if (!database.deviceExists(deviceId))
    {
        return result(
            CommandExecutionStatus::DeviceNotFound,
            "Device not found: " + deviceId);
    }

    if (!database.loadDevice(deviceId, device))
    {
        return result(
            CommandExecutionStatus::DeviceLoadFailed,
            "Failed to load device: " + deviceId);
    }

    if (!device.enabled)
    {
        return result(
            CommandExecutionStatus::DeviceDisabled,
            "Device is disabled: " + deviceId);
    }

    for (const DeviceCommand& command : device.commands)
    {
        if (command.id == commandId)
        {
            return execute(command);
        }
    }

    return result(
        CommandExecutionStatus::CommandNotFound,
        "Command not found: " + deviceId + "." + commandId);
}

CommandExecutionResult CommandExecutor::execute(
    const std::string& deviceId,
    const std::string& commandId,
    const std::vector<std::string>& transmitters)
{
    if (transmitters.empty())
    {
        return execute(deviceId, commandId);
    }

    DeviceDatabase database;
    Device device;

    if (!database.deviceExists(deviceId))
    {
        return result(
            CommandExecutionStatus::DeviceNotFound,
            "Device not found: " + deviceId);
    }

    if (!database.loadDevice(deviceId, device))
    {
        return result(
            CommandExecutionStatus::DeviceLoadFailed,
            "Failed to load device: " + deviceId);
    }

    if (!device.enabled)
    {
        return result(
            CommandExecutionStatus::DeviceDisabled,
            "Device is disabled: " + deviceId);
    }

    const DeviceCommand* matchedCommand = nullptr;
    for (const DeviceCommand& command : device.commands)
    {
        if (command.id == commandId)
        {
            matchedCommand = &command;
            break;
        }
    }

    if (matchedCommand == nullptr)
    {
        return result(
            CommandExecutionStatus::CommandNotFound,
            "Command not found: " + deviceId + "." + commandId);
    }

    if (matchedCommand->transport != TransportType::IR)
    {
        return execute(*matchedCommand);
    }

    std::vector<std::string> attemptedTransmitters;
    std::vector<std::string> successfulTransmitters;
    std::vector<std::string> failedTransmitters;
    CommandExecutionResult lastFailure = result(
        CommandExecutionStatus::TransmissionFailed,
        "IR transmission failed.",
        TransportType::IR);

    for (const std::string& transmitterName : transmitters)
    {
        if (transmitterName.empty())
        {
            continue;
        }

        if (std::find(
                attemptedTransmitters.begin(),
                attemptedTransmitters.end(),
                transmitterName) != attemptedTransmitters.end())
        {
            continue;
        }
        attemptedTransmitters.push_back(transmitterName);

        DeviceCommand overridden = *matchedCommand;
        overridden.transmitter = transmitterName;
        const CommandExecutionResult execution = execute(overridden);
        if (execution.succeeded())
        {
            successfulTransmitters.push_back(transmitterName);
        }
        else
        {
            failedTransmitters.push_back(
                transmitterName + " (" + execution.message + ")");
            lastFailure = execution;
        }
    }

    if (attemptedTransmitters.empty())
    {
        return result(
            CommandExecutionStatus::InvalidMapping,
            "No valid IR transmitters were selected.",
            TransportType::IR);
    }

    if (!successfulTransmitters.empty())
    {
        std::string message = "IR execution complete on " +
            std::to_string(successfulTransmitters.size()) + "/" +
            std::to_string(attemptedTransmitters.size()) + " transmitter(s): ";

        for (std::size_t i = 0; i < successfulTransmitters.size(); ++i)
        {
            if (i > 0)
            {
                message += ", ";
            }
            message += successfulTransmitters[i];
        }

        if (!failedTransmitters.empty())
        {
            message += ". Failed: ";
            for (std::size_t i = 0; i < failedTransmitters.size(); ++i)
            {
                if (i > 0)
                {
                    message += "; ";
                }
                message += failedTransmitters[i];
            }
        }

        return result(
            CommandExecutionStatus::Success,
            message,
            TransportType::IR);
    }

    std::string message = "IR execution failed on all selected transmitters: ";
    for (std::size_t i = 0; i < failedTransmitters.size(); ++i)
    {
        if (i > 0)
        {
            message += "; ";
        }
        message += failedTransmitters[i];
    }

    return result(lastFailure.status, message, TransportType::IR);
}

CommandExecutionResult CommandExecutor::execute(
    const DeviceCommand& command)
{
    if (!command.enabled)
    {
        return result(
            CommandExecutionStatus::CommandDisabled,
            "Command is disabled: " + command.id,
            command.transport);
    }

    try
    {
        if (command.transport == TransportType::RF)
        {
            return executeRF(command);
        }

        return executeIR(command);
    }
    catch (const std::exception& error)
    {
        return result(
            CommandExecutionStatus::TransportDataInvalid,
            "Invalid transport data: " + std::string(error.what()),
            command.transport);
    }
}

CommandExecutionResult CommandExecutor::executeIR(
    const DeviceCommand& command)
{
    if (command.transportDevice.empty() ||
        command.transportCommand.empty() ||
        command.transmitter.empty())
    {
        return result(
            CommandExecutionStatus::InvalidMapping,
            "IR mapping requires transportDevice, transportCommand, and "
            "transmitter.",
            TransportType::IR);
    }

    IRDatabase irDatabase;
    IRCode code;

    if (!irDatabase.load(
            command.transportDevice,
            command.transportCommand,
            code))
    {
        return result(
            CommandExecutionStatus::TransportDataNotFound,
            "Failed to load IR command: " +
                command.transportDevice + "." +
                command.transportCommand,
            TransportType::IR);
    }

    Device transportDevice;
    DeviceDatabase deviceDatabase;
    unsigned int carrierKhz = 0;
    unsigned int dutyPercent = 0;
    if (deviceDatabase.deviceExists(command.transportDevice) &&
        deviceDatabase.loadDevice(command.transportDevice, transportDevice))
    {
        carrierKhz = transportDevice.irProfile.carrierKhz;
        dutyPercent = transportDevice.irProfile.dutyPercent;
        const auto transmitterDuty =
            transportDevice.irProfile.transmitterDutyPercent.find(command.transmitter);
        if (transmitterDuty != transportDevice.irProfile.transmitterDutyPercent.end())
            dutyPercent = transmitterDuty->second;
    }

    IRTransmitterDatabase transmitterDatabase;
    IRTransmitter transmitter;

    if (!transmitterDatabase.load(command.transmitter, transmitter))
    {
        return result(
            CommandExecutionStatus::TransportDataNotFound,
            "Failed to load IR transmitter: " + command.transmitter,
            TransportType::IR);
    }

    IRSender sender;

    if (!sender.send(code, transmitter, dutyPercent, carrierKhz))
    {
        return result(
            CommandExecutionStatus::TransmissionFailed,
            "IR transmission failed.",
            TransportType::IR);
    }

    return result(
        CommandExecutionStatus::Success,
        "IR execution complete.",
        TransportType::IR);
}

CommandExecutionResult CommandExecutor::executeRF(
    const DeviceCommand& command)
{
    if (command.transportDevice.empty() ||
        command.transportCommand.empty())
    {
        return result(
            CommandExecutionStatus::InvalidMapping,
            "RF mapping requires transportDevice and transportCommand.",
            TransportType::RF);
    }

    bool turnOn = false;

    if (command.transportCommand == "on")
    {
        turnOn = true;
    }
    else if (command.transportCommand != "off")
    {
        return result(
            CommandExecutionStatus::InvalidMapping,
            "RF transportCommand must be 'on' or 'off'.",
            TransportType::RF);
    }

    RFDatabase rfDatabase;
    RFDevice rfDevice;

    if (!rfDatabase.loadPowerDevice(
            command.transportDevice,
            rfDevice))
    {
        return result(
            CommandExecutionStatus::TransportDataNotFound,
            "Failed to load RF device: " + command.transportDevice,
            TransportType::RF);
    }

    RFSender sender;

    if (!sender.send(rfDevice, turnOn))
    {
        return result(
            CommandExecutionStatus::TransmissionFailed,
            "RF transmission failed.",
            TransportType::RF);
    }

    return result(
        CommandExecutionStatus::Success,
        "RF execution complete.",
        TransportType::RF);
}
