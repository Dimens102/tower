#pragma once

#include "service/Callback.h"

class TimerManager
{
public:
    void update();

private:
    Callback callback_;
};