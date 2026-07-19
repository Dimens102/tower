
#include <iostream>
#include "commands/command_handlers.h"
#include "core/command.h"
#include "core/gpio.h"
#include "version.h"

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
        << "  tower learn-kernel\n"
        << "  tower replay\n"
        << "  tower config\n"
        << "  tower device\n";
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
            return runSendCommand(argc, argv);

        case Command::Learn:
            return runLearnCommand(argc, argv);
        case Command::Replay:
            return runReplayCommand(argc, argv);

        case Command::LearnKernel:
            return runLearnKernelCommand();

        case Command::Config:
            return runConfigCommand();

        case Command::Device:
            return runDeviceCommand(argc, argv);

        default:
            std::cerr << "Unknown command\n\n";
            print_usage();
            return 1;
    }

    return 0;
}
