#include "core/commands/command_handlers.h"

#include "devices/controllers/ads1115.h"
#include "devices/sensors/bme688.h"
#include "devices/sensors/sensor.h"
#include "core/service/DeviceManager.h"

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
        std::make_unique<tower::controllers::ADS1115>());

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