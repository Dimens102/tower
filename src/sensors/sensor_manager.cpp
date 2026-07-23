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

void SensorManager::registerSensor(std::unique_ptr<Sensor> sensor)
{
    m_sensors.push_back(std::move(sensor));
}

const std::vector<std::unique_ptr<Sensor>>& SensorManager::sensors() const
{
    return m_sensors;
}

double SensorManager::temperature() const
{
    for (const auto& sensor : m_sensors)
    {
        if (sensor->reading().valid)
        {
            return sensor->reading().temperatureC;
        }
    }

    return std::numeric_limits<double>::quiet_NaN();
}

double SensorManager::humidity() const
{
    for (const auto& sensor : m_sensors)
    {
        if (sensor->reading().valid)
        {
            return sensor->reading().humidityPercent;
        }
    }

    return std::numeric_limits<double>::quiet_NaN();
}

double SensorManager::pressure() const
{
    for (const auto& sensor : m_sensors)
    {
        if (sensor->reading().valid)
        {
            return sensor->reading().pressureHpa;
        }
    }

    return std::numeric_limits<double>::quiet_NaN();
}

double SensorManager::gasResistance() const
{
    for (const auto& sensor : m_sensors)
    {
        if (sensor->reading().valid)
        {
            return sensor->reading().gasResistanceOhms;
        }
    }

    return std::numeric_limits<double>::quiet_NaN();
}

} // namespace tower::sensors