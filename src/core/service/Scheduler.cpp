#include "core/service/Scheduler.h"

#include <utility>

bool Scheduler::initialize()
{
    std::string error;
    const bool schedulesReady = scheduleService_.initialize();
    return deviceManager_.initialize() && schedulesReady;
}

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

void Scheduler::addDevice(
    std::unique_ptr<ManagedDevice> device)
{
    deviceManager_.addDevice(
        std::move(device));
}

void Scheduler::update()
{
    timerManager_.update();
    deviceManager_.update();
    automationEngine_.update();
    scheduleService_.update();
}

ScheduleService& Scheduler::schedules() { return scheduleService_; }
const ScheduleService& Scheduler::schedules() const { return scheduleService_; }
