#include "core/gpio.h"

#include <iostream>

bool GPIO::initialize()
{
    std::cout << "GPIO initialized\n";
    return true;
}

void GPIO::shutdown()
{
    std::cout << "GPIO shutdown\n";
}
