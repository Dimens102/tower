#include "devices/ir/ir_receiver.h"
#include "devices/ir/ir_constants.h"

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
    std::cout << "Waiting for IR transmission...\n";

    while (true)
    {
        GPIOEvent firstEvent;
        GPIOEvent secondEvent;

        if (!gpio.waitForEdge(gpioPin, firstEvent, 5000))
        {
            std::cout << "Timeout waiting for IR signal.\n";
            return false;
        }

        if (firstEvent.edge != GPIOEdge::Falling)
        {
            continue;
        }

        if (!gpio.waitForEdge(
                gpioPin,
                secondEvent,
                IR_START_EDGE_TIMEOUT_MS))
        {
            std::cout << "Ignored isolated noise edge.\n";
            continue;
        }

        if (secondEvent.edge != GPIOEdge::Rising)
        {
            std::cout << "Ignored invalid IR start edge sequence.\n";
            continue;
        }

        code.protocol = "raw";
        code.pulses.clear();

        unsigned int startPulse =
                static_cast<unsigned int>(
                        (secondEvent.timestampNs - firstEvent.timestampNs) / 1000);

        code.pulses.push_back(startPulse);

        std::cout << "Start pulse: " << startPulse << " us\n";

        unsigned long long previousTimestamp = secondEvent.timestampNs;

        while (code.pulses.size() < IR_MAX_PULSES)
        {
            GPIOEvent nextEvent;

            if (!gpio.waitForEdge(
                    gpioPin,
                    nextEvent,
                    IR_EDGE_TIMEOUT_MS))
            {
                break;
            }

            code.pulses.push_back(
                static_cast<unsigned int>(
                    (nextEvent.timestampNs - previousTimestamp) / 1000));

            std::cout << code.pulses.back() << " ";

            previousTimestamp = nextEvent.timestampNs;
        }
		
        std::cout << "\n";
		
        std::cout << "Captured "
                  << code.pulses.size()
                  << " pulse lengths.\n";

        if (code.pulses.size() < IR_MIN_PULSES)
        {
            std::cout << "Rejected short/noisy IR capture.\n";
            continue;
        }

        return true;
    }
}

void IRReceiver::shutdown()
{
    gpioPin = -1;
}
