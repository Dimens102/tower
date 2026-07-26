#include "core/service/TimerManager.h"

#include <algorithm>
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
    const Timer::TimePoint now = Timer::Clock::now();

    for (Timer& timer : timers_)
    {
        if (!timer.hasExpired(now))
        {
            continue;
        }

        timer.execute();

        if (timer.isRepeating())
        {
            timer.reschedule(now);
        }
    }

    timers_.erase(
        std::remove_if(
            timers_.begin(),
            timers_.end(),
            [now](const Timer& timer)
            {
                return timer.hasExpired(now) &&
                       !timer.isRepeating();
            }),
        timers_.end());
}