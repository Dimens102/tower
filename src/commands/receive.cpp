#include "commands/command_handlers.h"

#include <iostream>

#include "core/gpio.h"

int runReceiveCommand()
{
    GPIO gpio;

    if (!gpio.openChip("/dev/gpiochip0"))
    {
        return 1;
    }

    if (!gpio.requestInput(23, GPIOEdge::Both))
    {
        return 1;
    }

    std::cout << "Waiting for GPIO23 edges. Press Ctrl+C to stop.\n";

    int count = 0;

    while (true)
    {
        GPIOEvent event;

        if (gpio.waitForEdge(23, event, 1000))
        {
            ++count;
            std::cout << "Edge " << count
                      << " line=" << event.line
                      << " edge=" << (event.edge == GPIOEdge::Rising ? "rising" : "falling")
                      << " timestamp_ns=" << event.timestampNs
                      << "\n";
        }
    }

    return 0;
}
