#pragma once

#include <string>
#include <vector>

struct IRCode
{
    std::string device;
    std::string command;
    std::string protocol;
    std::string decodedProtocol;
    unsigned int address = 0;
    unsigned int decodedCommand = 0;
    unsigned int carrierKhz = 0;
    unsigned int receiverGpio = 0;
    std::string receiverModel;
    std::string sourceCapture;
    std::vector<unsigned int> pulses;
};
