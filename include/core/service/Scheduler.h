#pragma once

#include "core/service/AutomationEngine.h"
#include "core/service/Callback.h"
#include "core/service/DeviceManager.h"
#include "core/service/ManagedDevice.h"
#include "core/service/TimerManager.h"

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