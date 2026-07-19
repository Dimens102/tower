#include <iostream>
#include <string>

#include "commands/device_handlers.h"
#include "devices/device_database.h"

int runCommandDelete(int argc, char* argv[])
{
    if (argc < 5)
    {
        std::cerr
            << "Usage: tower command delete <device-id> <command-id>\n";

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

    for (auto it = device.commands.begin();
         it != device.commands.end();
         ++it)
    {
        if (it->id != commandId)
        {
            continue;
        }

        device.commands.erase(it);

        if (!db.saveDevice(device))
        {
            std::cerr << "Failed to save device.\n";
            return 1;
        }

        std::cout
            << "Deleted command '" << commandId
            << "' from device '" << device.id
            << "'.\n";

        return 0;
    }

    std::cerr << "Command not found.\n";
    return 1;
}