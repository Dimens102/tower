#include "service/Scheduler.h"

#include <utility>

void Scheduler::after(
    Duration delay,
    Callback callback)
{
    timerManager_.addTimer(
        delay,
        false,
        std::move(callback));
}

void Scheduler::every(
    Duration interval,
    Callback callback)
{
    timerManager_.addTimer(
        interval,
        true,
        std::move(callback));
}

void Scheduler::update()
{
    timerManager_.update();
    deviceManager_.update();
    automationEngine_.update();
}