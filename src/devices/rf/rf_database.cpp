#include "devices/rf/rf_database.h"

#include <fstream>
#include <iostream>
#include <sstream>

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
