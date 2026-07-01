#include <iostream>
#include "version.h"

#include "core/command.h"
#include "core/gpio.h"
#include "commands/command_handlers.h"

void print_usage()
{
    std::cout
        << "Tower Home Automation Engine\n"
        << "Version " << TOWER_VERSION << "\n\n"
        << "Usage:\n"
        << "  tower version\n"
        << "  tower receive\n"
        << "  tower send\n"
        << "  tower learn\n"
        << "  tower replay\n"
        << "  tower config\n";
}

int main(int argc, char* argv[])
{
    if (argc == 1)
    {
        print_usage();
        return 0;
    }

    switch (parseCommand(argv[1]))
    {
        case Command::Version:
            return runVersionCommand();

        case Command::Receive:
            return runReceiveCommand();

        case Command::Send:
            return runSendCommand();

        case Command::Learn:
            return runLearnCommand();

        case Command::Replay:
            return runReplayCommand();

        case Command::Config:
            return runConfigCommand();

        default:
            std::cerr << "Unknown command\n\n";
            print_usage();
            return 1;
    }

    return 0;
}
