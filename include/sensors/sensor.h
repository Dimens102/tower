#pragma once

#include <string>

#include "sensors/sensor_reading.h"

namespace tower::sensors
{

class Sensor
{
public:
    virtual ~Sensor() = default;

    virtual bool initialize() = 0;
    virtual bool update() = 0;

    virtual bool available() const = 0;
    virtual const std::string& name() const = 0;
    virtual const SensorReading& reading() const = 0;
};

} // namespace tower::sensors