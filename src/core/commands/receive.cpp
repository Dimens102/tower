#include "core/commands/command_handlers.h"

#include <iostream>

#include "core/gpio.h"
#include "devices/controllers/ads1115.h"

int runReceiveCommand()
{
    GPIO gpio;
	
	tower::controllers::ADS1115 ads;

    if (!ads.initialize())
    {
        return 1;
    }

    if (!gpio.openChip("/dev/gpiochip0"))
    {
        return 1;
    }

    if (!gpio.requestInput(4, GPIOEdge::Both))
    {
        return 1;
    }

    std::cout << "Waiting for GPIO4 edges. Press Ctrl+C to stop.\n";

    int count = 0;
	
	unsigned long long previousTimestamp = 0;

    while (true)
    {
		double rssi;

        if (ads.readChannel(0, rssi))
        {
            std::cout << "RSSI: " << rssi << " V\n";
        }

        GPIOEvent event;

        if (gpio.waitForEdge(4, event, 1000))
        {
            ++count;
            if (previousTimestamp != 0)
            {
                std::cout
                    << (event.edge == GPIOEdge::Rising ? "RISING  " : "FALLING ")
                    << (event.timestampNs - previousTimestamp) / 1000
                    << " us\n";
            }

previousTimestamp = event.timestampNs;
        }
    }

    return 0;
}
