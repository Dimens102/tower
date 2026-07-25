#pragma once

#include <chrono>
#include <string>

struct TemperatureReading
{
    std::string sensorId;
    std::chrono::system_clock::time_point timestamp;
    double temperatureCelsius;
};