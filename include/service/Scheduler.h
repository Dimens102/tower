#pragma once

#include "service/AutomationEngine.h"
#include "service/Callback.h"
#include "service/DeviceManager.h"
#include "service/ManagedDevice.h"
#include "service/TimerManager.h"

#include <chrono>
#include <memory>

class Scheduler
{
public:
    using Duration = std::chrono::milliseconds;

    void after(
        Duration delay,
        Callback callback);

    void every(
        Duration interval,
        Callback callback);

    void addDevice(
        std::unique_ptr<ManagedDevice> device);

    void update();

private:
    TimerManager timerManager_;
    DeviceManager deviceManager_;
    AutomationEngine automationEngine_;
};