#include "ir/ir_transmitter_database.h"

#include <filesystem>
#include <fstream>

bool IRTransmitterDatabase::load(const std::string& name, IRTransmitter& transmitter)
{
    std::filesystem::path file =
        std::filesystem::path("data") /
        "ir" /
        "transmitters" /
        (name + ".irtx");

    std::ifstream in(file);

    if (!in)
    {
        return false;
    }

    std::string line;

    while (std::getline(in, line))
    {
        auto pos = line.find('=');

        if (pos == std::string::npos)
            continue;

        std::string key = line.substr(0, pos);
        std::string value = line.substr(pos + 1);

        if (key == "name")
            transmitter.name = value;
        else if (key == "friendly_name")
            transmitter.friendlyName = value;
        else if (key == "hardware")
            transmitter.hardware = value;
        else if (key == "gpio")
            transmitter.gpio = std::stoi(value);
        else if (key == "location")
            transmitter.location = value;
        else if (key == "status")
            transmitter.status = value;
    }

    return true;
}
