#include <iostream>

#include "core/commands/device_handlers.h"
#include "devices/device_database.h"

int runDeviceShow(int argc, char* argv[])
{
    if (argc < 4)
    {
        std::cerr << "Usage: tower device show <device-id>\n";
        return 1;
    }

    DeviceDatabase db;
    Device device;

    if (!db.loadDevice(argv[3], device))
    {
        std::cerr << "Device not found.\n";
        return 1;
    }

    std::cout << "ID:           " << device.id << "\n";
    std::cout << "Name:         " << device.name << "\n";
    std::cout << "Type:         " << device.type << "\n";
    std::cout << "Manufacturer: " << device.manufacturer << "\n";
    std::cout << "Model:        " << device.model << "\n";
    std::cout << "Remote:       " << device.remoteName << "\n";
    std::cout << "Location:     " << device.location << "\n";
    std::cout << "Transmitter:  " << device.transmitter << "\n";
    std::cout << "Enabled:      "
              << (device.enabled ? "Yes" : "No") << "\n";

    if (!device.aliases.empty())
    {
        std::cout << "Aliases:      ";

        for (std::size_t i = 0; i < device.aliases.size(); ++i)
        {
            if (i > 0)
            {
                std::cout << ", ";
            }

            std::cout << device.aliases[i];
        }

        std::cout << "\n";
    }

    return 0;
}
