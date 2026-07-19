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
        device.location = document.value("location", "");
        device.enabled = document.value("enabled", true);

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
    document["location"] = device.location;
    document["enabled"] = device.enabled;
    document["aliases"] = device.aliases;
    document["commands"] = json::array();

    for (const DeviceCommand& command : device.commands)
    {
        json commandDocument;

        commandDocument["id"] = command.id;
        commandDocument["name"] = command.name;
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