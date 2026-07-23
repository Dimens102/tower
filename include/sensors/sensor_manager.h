#pragma once

#include <memory>
#include <vector>

#include "sensors/sensor.h"

namespace tower::sensors
{

class SensorManager
{
public:
    bool initialize();
    void update();

    void registerSensor(std::unique_ptr<Sensor> sensor);

    const std::vector<std::unique_ptr<Sensor>>& sensors() const;

    double temperature() const;
    double humidity() const;
    double pressure() const;
    double gasResistance() const;

private:
    std::vector<std::unique_ptr<Sensor>> m_sensors;
};

} // namespace tower::sensors