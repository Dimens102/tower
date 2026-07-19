#pragma once

#include <string>

#include "devices/device.h"

class DeviceEditor
{
public:
    static bool setProperty(
        Device& device,
        const std::string& property,
        const std::string& value);
    static bool addAlias(
        Device& device,
        const std::string& alias);

    static bool removeAlias(
        Device& device,
        const std::string& alias);
};