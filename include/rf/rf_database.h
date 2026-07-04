#pragma once

#include <string>

#include "rf/rf_device.h"

class RFDatabase
{
public:
    bool loadPowerDevice(const std::string& name, RFDevice& device);
};
