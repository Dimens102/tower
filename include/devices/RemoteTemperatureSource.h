#pragma once

#include "devices/TemperatureReading.h"
#include "network/HttpClient.h"
#include "service/ManagedDevice.h"

#include <chrono>
#include <optional>
#include <string>

class RemoteTemperatureSource : public ManagedDevice
{
public:
    using Clock = std::chrono::steady_clock;
    using Duration = std::chrono::milliseconds;

    RemoteTemperatureSource(
        std::string url,
        Duration pollInterval);

    void update() override;

    const std::optional<TemperatureReading>& latestReading() const;

private:
    void poll();

    std::string url_;
    Duration pollInterval_;
    Clock::time_point nextPoll_;
    HttpClient httpClient_;
    std::optional<TemperatureReading> latestReading_;
};