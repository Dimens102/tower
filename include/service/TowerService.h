#pragma once

#include "service/Scheduler.h"

class TowerService
{
public:
    bool start();
    void run();
    void stop();

private:
    Scheduler scheduler_;
    void update();

};