#include "service/TimerManager.h"

#include <utility>

void TimerManager::addTimer(
    Duration delay,
    bool repeating,
    Callback callback)
{
    const Timer::TimePoint expiresAt = Timer::Clock::now() + delay;

    timers_.emplace_back(
        expiresAt,
        delay,
        repeating,
        std::move(callback));
}

void TimerManager::update()
{
}