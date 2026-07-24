#pragma once

#include "service/Callback.h"
#include "service/Timer.h"

#include <chrono>
#include <vector>

class TimerManager
{
public:
    using Duration = std::chrono::milliseconds;

    void addTimer(
        Duration delay,
        bool repeating,
        Callback callback);

    void update();

private:
    std::vector<Timer> timers_;
};