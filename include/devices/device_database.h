#pragma once

#include <string>
#include <vector>

#include "devices/device.h"



class DeviceDatabase
{
public:
    bool loadDevice(const std::string& deviceId, Device& device);

    bool saveDevice(const Device& device);

    bool deleteDevice(const std::string& deviceId);

    bool deviceExists(const std::string& deviceId);

    std::vector<std::string> listDevices();
};