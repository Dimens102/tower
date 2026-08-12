#include "devices/device_database.h"

#include "nlohmann/json.hpp"

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

using json = nlohmann::ordered_json;

namespace
{
std::string transportToString(TransportType transport)
{
    switch (transport)
    {
        case TransportType::RF:
            return "RF";

        case TransportType::IR:
        default:
            return "IR";
    }
}

TransportType transportFromString(const std::string& transport)
{
    if (transport == "RF")
    {
        return TransportType::RF;
    }

    return TransportType::IR;
}
}

bool DeviceDatabase::loadDevice(const std::string& deviceId, Device& device)
{
    const std::filesystem::path file =
        std::filesystem::path("data") / "devices" / (deviceId + ".json");

    std::ifstream in(file);

    if (!in)
    {
        std::cerr << "Failed to open device file for reading: "
                  << file << "\n";
        return false;
    }

    try
    {
        json document;
        in >> document;

        device.id = deviceId;
        device.name = document.value("name", "");
        device.type = document.value("type", "");
        device.manufacturer = document.value("manufacturer", "");
        device.model = document.value("model", "");
        device.remoteName = document.value("remoteName", "");
        device.location = document.value("location", "");
        device.transmitter = document.value("transmitter", "");
        device.enabled = document.value("enabled", true);

        device.irProfile = {};
        if (document.contains("irProfile") && document["irProfile"].is_object())
        {
            const json& profile = document["irProfile"];
            device.irProfile.calibrated = profile.value("calibrated", false);
            device.irProfile.carrierKhz = profile.value("carrierKhz", 0U);
            device.irProfile.dutyPercent = profile.value("dutyPercent", 0U);
            if (profile.contains("transmitterDutyPercent") && profile["transmitterDutyPercent"].is_object())
                device.irProfile.transmitterDutyPercent = profile["transmitterDutyPercent"].get<std::map<std::string, unsigned int>>();
            device.irProfile.calibrationCommand = profile.value("calibrationCommand", "");
            if (profile.contains("verifiedTransmitters") && profile["verifiedTransmitters"].is_array())
                device.irProfile.verifiedTransmitters = profile["verifiedTransmitters"].get<std::vector<std::string>>();
            if (profile.contains("unreliableTransmitters") && profile["unreliableTransmitters"].is_array())
                device.irProfile.unreliableTransmitters = profile["unreliableTransmitters"].get<std::vector<std::string>>();
            if (profile.contains("incompatibleTransmitters") && profile["incompatibleTransmitters"].is_array())
                device.irProfile.incompatibleTransmitters = profile["incompatibleTransmitters"].get<std::vector<std::string>>();
        }

        device.aliases.clear();
        device.commands.clear();

        if (document.contains("aliases") &&
            document["aliases"].is_array())
        {
            device.aliases =
                document["aliases"].get<std::vector<std::string>>();
        }

        if (document.contains("commands") &&
            document["commands"].is_array())
        {
            for (const json& commandDocument : document["commands"])
            {
                DeviceCommand command;

                command.id =
                    commandDocument.value("id", "");

                command.name =
                    commandDocument.value("name", "");

                command.description =
                    commandDocument.value("description", "");

                command.transport =
                    transportFromString(
                        commandDocument.value("transport", "IR"));

                command.transportDevice =
                    commandDocument.value("transportDevice", "");

                command.transportCommand =
                    commandDocument.value("transportCommand", "");

                command.transmitter =
                    commandDocument.value("transmitter", "");

                command.enabled =
                    commandDocument.value("enabled", true);

                if (!command.id.empty())
                {
                    device.commands.push_back(command);
                }
            }
        }

        // Compatibility with device files created before the device-level
        // transmitter setting existed.  Infer it when every mapped IR
        // command already uses the same transmitter.
        if (device.transmitter.empty())
        {
            std::string inferred;
            bool conflicting = false;
            for (const DeviceCommand& command : device.commands)
            {
                if (command.transport != TransportType::IR ||
                    command.transmitter.empty())
                    continue;

                if (inferred.empty())
                    inferred = command.transmitter;
                else if (inferred != command.transmitter)
                    conflicting = true;
            }
            if (!conflicting) device.transmitter = inferred;
        }
    }
    catch (const json::exception& error)
    {
        std::cerr << "Failed to parse device JSON file: "
                  << file << "\n"
                  << error.what() << "\n";
        return false;
    }

    return true;
}

bool DeviceDatabase::saveDevice(const Device& device)
{
    const std::filesystem::path directory =
        std::filesystem::path("data") / "devices";

    std::filesystem::create_directories(directory);

    const std::filesystem::path file =
        directory / (device.id + ".json");

    json document;

    document["id"] = device.id;
    document["name"] = device.name;
    document["type"] = device.type;
    document["manufacturer"] = device.manufacturer;
    document["model"] = device.model;
    document["remoteName"] = device.remoteName;
    document["location"] = device.location;
    document["transmitter"] = device.transmitter;
    document["irProfile"] = {
        {"calibrated", device.irProfile.calibrated},
        {"carrierKhz", device.irProfile.carrierKhz},
        {"dutyPercent", device.irProfile.dutyPercent},
        {"transmitterDutyPercent", device.irProfile.transmitterDutyPercent},
        {"calibrationCommand", device.irProfile.calibrationCommand},
        {"verifiedTransmitters", device.irProfile.verifiedTransmitters},
        {"unreliableTransmitters", device.irProfile.unreliableTransmitters},
        {"incompatibleTransmitters", device.irProfile.incompatibleTransmitters}
    };
    document["enabled"] = device.enabled;
    document["aliases"] = device.aliases;
    document["commands"] = json::array();

    for (const DeviceCommand& command : device.commands)
    {
        json commandDocument;

        commandDocument["id"] = command.id;
        commandDocument["name"] = command.name;
        commandDocument["description"] = command.description;
        commandDocument["transport"] =
            transportToString(command.transport);

        commandDocument["transportDevice"] =
            command.transportDevice;

        commandDocument["transportCommand"] =
            command.transportCommand;

        commandDocument["transmitter"] =
            command.transmitter;

        commandDocument["enabled"] =
            command.enabled;

        document["commands"].push_back(commandDocument);
    }

    std::ofstream out(file);

    if (!out)
    {
        std::cerr << "Failed to open device file for writing: "
                  << file << "\n";
        return false;
    }

    out << document.dump(4) << "\n";

    return true;
}

bool DeviceDatabase::deleteDevice(const std::string& deviceId)
{
    const std::filesystem::path file =
        std::filesystem::path("data") / "devices" /
        (deviceId + ".json");

    std::error_code error;

    const bool removed =
        std::filesystem::remove(file, error);

    if (error)
    {
        std::cerr << "Failed to delete device file: "
                  << file << " (" << error.message() << ")\n";
        return false;
    }

    return removed;
}

bool DeviceDatabase::deviceExists(const std::string& deviceId)
{
    const std::filesystem::path file =
        std::filesystem::path("data") / "devices" /
        (deviceId + ".json");

    return std::filesystem::exists(file);
}

std::vector<std::string> DeviceDatabase::listDevices()
{
    std::vector<std::string> devices;

    const std::filesystem::path directory =
        std::filesystem::path("data") / "devices";

    if (!std::filesystem::exists(directory))
    {
        return devices;
    }

    for (const std::filesystem::directory_entry& entry :
         std::filesystem::directory_iterator(directory))
    {
        if (!entry.is_regular_file())
        {
            continue;
        }

        if (entry.path().extension() != ".json")
        {
            continue;
        }

        devices.push_back(entry.path().stem().string());
    }

    std::sort(devices.begin(), devices.end());

    return devices;
}
