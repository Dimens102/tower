#include <iostream>
#include <string>

#include "commands/command_handlers.h"
#include "commands/device_handlers.h"

int runDeviceCommand(int argc, char* argv[])
{
    if (argc < 3)
    {
        std::cout
            << "Device commands:\n"
            << "  tower device list\n"
            << "  tower device show <device-id>\n"
            << "  tower device create <device-id>\n"
            << "  tower device set <device-id> <property> <value>\n"
            << "  tower device alias add <device-id> <alias>\n"
            << "  tower device alias remove <device-id> <alias>\n"
            << "  tower device delete <device-id>\n";

        return 0;
    }

    const std::string subcommand = argv[2];

    if (subcommand == "list")
    {
        return runDeviceList(argc, argv);
    }

    if (subcommand == "show")
    {
        return runDeviceShow(argc, argv);
    }

    if (subcommand == "create")
    {
        return runDeviceCreate(argc, argv);
    }

    if (subcommand == "set")
    {
        return runDeviceSet(argc, argv);
    }

    if (subcommand == "alias")
    {
        return runDeviceAlias(argc, argv);
    }

    if (subcommand == "delete")
    {
        return runDeviceDelete(argc, argv);
    }

    std::cerr
        << "Unknown device command: "
        << subcommand << "\n";

    return 1;
}