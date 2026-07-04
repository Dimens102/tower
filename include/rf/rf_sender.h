#pragma once

#include "rf/rf_device.h"

class RFSender
{
public:
    bool send(const RFDevice& device, bool turnOn);
};
