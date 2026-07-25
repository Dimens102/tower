#pragma once

#include <string>

#include "service/ManagedDevice.h"
#include "sensors/sensor_reading.h"

namespace tower::sensors
{

class Sensor : public ManagedDevice
{
public:
    ~Sensor() override = default;

    virtual const SensorReading& reading() const = 0;
};

} // namespace tower::sensors