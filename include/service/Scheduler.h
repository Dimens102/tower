#pragma once

#include "service/AutomationEngine.h"
#include "service/Callback.h"
#include "service/DeviceManager.h"
#include "service/TimerManager.h"

#include <chrono>

class Scheduler
{
public:
    using Duration = std::chrono::milliseconds;

    void addTimer(
        Duration delay,
        bool repeating,
        Callback callback);

    void update();

private:
    TimerManager timerManager_;
    DeviceManager deviceManager_;
    AutomationEngine automationEngine_;
};