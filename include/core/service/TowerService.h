#pragma once

#include <chrono>
#include <deque>
#include <mutex>
#include <string>
#include <vector>

#include "core/gpio.h"
#include "core/network/TowerApiServer.h"
#include "core/service/Scheduler.h"
#include "core/service/ExecutionDisplay.h"
#include "core/service/IRTriggerService.h"
#include "devices/displays/LCD1602.h"
#include "devices/remote/TemperatureSensor.h"
#include "devices/sensors/bme688.h"

class TowerService
{
public:
    TowerService();

    bool start();
    void run();
    void stop();

private:
    void update();
    void updateDisplay();
    void updateBacklightButton();

    void showVoiceNotification(
        const VoiceDisplayNotification& notification);

    void queueExecutionDisplay(
        const ExecutionDisplayNotification& notification);

    void showBootStatus(
        const std::string& status,
        const std::string& detail = "");

    std::vector<TowerApiSensorSnapshot> sensorSnapshots();

    Scheduler scheduler_;
    IRTriggerService irTriggerService_;
    tower::displays::LCD1602 lcd_;

    TemperatureSensor* aquariumSensor_ = nullptr;
    tower::sensors::BME688* roomSensor_ = nullptr;
    std::mutex sensorMutex_;

    std::chrono::steady_clock::time_point nextDisplayUpdate_{};

    std::mutex executionDisplayMutex_;
    std::deque<ExecutionDisplayNotification> executionDisplayQueue_;
    ExecutionDisplayNotification executionDisplayCurrent_;
    bool executionDisplayActive_ = false;
    bool executionDisplayPainted_ = false;
    std::chrono::steady_clock::time_point executionDisplayEndsAt_{};

    bool bootScreenActive_ = false;
    std::chrono::steady_clock::time_point bootScreenEndsAt_{};

    GPIO gpio_;
    bool buttonAvailable_ = false;
    bool backlightOn_ = false;

    bool permanentBacklight_ = false;
    bool waitingForSecondPress_ = false;
    bool doublePressTurnsOn_ = true;

    unsigned long long firstButtonPressTimestampNs_ = 0;
    bool buttonPressArmed_ = true;
    bool buttonReleased_ = true;

    std::chrono::steady_clock::time_point lastButtonEdgeAt_{};
    std::chrono::steady_clock::time_point backlightOffAt_{};
	
    int serviceLockFd_ = -1;
    TowerApiServer apiServer_;
};
