#pragma once

#include <atomic>
#include <cstdint>
#include <functional>
#include <string>
#include <thread>
#include <vector>

#include "core/network/VoiceApi.h"

struct TowerApiSensorMeasurement
{
    std::string name;
    std::string unit;
    double value = 0.0;
};

struct TowerApiSensorSnapshot
{
    std::string id;
    std::string name;
    bool available = false;
    std::string timestampUtc;
    long long ageSeconds = -1;
    std::vector<TowerApiSensorMeasurement> measurements;
};

class TowerApiServer
{
public:
    TowerApiServer();
    ~TowerApiServer();

    bool start(std::uint16_t port, const std::string& token);
    void stop();

    void setSensorProvider(
        std::function<std::vector<TowerApiSensorSnapshot>()> provider);

    void setVoiceDisplayNotificationHandler(
        VoiceDisplayNotificationHandler handler);

private:
    void run();
    void handleClient(int clientFd);

    std::atomic<bool> running_{false};
    int listenFd_ = -1;
    std::string token_;
    std::thread thread_;
    std::function<std::vector<TowerApiSensorSnapshot>()> sensorProvider_;
    VoiceDisplayNotificationHandler voiceDisplayNotificationHandler_;
};
