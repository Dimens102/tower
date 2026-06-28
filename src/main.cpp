#include <iostream>
#include <string>
#include "version.h"

void print_usage() {
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

int main(int argc, char* argv[]) {
    if (argc == 1) {
        print_usage();
        return 0;
    }

    std::string command = argv[1];

    if (command == "version") {
        std::cout << "Tower " << TOWER_VERSION << "\n";
        return 0;
    }

    if (command == "receive") {
        std::cout << "Tower receive mode\n";
        return 0;
    }

    if (command == "send") {
        std::cout << "Tower send mode\n";
        return 0;
    }

    if (command == "learn") {
        std::cout << "Tower learn mode\n";
        return 0;
    }

    if (command == "replay") {
        std::cout << "Tower replay mode\n";
        return 0;
    }

    if (command == "config") {
        std::cout << "Tower config mode\n";
        return 0;
    }

    std::cerr << "Unknown command: " << command << "\n\n";
    print_usage();
    return 1;
}
