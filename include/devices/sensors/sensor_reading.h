#pragma once

#include <chrono>
#include <string>
#include <vector>

namespace tower::sensors
{

struct SensorMeasurement
{
    std::string name;
    std::string unit;
    double value = 0.0;
};

struct SensorReading
{
    std::vector<SensorMeasurement> measurements;

    bool valid = false;

    std::chrono::steady_clock::time_point timestamp;
};

} // namespace tower::sensors
