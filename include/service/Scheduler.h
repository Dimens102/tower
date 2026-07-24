#pragma once

#include "service/DeviceManager.h"
#include "service/TimerManager.h"

class Scheduler
{
public:
    void update();

private:
    TimerManager timerManager_;
    DeviceManager deviceManager_;
};