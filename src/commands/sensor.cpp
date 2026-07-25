#include "commands/command_handlers.h"

#include "sensors/ads1115.h"
#include "sensors/bme688.h"
#include "sensors/sensor.h"
#include "service/DeviceManager.h"

#include <iomanip>
#include <iostream>
#include <memory>

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
    DeviceManager deviceManager;

    deviceManager.addDevice(
        std::make_unique<tower::sensors::BME688>());

    deviceManager.addDevice(
        std::make_unique<tower::sensors::ADS1115>());

    if (!deviceManager.initialize())
    {
        std::cerr
            << "One or more sensors failed to initialize.\n";
        return 1;
    }

    deviceManager.update();

    std::cout << std::fixed << std::setprecision(3);

    bool success = true;

    for (const auto& device : deviceManager.devices())
    {
        const auto* sensor =
            dynamic_cast<const tower::sensors::Sensor*>(
                device.get());

        if (sensor == nullptr)
        {
            continue;
        }

        printReading(*sensor);

        if (!sensor->reading().valid)
        {
            success = false;
        }
    }

    return success ? 0 : 1;
}