#include <iostream>
#include <string>

#include "core/commands/command_handlers.h"
#include "core/commands/device_handlers.h"

int runLogicalCommand(int argc, char* argv[])
{
    if (argc < 3)
    {
        std::cout
            << "Command commands:\n"
            << "  tower command list <device-id>\n"
            << "  tower command show <device-id> <command-id>\n"
            << "  tower command create <device-id> <command-id>\n"
            << "  tower command set <device-id> <command-id> <property> <value>\n"
            << "  tower command delete <device-id> <command-id>\n";

        return 0;
    }

    const std::string subcommand = argv[2];

    if (subcommand == "list")
    {
        return runCommandList(argc, argv);
    }

    if (subcommand == "create")
    {
        return runCommandCreate(argc, argv);
    }

    if (subcommand == "show")
    {
        return runCommandShow(argc, argv);
    }

    if (subcommand == "set")
    {
        return runCommandSet(argc, argv);
    }

    if (subcommand == "delete")
    {
        return runCommandDelete(argc, argv);
    }

    std::cerr
        << "Unknown command command: "
        << subcommand
        << "\n";

    return 1;
}
