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

    // Physical handset used to record this logical device's IR commands.
    std::string remoteName;

    std::string location;

    // Default IR output for every command on this device.  Individual
    // commands retain their transmitter field for exceptional overrides.
    std::string transmitter;

    bool enabled = true;

    std::vector<std::string> aliases;

    std::vector<DeviceCommand> commands;
};
