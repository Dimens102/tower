#include "commands/command_handlers.h"

#include <iomanip>
#include <iostream>
#include <memory>

#include "sensors/bme688.h"
#include "sensors/sensor_manager.h"

int runSensorCommand()
{
    tower::sensors::SensorManager sensorManager;

    sensorManager.registerSensor(
        std::make_unique<tower::sensors::BME688>());

    if (!sensorManager.initialize())
    {
        std::cerr << "Failed to initialize BME688.\n";
        return 1;
    }

    sensorManager.update();

    const auto& sensors = sensorManager.sensors();

    if (sensors.empty() || !sensors.front()->reading().valid)
    {
        std::cerr << "Failed to read BME688.\n";
        return 1;
    }

    std::cout << std::fixed << std::setprecision(2);

    std::cout
        << sensors.front()->name() << "\n\n"
        << "Temperature : " << sensorManager.temperature() << " C\n"
        << "Humidity    : " << sensorManager.humidity() << " %\n"
        << "Pressure    : " << sensorManager.pressure() << " hPa\n"
        << "Gas         : " << sensorManager.gasResistance() << " ohm\n";

    return 0;
}