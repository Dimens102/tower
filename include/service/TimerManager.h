#pragma once

#include "service/Timer.h"

#include <vector>

class TimerManager
{
public:
    void update();

private:
    std::vector<Timer> timers_;
};