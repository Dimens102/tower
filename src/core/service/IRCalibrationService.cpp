#include "core/service/IRCalibrationService.h"

#include "devices/device.h"
#include "devices/device_database.h"
#include "devices/ir/ir_code.h"
#include "devices/ir/ir_database.h"
#include "devices/ir/ir_sender.h"
#include "devices/ir/ir_transmitter.h"
#include "devices/ir/ir_transmitter_database.h"

#include <algorithm>
#include <chrono>
#include <string>
#include <thread>
#include <vector>

namespace
{

constexpr const char* kCalibrationTransmitter =
    "Tower-IR-TX-001";

std::string defaultCalibrationCommand(
    const Device& device)
{
    const char* preferred[] = {
        "Volume Up",
        "Volume Down",
        "Program Up",
        "Program Down",
        "Channel Up",
        "Channel Down",
        "Temperature Up",
        "Temperature Down"
    };

    for (const char* name : preferred)
    {
        for (const DeviceCommand& command :
             device.commands)
        {
            if (command.transport == TransportType::IR &&
                command.id == name)
            {
                return command.id;
            }
        }
    }

    for (const DeviceCommand& command :
         device.commands)
    {
        if (command.transport == TransportType::IR &&
            command.id.find("Power") == std::string::npos)
        {
            return command.id;
        }
    }

    return {};
}

} // namespace

bool IRCalibrationService::prepare(
    const std::string& deviceName,
    IRCalibrationPreparation& preparation,
    std::string& error) const
{
    DeviceDatabase deviceDatabase;
    Device device;

    if (!deviceDatabase.loadDevice(
            deviceName,
            device))
    {
        error =
            "Could not load IR device '" +
            deviceName +
            "'.";
        return false;
    }

    IRDatabase irDatabase;

    preparation = {};
    preparation.transmitter =
        kCalibrationTransmitter;
    preparation.batchSize = 10;
    preparation.confirmThreshold = 8;
    preparation.alreadyCalibrated =
        device.irProfile.calibrated;
    preparation.existingCarrierKhz =
        device.irProfile.carrierKhz;
    preparation.existingDutyPercent =
        device.irProfile.dutyPercent;
    preparation.existingCommand =
        device.irProfile.calibrationCommand;

    for (const DeviceCommand& command :
         device.commands)
    {
        if (command.transport != TransportType::IR ||
            !command.enabled)
        {
            continue;
        }

        const std::string irCommand =
            command.transportCommand.empty()
                ? command.id
                : command.transportCommand;

        IRCode code;

        if (!irDatabase.load(
                deviceName,
                irCommand,
                code))
        {
            continue;
        }

        IRCalibrationCommandInfo info;
        info.id = command.id;
        info.description = command.description;
        info.carrierKhz =
            code.carrierKhz > 0
                ? code.carrierKhz
                : 38;

        preparation.commands.push_back(info);
    }

    if (preparation.commands.empty())
    {
        error =
            "No enabled learned IR commands are available "
            "for calibration.";
        return false;
    }

    preparation.suggestedCommand =
        defaultCalibrationCommand(device);

    if (preparation.suggestedCommand.empty())
    {
        preparation.suggestedCommand =
            preparation.commands.front().id;
    }

    if (!device.irProfile.calibrationCommand.empty())
    {
        const auto existing =
            std::find_if(
                preparation.commands.begin(),
                preparation.commands.end(),
                [&device](
                    const IRCalibrationCommandInfo& command)
                {
                    return
                        command.id ==
                        device.irProfile.calibrationCommand;
                });

        if (existing != preparation.commands.end())
        {
            preparation.suggestedCommand =
                device.irProfile.calibrationCommand;
        }
    }

    if (device.irProfile.dutyPercent >= 10 &&
        device.irProfile.dutyPercent <= 60)
    {
        preparation.dutyCandidates.push_back(
            device.irProfile.dutyPercent);
    }

    for (const unsigned int candidate :
         {33U, 40U, 50U, 60U})
    {
        if (std::find(
                preparation.dutyCandidates.begin(),
                preparation.dutyCandidates.end(),
                candidate) ==
            preparation.dutyCandidates.end())
        {
            preparation.dutyCandidates.push_back(
                candidate);
        }
    }

    error.clear();
    return true;
}

bool IRCalibrationService::sendBatch(
    const std::string& deviceName,
    const std::string& commandName,
    unsigned int carrierKhz,
    unsigned int dutyPercent,
    unsigned int count,
    unsigned int preDelaySeconds,
    unsigned int intervalMilliseconds,
    std::string& error) const
{
    if (carrierKhz < 20 || carrierKhz > 60)
    {
        error =
            "Calibration carrier must be between "
            "20 and 60 kHz.";
        return false;
    }

    if (dutyPercent < 10 || dutyPercent > 60)
    {
        error =
            "Normal calibration duty must be between "
            "10 and 60 percent.";
        return false;
    }

    if (count == 0 || count > 20)
    {
        error =
            "Calibration batch count must be between "
            "1 and 20.";
        return false;
    }

    if (preDelaySeconds > 10 ||
        intervalMilliseconds > 5000)
    {
        error =
            "Calibration timing request is outside "
            "the supported range.";
        return false;
    }

    DeviceDatabase deviceDatabase;
    Device device;

    if (!deviceDatabase.loadDevice(
            deviceName,
            device))
    {
        error =
            "Could not load IR device.";
        return false;
    }

    const auto command =
        std::find_if(
            device.commands.begin(),
            device.commands.end(),
            [&commandName](
                const DeviceCommand& item)
            {
                return
                    item.transport == TransportType::IR &&
                    item.enabled &&
                    item.id == commandName;
            });

    if (command == device.commands.end())
    {
        error =
            "Calibration command is not an enabled "
            "IR command on this device.";
        return false;
    }

    const std::string irCommand =
        command->transportCommand.empty()
            ? command->id
            : command->transportCommand;

    IRDatabase irDatabase;
    IRCode code;

    if (!irDatabase.load(
            deviceName,
            irCommand,
            code))
    {
        error =
            "Could not load learned IR command '" +
            irCommand +
            "'.";
        return false;
    }

    IRTransmitterDatabase transmitterDatabase;
    IRTransmitter transmitter;

    if (!transmitterDatabase.load(
            kCalibrationTransmitter,
            transmitter))
    {
        error =
            "Could not load Tower-IR-TX-001.";
        return false;
    }

    IRSender sender;

    if (preDelaySeconds > 0)
    {
        std::this_thread::sleep_for(
            std::chrono::seconds(
                preDelaySeconds));
    }

    for (unsigned int index = 0;
         index < count;
         ++index)
    {
        if (!sender.send(
                code,
                transmitter,
                dutyPercent,
                carrierKhz))
        {
            error =
                "IR transmission failed during "
                "calibration batch.";
            return false;
        }

        if (index + 1 < count &&
            intervalMilliseconds > 0)
        {
            std::this_thread::sleep_for(
                std::chrono::milliseconds(
                    intervalMilliseconds));
        }
    }

    error.clear();
    return true;
}

bool IRCalibrationService::saveProfile(
    const std::string& deviceName,
    const std::string& commandName,
    unsigned int carrierKhz,
    unsigned int dutyPercent,
    std::string& error) const
{
    if (carrierKhz < 20 || carrierKhz > 60 ||
        dutyPercent < 10 || dutyPercent > 60)
    {
        error =
            "Invalid calibration carrier or duty.";
        return false;
    }

    DeviceDatabase deviceDatabase;
    Device device;

    if (!deviceDatabase.loadDevice(
            deviceName,
            device))
    {
        error =
            "Could not load IR device for calibration save.";
        return false;
    }

    const auto command =
        std::find_if(
            device.commands.begin(),
            device.commands.end(),
            [&commandName](
                const DeviceCommand& item)
            {
                return
                    item.transport == TransportType::IR &&
                    item.enabled &&
                    item.id == commandName;
            });

    if (command == device.commands.end())
    {
        error =
            "Calibration command is not available "
            "on this device.";
        return false;
    }

    device.irProfile.calibrationCommand =
        commandName;
    device.irProfile.carrierKhz =
        carrierKhz;
    device.irProfile.dutyPercent =
        dutyPercent;
    device.irProfile.calibrated =
        true;

    device.irProfile.verifiedTransmitters = {
        kCalibrationTransmitter
    };
    device.irProfile.unreliableTransmitters.clear();
    device.irProfile.incompatibleTransmitters.clear();
    device.irProfile.transmitterDutyPercent.clear();

    if (!deviceDatabase.saveDevice(device))
    {
        error =
            "Could not save IR transmission calibration.";
        return false;
    }

    error.clear();
    return true;
}
