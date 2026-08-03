#include "devices/rf/rf_database.h"

#include <fstream>
#include <iostream>
#include <sstream>
#include <algorithm>
#include <filesystem>
#include <vector>

static void applyKeyValue(RFDevice& device, const std::string& key, const std::string& value)
{
    if (key == "name") device.name = value;
    else if (key == "protocol") device.protocol = value;
    else if (key == "description") device.description = value;
    else if (key == "house") device.house = value;
    else if (key == "unit") device.unit = std::stoi(value);
    else if (key == "gpio") device.gpio = std::stoi(value);
    else if (key == "pulse") device.pulse = std::stoi(value);
    else if (key == "repeat") device.repeat = std::stoi(value);
    else if (key == "on") device.onCode = std::stoul(value);
    else if (key == "off") device.offCode = std::stoul(value);
    else if (key == "transmitter_id") device.transmitterId = value;
    else if (key == "status") device.status = value;
    else if (key == "device_name") device.deviceName = value;
}

bool RFDatabase::loadPowerDevice(const std::string& name, RFDevice& device)
{
    std::string path = "data/rf/power/" + name + ".rf";
    std::ifstream file(path);

    if (!file)
    {
        std::cerr << "Failed to open RF device file: " << path << "\n";
        return false;
    }

    std::string line;

    while (std::getline(file, line))
    {
        if (line.empty()) continue;

        std::size_t pos = line.find('=');

        if (pos == std::string::npos) continue;

        std::string key = line.substr(0, pos);
        std::string value = line.substr(pos + 1);

        applyKeyValue(device, key, value);
    }

    return true;
}

std::vector<RFDevice> RFDatabase::listPowerDevices()
{
    std::vector<RFDevice> devices;
    const std::filesystem::path directory = "data/rf/power";

    if (!std::filesystem::exists(directory))
    {
        return devices;
    }

    for (const auto& entry : std::filesystem::directory_iterator(directory))
    {
        if (!entry.is_regular_file() || entry.path().extension() != ".rf")
        {
            continue;
        }

        RFDevice device;
        if (loadPowerDevice(entry.path().stem().string(), device))
        {
            devices.push_back(std::move(device));
        }
    }

    std::sort(
        devices.begin(),
        devices.end(),
        [](const RFDevice& left, const RFDevice& right)
        {
            return left.name < right.name;
        });

    return devices;
}
