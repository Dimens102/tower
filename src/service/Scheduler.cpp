#include "service/Scheduler.h"

#include <utility>

void Scheduler::addTimer(
    Duration delay,
    bool repeating,
    Callback callback)
{
    timerManager_.addTimer(
        delay,
        repeating,
        std::move(callback));
}

void Scheduler::update()
{
    timerManager_.update();
    deviceManager_.update();
    automationEngine_.update();
}