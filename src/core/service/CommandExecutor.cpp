#include "core/service/CommandExecutor.h"
#include "core/service/DeviceStateService.h"

#include "core/service/ExecutionDisplay.h"

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

void publishExecution(
    const DeviceCommand& command,
    const CommandExecutionResult& execution)
{
    ExecutionDisplay::publish({
        command.transport == TransportType::IR
            ? "IR command"
            : "RF command",
        command.transportDevice,
        command.name.empty() ? command.id : command.name,
        execution.succeeded()
            ? "OK - command sent"
            : "FAILED - not sent",
        execution.succeeded(),
        5,
    });
}
}

CommandExecutionResult CommandExecutor::executeRaw(
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
            return executeRaw(command);
        }
    }

    return result(
        CommandExecutionStatus::CommandNotFound,
        "Command not found: " + deviceId + "." + commandId);
}

CommandExecutionResult CommandExecutor::executeRaw(
    const std::string& deviceId,
    const std::string& commandId,
    const std::vector<std::string>& transmitters)
{
    if (transmitters.empty())
    {
        return executeRaw(deviceId, commandId);
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

    const auto publishAndReturn =
        [matchedCommand](CommandExecutionResult execution)
        {
            publishExecution(*matchedCommand, execution);
            return execution;
        };

    if (matchedCommand->transport != TransportType::IR)
    {
        return executeRaw(*matchedCommand);
    }

    std::vector<std::string> attemptedTransmitters;
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
    }

    if (attemptedTransmitters.empty())
    {
        return publishAndReturn(result(
            CommandExecutionStatus::InvalidMapping,
            "No valid IR transmitters were selected.",
            TransportType::IR));
    }

    // Two or more Pico outputs must receive one frame. Sending a complete
    // toggle command to each output in sequence can toggle a device on and
    // immediately back off.
    if (attemptedTransmitters.size() >= 2)
    {
        IRTransmitterDatabase transmitterDatabase;
        std::vector<IRTransmitter> synchronizedTransmitters;
        bool allUseTowerPico = true;

        for (const std::string& transmitterName : attemptedTransmitters)
        {
            IRTransmitter transmitter;
            if (!transmitterDatabase.load(transmitterName, transmitter))
            {
                return publishAndReturn(result(
                    CommandExecutionStatus::TransportDataNotFound,
                    "Failed to load IR transmitter: " + transmitterName,
                    TransportType::IR));
            }

            if (transmitter.controller != "tower-pico")
            {
                allUseTowerPico = false;
                break;
            }

            synchronizedTransmitters.push_back(transmitter);
        }

        if (allUseTowerPico)
        {
            IRDatabase irDatabase;
            IRCode code;
            if (!irDatabase.load(
                    matchedCommand->transportDevice,
                    matchedCommand->transportCommand,
                    code))
            {
                return publishAndReturn(result(
                    CommandExecutionStatus::TransportDataNotFound,
                    "Failed to load IR command: " +
                        matchedCommand->transportDevice + "." +
                        matchedCommand->transportCommand,
                    TransportType::IR));
            }

            Device transportDevice;
            DeviceDatabase transportDeviceDatabase;
            unsigned int carrierKhz = 0;
            unsigned int dutyPercent = 0;
            if (transportDeviceDatabase.deviceExists(
                    matchedCommand->transportDevice) &&
                transportDeviceDatabase.loadDevice(
                    matchedCommand->transportDevice,
                    transportDevice))
            {
                carrierKhz = transportDevice.irProfile.carrierKhz;
                dutyPercent = transportDevice.irProfile.dutyPercent;

                bool firstDuty = true;
                unsigned int synchronizedDuty = dutyPercent;
                for (const std::string& transmitterName : attemptedTransmitters)
                {
                    unsigned int transmitterDuty = dutyPercent;
                    const auto overrideDuty =
                        transportDevice.irProfile.transmitterDutyPercent.find(
                            transmitterName);
                    if (overrideDuty !=
                        transportDevice.irProfile.transmitterDutyPercent.end())
                    {
                        transmitterDuty = overrideDuty->second;
                    }

                    if (firstDuty)
                    {
                        synchronizedDuty = transmitterDuty;
                        firstDuty = false;
                    }
                    else if (transmitterDuty != synchronizedDuty)
                    {
                        return publishAndReturn(result(
                            CommandExecutionStatus::InvalidMapping,
                            "Synchronized Pico outputs must use the same IR "
                            "duty percentage.",
                            TransportType::IR));
                    }
                }
                dutyPercent = synchronizedDuty;
            }

            IRSender sender;
            if (!sender.sendSynchronized(
                    code,
                    synchronizedTransmitters,
                    dutyPercent,
                    carrierKhz))
            {
                return publishAndReturn(result(
                    CommandExecutionStatus::TransmissionFailed,
                    "Synchronized IR broadcast failed.",
                    TransportType::IR));
            }

            std::string message =
                "Synchronized IR broadcast complete on " +
                std::to_string(attemptedTransmitters.size()) +
                " transmitter(s): ";
            for (std::size_t index = 0;
                 index < attemptedTransmitters.size();
                 ++index)
            {
                if (index > 0)
                {
                    message += ", ";
                }
                message += attemptedTransmitters[index];
            }

            return publishAndReturn(result(
                CommandExecutionStatus::Success,
                message,
                TransportType::IR));
        }
    }

    std::vector<std::string> successfulTransmitters;
    std::vector<std::string> failedTransmitters;
    CommandExecutionResult lastFailure = result(
        CommandExecutionStatus::TransmissionFailed,
        "IR transmission failed.",
        TransportType::IR);

    for (const std::string& transmitterName : attemptedTransmitters)
    {

        DeviceCommand overridden = *matchedCommand;
        overridden.transmitter = transmitterName;
        const CommandExecutionResult execution = executeRaw(overridden);
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

CommandExecutionResult CommandExecutor::executeRaw(
    const DeviceCommand& command)
{
    if (!command.enabled)
    {
        const CommandExecutionResult execution = result(
            CommandExecutionStatus::CommandDisabled,
            "Command is disabled: " + command.id,
            command.transport);
        publishExecution(command, execution);
        return execution;
    }

    CommandExecutionResult execution;
    try
    {
        if (command.transport == TransportType::RF)
        {
            execution = executeRF(command);
        }
        else
        {
            execution = executeIR(command);
        }
    }
    catch (const std::exception& error)
    {
        execution = result(
            CommandExecutionStatus::TransportDataInvalid,
            "Invalid transport data: " + std::string(error.what()),
            command.transport);
    }

    publishExecution(command, execution);
    return execution;
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

CommandExecutionResult CommandExecutor::execute(const std::string& device, const std::string& command) {
    return execute(device, command, {});
}
CommandExecutionResult CommandExecutor::execute(const std::string& device, const std::string& command, const std::vector<std::string>& outputs) {
    CommandExecutionResult r;
    try {
        DeviceDatabase db; Device d; std::string key="ir:"+device, effectCommand=command;
        if(db.loadDevice(device,d)) for(const auto& c:d.commands) if(c.id==command) {
            key=(c.transport==TransportType::RF?"rf:":"ir:")+c.transportDevice; effectCommand=c.transportCommand; break;
        }
        r=result(CommandExecutionStatus::Success,"Disabled device skipped; no signal sent");
        DeviceStateService::track(key, effectCommand, [&]{r=executeRaw(device,command,outputs);return r.succeeded();});
    } catch(const std::exception& e) {r.status=CommandExecutionStatus::TransmissionFailed;r.message=e.what();}
    return r;
}
CommandExecutionResult CommandExecutor::execute(const DeviceCommand& command) {
    CommandExecutionResult r;
    try {
        r=result(CommandExecutionStatus::Success,"Disabled device skipped; no signal sent",command.transport);
        DeviceStateService::track((command.transport==TransportType::RF?"rf:":"ir:")+command.transportDevice, command.transportCommand,
            [&]{r=executeRaw(command);return r.succeeded();});
    } catch(const std::exception& e) {r.status=CommandExecutionStatus::TransmissionFailed;r.message=e.what();}
    return r;
}
