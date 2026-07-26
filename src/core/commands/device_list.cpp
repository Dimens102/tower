#include <iostream>
#include <string>
#include <vector>

#include "core/commands/device_handlers.h"
#include "devices/device_database.h"

int runDeviceList(int argc, char* argv[])
{
    DeviceDatabase db;

    const std::vector<std::string> devices = db.listDevices();

    if (devices.empty())
    {
        std::cout << "No devices found.\n";
        return 0;
    }

    std::cout << "Devices:\n";

    for (const std::string& deviceId : devices)
    {
        std::cout << "  " << deviceId << "\n";
    }

    return 0;
}