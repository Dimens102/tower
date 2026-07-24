#include "service/Timer.h"

#include <utility>

Timer::Timer(
    TimePoint expiresAt,
    Duration interval,
    bool repeating,
    Callback callback)
    : expiresAt_(expiresAt),
      interval_(interval),
      repeating_(repeating),
      callback_(std::move(callback))
{
}

bool Timer::hasExpired(TimePoint now) const
{
    return now >= expiresAt_;
}

bool Timer::isRepeating() const
{
    return repeating_;
}

void Timer::execute()
{
    if (callback_)
    {
        callback_();
    }
}

void Timer::reschedule(TimePoint now)
{
    expiresAt_ = now + interval_;
}