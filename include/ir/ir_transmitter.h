#pragma once

#include <string>

struct IRTransmitter
{
     std::string name;
     std::string deviceName;
     std::string hardware;
     int gpio = 22;
     std::string status;
     std::string lircDevice;
};
