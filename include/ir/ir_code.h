#pragma once

#include <string>
#include <vector>

struct IRCode
{
    std::string device;
    std::string command;
    std::string protocol;
    std::vector<unsigned int> pulses;
};
