#include "service/Scheduler.h"

void Scheduler::update()
{
    timerManager_.update();
    deviceManager_.update();
    automationEngine_.update();
}