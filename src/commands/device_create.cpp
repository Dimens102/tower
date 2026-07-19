#include <iostream>

#include "commands/device_handlers.h"
#include "devices/device_database.h"

int runDeviceCreate(int argc, char* argv[])
{
    if (argc < 4)
    {
        std::cerr << "Usage: tower device create <device-id>\n";
        return 1;
    }

    DeviceDatabase db;

    if (db.deviceExists(argv[3]))
    {
        std::cerr << "Device already exists.\n";
        return 1;
    }

    Device device;

    device.id = argv[3];
    device.name = argv[3];
    device.enabled = true;

    if (!db.saveDevice(device))
    {
        std::cerr << "Failed to create device.\n";
        return 1;
    }

    std::cout << "Created device '" << device.name << "'.\n";

    return 0;
}