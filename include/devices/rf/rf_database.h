#pragma once

#include <string>
#include <vector>

#include "devices/rf/rf_device.h"

class RFDatabase
{
public:
    bool loadPowerDevice(const std::string& name, RFDevice& device);
    std::vector<RFDevice> listPowerDevices();
    bool savePowerDevice(const RFDevice& device, bool overwrite = false);
    bool updatePowerDeviceStatus(
        const std::string& name,
        const std::string& status);
    bool deletePowerDevice(const std::string& name);
};
