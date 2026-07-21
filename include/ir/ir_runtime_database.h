#pragma once

#include <optional>
#include <string>

class IRRuntimeDatabase
{
public:
    std::optional<std::string> getLircDeviceForGpio(int gpio);
};