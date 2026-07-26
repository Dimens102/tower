#pragma once

#include "devices/rf/rf_device.h"

class RFSender
{
public:
    bool send(const RFDevice& device, bool turnOn);
};
