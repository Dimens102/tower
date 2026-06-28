#include "core/gpio.h"

#include <iostream>

GPIO::GPIO()
    : chip(nullptr)
{
}

GPIO::~GPIO()
{
    closeChip();
}

bool GPIO::openChip(const std::string& chipName)
{
    std::cout << "Opening GPIO chip: " << chipName << "\n";
    chip = nullptr;
    return true;
}

void GPIO::closeChip()
{
    chip = nullptr;
}

bool GPIO::requestInput(int line, GPIOEdge edge)
{
    std::cout << "Request GPIO input line " << line << "\n";
    return true;
}

bool GPIO::requestOutput(int line, bool initialValue)
{
    std::cout << "Request GPIO output line " << line
              << " initial=" << initialValue << "\n";
    return true;
}

bool GPIO::read(int line) const
{
    std::cout << "Read GPIO line " << line << "\n";
    return false;
}

bool GPIO::write(int line, bool value)
{
    std::cout << "Write GPIO line " << line
              << " value=" << value << "\n";
    return true;
}
