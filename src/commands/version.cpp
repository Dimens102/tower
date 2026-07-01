#include "commands/command_handlers.h"

#include <iostream>
#include "version.h"

int runVersionCommand()
{
    std::cout << "Tower " << TOWER_VERSION << "\n";
    return 0;
}
