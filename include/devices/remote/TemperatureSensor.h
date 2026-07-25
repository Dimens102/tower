#pragma once

#include "devices/TemperatureReading.h"
#include "devices/remote/RemoteSource.h"
#include "network/HttpClient.h"

#include <chrono>
#include <optional>
#include <string>

class TemperatureSensor : public RemoteSource
{
public:
    using Clock = std::chrono::steady_clock;
    using Duration = std::chrono::milliseconds;

    TemperatureSensor(
        std::string url,
        Duration pollInterval);

    bool initialize() override;
    bool update() override;

    bool available() const override;
    const std::string& name() const override;

    const std::optional<TemperatureReading>&
    latestReading() const;

private:
    bool poll();

    std::string url_;
    Duration pollInterval_;
    Clock::time_point nextPoll_;
    HttpClient httpClient_;
    std::optional<TemperatureReading> latestReading_;

    std::string name_ = "RemoteTemperatureSensor";
};