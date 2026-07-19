#include <iostream>
#include <string>

#include "commands/device_handlers.h"
#include "devices/device_database.h"
#include "devices/device_editor.h"

int runDeviceAlias(int argc, char* argv[])
{
    if (argc < 6)
    {
        std::cerr
            << "Usage:\n"
            << "  tower device alias add <device-id> <alias>\n"
            << "  tower device alias remove <device-id> <alias>\n";

        return 1;
    }

    std::string action = argv[3];
    std::string deviceId = argv[4];
    std::string alias = argv[5];

    DeviceDatabase db;
    Device device;

    if (!db.loadDevice(deviceId, device))
    {
        std::cerr << "Device not found.\n";
        return 1;
    }

    bool changed = false;

    if (action == "add")
    {
        changed = DeviceEditor::addAlias(device, alias);

        if (!changed)
        {
            std::cerr << "Alias is empty or already exists.\n";
            return 1;
        }
    }
    else if (action == "remove")
    {
        changed = DeviceEditor::removeAlias(device, alias);

        if (!changed)
        {
            std::cerr << "Alias not found.\n";
            return 1;
        }
    }
    else
    {
        std::cerr
            << "Unknown alias action: "
            << action << "\n";

        return 1;
    }

    if (!db.saveDevice(device))
    {
        std::cerr << "Failed to save device.\n";
        return 1;
    }

    std::cout
        << (action == "add" ? "Added" : "Removed")
        << " alias '" << alias
        << "' "
        << (action == "add" ? "to" : "from")
        << " device '" << device.id << "'.\n";

    return 0;
}