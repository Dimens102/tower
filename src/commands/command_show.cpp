#include <iostream>
#include <string>

#include "commands/device_handlers.h"
#include "devices/device_database.h"

namespace
{
std::string transportToString(TransportType transport)
{
    switch (transport)
    {
        case TransportType::RF:
            return "RF";

        case TransportType::IR:
        default:
            return "IR";
    }
}
}

int runCommandShow(int argc, char* argv[])
{
    if (argc < 5)
    {
        std::cerr
            << "Usage: tower command show <device-id> <command-id>\n";

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
        if (command.id != commandId)
        {
            continue;
        }

        std::cout << "ID:                " << command.id << "\n";
        std::cout << "Name:              " << command.name << "\n";
        std::cout << "Transport:         "
                  << transportToString(command.transport) << "\n";
        std::cout << "Transport device:  "
                  << command.transportDevice << "\n";
        std::cout << "Transport command: "
                  << command.transportCommand << "\n";
        std::cout << "Transmitter:       "
                  << command.transmitter << "\n";
        std::cout << "Enabled:           "
                  << (command.enabled ? "Yes" : "No") << "\n";

        return 0;
    }

    std::cerr << "Command not found.\n";
    return 1;
}