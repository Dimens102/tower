#include "commands/command_handlers.h"

#include <chrono>
#include <csignal>
#include <iostream>
#include <thread>

namespace
{

volatile std::sig_atomic_t keepRunning = 1;

void handleSignal(int)
{
    keepRunning = 0;
}

} // namespace

int runServiceCommand()
{
    std::signal(SIGINT, handleSignal);
    std::signal(SIGTERM, handleSignal);

    std::cout << "Tower service starting.\n";
    std::cout << "Press Ctrl+C to stop.\n";

    while (keepRunning)
    {
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }

    std::cout << "Tower service stopping.\n";
    return 0;
}