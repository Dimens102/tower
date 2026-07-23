#include "sensors/sensor_manager.h"

#include <limits>
#include <utility>

namespace tower::sensors
{

bool SensorManager::initialize()
{
    bool success = true;

    for (auto& sensor : m_sensors)
    {
        if (!sensor->initialize())
        {
            success = false;
        }
    }

    return success;
}

void SensorManager::update()
{
    for (auto& sensor : m_sensors)
    {
        if (sensor->available())
        {
            sensor->update();
        }
    }
}

void SensorManager::registerSensor(
    std::unique_ptr<Sensor> sensor)
{
    m_sensors.push_back(std::move(sensor));
}

const std::vector<std::unique_ptr<Sensor>>&
SensorManager::sensors() const
{
    return m_sensors;
}

} // namespace tower::sensors
