#pragma once

#include <chrono>
#include <string>

#include "core/gpio.h"
#include "core/service/Scheduler.h"
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

    void showBootStatus(
        const std::string& status,
        const std::string& detail = "");

    Scheduler scheduler_;
    tower::displays::LCD1602 lcd_;

    TemperatureSensor* aquariumSensor_ = nullptr;
    tower::sensors::BME688* roomSensor_ = nullptr;

    std::chrono::steady_clock::time_point nextDisplayUpdate_{};

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
};