#pragma once

#include "devices/TemperatureReading.h"

#include <cstddef>
#include <filesystem>

class TemperatureHistory
{
public:
    explicit TemperatureHistory(
        std::filesystem::path filePath,
        std::size_t maximumReadings = 504);

    bool store(const TemperatureReading& reading);

private:
    std::filesystem::path filePath_;
    std::size_t maximumReadings_;
};