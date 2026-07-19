#include <iostream>

#include "devices/device_database.h"

int runCommandList(int argc, char* argv[])
{
    if (argc < 4)
    {
        std::cerr
            << "Usage: tower command list <device-id>\n";

        return 1;
    }

    DeviceDatabase db;
    Device device;

    if (!db.loadDevice(argv[3], device))
    {
        std::cerr << "Device not found.\n";
        return 1;
    }

    if (device.commands.empty())
    {
        std::cout
            << "No commands defined.\n";

        return 0;
    }

    for (const DeviceCommand& command : device.commands)
    {
        std::cout
            << command.id
            << "\n";
    }

    return 0;
}