#pragma once

#include "service/TimerManager.h"

class Scheduler
{
public:
    void update();

private:
    TimerManager timerManager_;
};