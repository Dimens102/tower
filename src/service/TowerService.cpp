#include "service/TowerService.h"

#include "devices/remote/TemperatureSensor.h"
#include "logging/Logger.h"

#include <chrono>
#include <csignal>
#include <memory>
#include <thread>

namespace
{

volatile std::sig_atomic_t keepRunning = 1;

void handleSignal(int)
{
    keepRunning = 0;
}

} // namespace

TowerService::TowerService()
{
    scheduler_.addDevice(
        std::make_unique<TemperatureSensor>(
            "http://192.168.2.26:8765/temperature",
            std::chrono::seconds(30)));
}

bool TowerService::start()
{
    keepRunning = 1;

    std::signal(SIGINT, handleSignal);
    std::signal(SIGTERM, handleSignal);

    Logger::info(
        "TowerService",
        "Tower service starting");

    return true;
}

void TowerService::update()
{
    scheduler_.update();
}

void TowerService::run()
{
    Logger::info(
        "TowerService",
        "Press Ctrl+C to stop");

    while (keepRunning)
    {
        update();

        std::this_thread::sleep_for(
            std::chrono::milliseconds(100));
    }
}

void TowerService::stop()
{
    Logger::info(
        "TowerService",
        "Tower service stopping");
}