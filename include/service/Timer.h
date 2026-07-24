#pragma once

#include "service/Callback.h"

#include <chrono>

class Timer
{
public:
    using Clock = std::chrono::steady_clock;
    using TimePoint = Clock::time_point;
    using Duration = std::chrono::milliseconds;

    Timer(
        TimePoint expiresAt,
        Duration interval,
        bool repeating,
        Callback callback);

private:
    TimePoint expiresAt_;
    Duration interval_;
    bool repeating_;
    Callback callback_;
};