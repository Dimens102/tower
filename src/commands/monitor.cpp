#include "commands/command_handlers.h"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <iomanip>
#include <iostream>

#include "core/gpio.h"
#include "sensors/ads1115.h"

int runMonitorCommand()
{
    GPIO gpio;
    tower::sensors::ADS1115 ads;

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

    std::cout
        << "Monitoring RF receiver on GPIO4.\n"
        << "RSSI = ADS1115 AIN0\n"
        << "Press Ctrl+C to stop.\n";

    std::uint64_t edgeCount = 0;

    auto lastReport = std::chrono::steady_clock::now();

    while (true)
    {
        double rssi;

        GPIOEvent event;

        if (gpio.waitForEdge(4, event, 5))
        {
            ++edgeCount;
        }

        const auto now = std::chrono::steady_clock::now();

        if (now - lastReport >= std::chrono::seconds(1))
        {
            std::cout
                << "Edges " << edgeCount << '\n';

            edgeCount = 0;
            lastReport = now;
        }
    }

    return 0;
}