#include <iostream>

#include "version.h"
#include "core/command.h"

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
            std::cout << "Tower " << TOWER_VERSION << "\n";
            break;

        case Command::Receive:
            std::cout << "Tower receive mode\n";
            break;

        case Command::Send:
            std::cout << "Tower send mode\n";
            break;

        case Command::Learn:
            std::cout << "Tower learn mode\n";
            break;

        case Command::Replay:
            std::cout << "Tower replay mode\n";
            break;

        case Command::Config:
            std::cout << "Tower config mode\n";
            break;

        default:
            std::cerr << "Unknown command\n\n";
            print_usage();
            return 1;
    }

    return 0;
}
