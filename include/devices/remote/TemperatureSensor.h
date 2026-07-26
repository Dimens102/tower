#pragma once

#include "devices/TemperatureReading.h"
#include "devices/remote/TemperatureHistory.h"
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
    using Hours = std::chrono::hours;

    TemperatureSensor(
        std::string sourceId,
        std::string displayName,
        std::string url,
        Duration pollInterval);

    bool initialize() override;
    bool update() override;

    bool available() const override;
    const std::string& name() const override;

    const std::optional<TemperatureReading>&
    latestReading() const;

    const std::string& sourceId() const;
    const std::string& displayName() const;

private:
    bool poll();

    std::string sourceId_;
    std::string displayName_;
    std::string url_;
    Duration pollInterval_;
    Clock::time_point nextPoll_;
    HttpClient httpClient_;
    std::optional<TemperatureReading> latestReading_;

    TemperatureHistory history_;
    Clock::time_point nextHistoryStore_;

    std::string name_ = "RemoteTemperatureSensor";
};