#include "service/TowerService.h"

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
}

bool TowerService::start()
{
    keepRunning = 1;

    std::signal(SIGINT, handleSignal);
    std::signal(SIGTERM, handleSignal);

    std::cout << "Tower service starting.\n";

    return true;
}

void TowerService::update()
{
}

void TowerService::run()
{
    std::cout << "Press Ctrl+C to stop.\n";

    while (keepRunning)
{
    update();

    std::this_thread::sleep_for(std::chrono::milliseconds(100));
}
}

void TowerService::stop()
{
    std::cout << "Tower service stopping.\n";
}