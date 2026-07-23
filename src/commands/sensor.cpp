#include "commands/command_handlers.h"

#include <iomanip>
#include <iostream>
#include <memory>

#include "sensors/ads1115.h"
#include "sensors/bme688.h"
#include "sensors/sensor_manager.h"

namespace
{

void printReading(const tower::sensors::Sensor& sensor)
{
    const auto& reading = sensor.reading();

    std::cout << sensor.name() << "\n\n";

    if (!reading.valid)
    {
        std::cout << "No valid reading.\n\n";
        return;
    }

        for (const auto& value : reading.measurements)
    {
        std::cout
            << std::left
            << std::setw(12) << value.name
            << " : "
            << value.value
            << " "
            << value.unit
            << "\n";
    }

    std::cout << "\n";
}

} // namespace

int runSensorCommand()
{
    tower::sensors::SensorManager sensorManager;

    sensorManager.registerSensor(
        std::make_unique<tower::sensors::BME688>());

    sensorManager.registerSensor(
        std::make_unique<tower::sensors::ADS1115>());

    if (!sensorManager.initialize())
    {
        std::cerr
            << "One or more sensors failed to initialize.\n";
        return 1;
    }

    sensorManager.update();

    std::cout << std::fixed << std::setprecision(3);

    bool success = true;

    for (const auto& sensor : sensorManager.sensors())
    {
        printReading(*sensor);

        if (!sensor->reading().valid)
        {
            success = false;
        }
    }

    return success ? 0 : 1;
}
