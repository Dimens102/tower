#include "commands/command_handlers.h"

#include <iostream>

#include "core/gpio.h"

int runConfigCommand()
{
    GPIO gpio;

    if (!gpio.openChip("/dev/gpiochip0"))
    {
        return 1;
    }

    if (!gpio.requestOutput(24, false))
    {
        return 1;
    }

    std::cout << "GPIO24 ON\n";
    gpio.write(24, true);

    std::cout << "GPIO24 OFF\n";
    gpio.write(24, false);

    return 0;
}
