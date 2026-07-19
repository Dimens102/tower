#include <iostream>

#include "commands/device_handlers.h"
#include "devices/device_database.h"

int runDeviceDelete(int argc, char* argv[])
{
    if (argc < 4)
    {
        std::cerr
            << "Usage: tower device delete <device-id>\n";
        return 1;
    }

    DeviceDatabase db;

    if (!db.deviceExists(argv[3]))
    {
        std::cerr << "Device not found.\n";
        return 1;
    }

    if (!db.deleteDevice(argv[3]))
    {
        std::cerr << "Failed to delete device.\n";
        return 1;
    }

    std::cout
        << "Deleted device '" << argv[3] << "'.\n";

    return 0;
}