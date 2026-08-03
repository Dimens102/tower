#pragma once

#include <string>

class RFCommandService
{
public:
    bool send(
        const std::string& deviceName,
        const std::string& action,
        std::string& error);
};
