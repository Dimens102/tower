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