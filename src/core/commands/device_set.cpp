#include <iostream>

#include "core/commands/device_handlers.h"
#include "devices/device_database.h"
#include "devices/device_editor.h"

int runDeviceSet(int argc, char* argv[])
{
    if (argc < 6)
    {
        std::cerr
            << "Usage: tower device set <device-id> <property> <value>\n";
        return 1;
    }

    DeviceDatabase db;
    Device device;

    if (!db.loadDevice(argv[3], device))
    {
        std::cerr << "Device not found.\n";
        return 1;
    }

    if (!DeviceEditor::setProperty(device, argv[4], argv[5]))
    {
        std::cerr
            << "Unknown device property: "
            << argv[4] << "\n";
        return 1;
    }

    if (!db.saveDevice(device))
    {
        std::cerr << "Failed to save device.\n";
        return 1;
    }

    std::cout
        << "Updated device '" << device.id
        << "': " << argv[4]
        << " = " << argv[5] << "\n";

    return 0;
}