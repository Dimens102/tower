#pragma once

#include <string>

enum class TransportType
{
    IR,
    RF
};

class DeviceCommand
{
public:
    std::string id;
    std::string name;
    std::string description;

    TransportType transport = TransportType::IR;

    std::string transportDevice;
    std::string transportCommand;

    std::string transmitter;

    bool enabled = true;
};
