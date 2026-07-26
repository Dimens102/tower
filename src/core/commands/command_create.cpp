#include <iostream>

#include "core/commands/device_handlers.h"
#include "devices/device_database.h"

int runCommandCreate(int argc, char* argv[])
{
    if (argc < 5)
    {
        std::cerr
            << "Usage: tower command create <device-id> <command-id>\n";

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

    for (const DeviceCommand& command : device.commands)
    {
        if (command.id == commandId)
        {
            std::cerr << "Command already exists.\n";
            return 1;
        }
    }

    DeviceCommand command;

    command.id = commandId;
    command.name = commandId;
    command.transport = TransportType::IR;
    command.enabled = true;

    device.commands.push_back(command);

    if (!db.saveDevice(device))
    {
        std::cerr << "Failed to create command.\n";
        return 1;
    }

    std::cout
        << "Created command '"
        << command.name
        << "' for device '"
        << device.id
        << "'.\n";

    return 0;
}