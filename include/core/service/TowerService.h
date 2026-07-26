#pragma once

#include "core/service/Scheduler.h"

class TowerService
{
public:
    TowerService();

    bool start();
    void run();
    void stop();

private:
    void update();

    Scheduler scheduler_;
};