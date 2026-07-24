#pragma once

#include "service/AutomationEngine.h"
#include "service/DeviceManager.h"
#include "service/TimerManager.h"

class Scheduler
{
public:
    void update();

private:
    TimerManager timerManager_;
    DeviceManager deviceManager_;
    AutomationEngine automationEngine_;
};