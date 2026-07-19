#pragma once

#include <string>
#include <vector>

#include "devices/device_command.h"

class Device
{
public:
    std::string id;

    std::string name;

    std::string type;

    std::string manufacturer;
    std::string model;

    std::string location;

    bool enabled = true;

    std::vector<std::string> aliases;

    std::vector<DeviceCommand> commands;
};