#include <iostream>
#include <string>

#include "core/commands/device_handlers.h"
#include "devices/device_database.h"

namespace
{
bool setCommandProperty(
    DeviceCommand& command,
    const std::string& property,
    const std::string& value)
{
    if (property == "name")
    {
        command.name = value;
        return true;
    }

    if (property == "transport")
    {
        if (value == "IR")
        {
            command.transport = TransportType::IR;
            return true;
        }

        if (value == "RF")
        {
            command.transport = TransportType::RF;
            return true;
        }

        return false;
    }

    if (property == "transportDevice")
    {
        command.transportDevice = value;
        return true;
    }

    if (property == "transportCommand")
    {
        command.transportCommand = value;
        return true;
    }

    if (property == "transmitter")
    {
        command.transmitter = value;
        return true;
    }

    if (property == "enabled")
    {
        command.enabled =
            (value == "true" ||
             value == "1" ||
             value == "yes");

        return true;
    }

    return false;
}
}

int runCommandSet(int argc, char* argv[])
{
    if (argc < 7)
    {
        std::cerr
            << "Usage: tower command set <device-id> <command-id> "
            << "<property> <value>\n";

        return 1;
    }

    DeviceDatabase db;
    Device device;

    if (!db.loadDevice(argv[3], device))
    {
        std::cerr << "Device not found.\n";
        return 1;
    }

    const std::string commandId = argv[4];
    const std::string property = argv[5];
    const std::string value = argv[6];

    for (DeviceCommand& command : device.commands)
    {
        if (command.id != commandId)
        {
            continue;
        }

        if (!setCommandProperty(command, property, value))
        {
            std::cerr
                << "Unknown command property or invalid value: "
                << property << "\n";

            return 1;
        }

        if (!db.saveDevice(device))
        {
            std::cerr << "Failed to save device.\n";
            return 1;
        }

        std::cout
            << "Updated command '" << command.id
            << "' for device '" << device.id
            << "': " << property
            << " = " << value << "\n";

        return 0;
    }

    std::cerr << "Command not found.\n";
    return 1;
}