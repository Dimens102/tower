#include "ir/ir_receiver.h"

#include <iostream>

bool IRReceiver::initialize(int gpio)
{
    gpioPin = gpio;

    if (!this->gpio.openChip("/dev/gpiochip0"))
    {
        return false;
    }

    if (!this->gpio.requestInput(gpioPin, GPIOEdge::Both))
    {
        return false;
    }

    std::cout << "IR receiver initialized on GPIO "
              << gpioPin << "\n";

    return true;
}

bool IRReceiver::receive(IRCode& code)
{
    GPIOEvent event;

    std::cout << "Waiting for first IR pulse...\n";

    if (!gpio.waitForEdge(gpioPin, event, 5000))
    {
        std::cout << "Timeout waiting for IR signal.\n";
        return false;
    }

    std::cout << "Received first pulse on GPIO "
              << event.line
              << " timestamp="
              << event.timestampNs
              << "\n";

    code.protocol = "raw";

    return true;
}

void IRReceiver::shutdown()
{
    gpioPin = -1;
}
