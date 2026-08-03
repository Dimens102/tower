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

    if (!sender.send(code, transmitter))
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
