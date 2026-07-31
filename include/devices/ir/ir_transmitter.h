#pragma once

#include <string>

struct IRTransmitter
{
    std::string name;
    std::string friendlyName;
    std::string hardware;
    int gpio = -1;
    std::string controller;
    int output = -1;
    std::string location;
    std::string status;
    // Temporary until runtime GPIO discovery is implemented.
    std::string lircDevice;
};
