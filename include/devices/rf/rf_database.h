#pragma once

#include <string>
#include <vector>

#include "devices/rf/rf_device.h"

class RFDatabase
{
public:
    bool loadPowerDevice(const std::string& name, RFDevice& device);
    std::vector<RFDevice> listPowerDevices();
};
