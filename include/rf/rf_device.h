#pragma once

#include <string>

struct RFDevice
{
    std::string name;
    std::string protocol;
    std::string description;
    std::string house;
    int unit = 0;
    int gpio = 24;
    int pulse = 350;
    int repeat = 16;
    unsigned long onCode = 0;
    unsigned long offCode = 0;
    std::string transmitterId;
    std::string status;
};
