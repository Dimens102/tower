#pragma once

#include <chrono>
#include <string>

namespace tower::sensors
{

struct SensorReading
{
    double temperatureC = 0.0;
    double humidityPercent = 0.0;
    double pressureHpa = 0.0;
    double gasResistanceOhms = 0.0;

    bool valid = false;

    std::chrono::steady_clock::time_point timestamp;
};

} // namespace tower::sensors