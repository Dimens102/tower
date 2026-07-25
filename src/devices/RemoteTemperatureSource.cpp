#include "devices/RemoteTemperatureSource.h"

#include "logging/Logger.h"
#include "nlohmann/json.hpp"

#include <chrono>
#include <cstdint>
#include <ctime>
#include <iomanip>
#include <optional>
#include <sstream>
#include <string>
#include <utility>

namespace
{
using json = nlohmann::json;

std::optional<TemperatureReading> parseReading(
    const std::string& response)
{
    try
    {
        const json document = json::parse(response);

        if (!document.contains("sensor_id") ||
            !document.contains("temperature_millidegrees_c") ||
            !document.contains("timestamp_utc"))
        {
            return std::nullopt;
        }

        if (!document["sensor_id"].is_string() ||
            !document["temperature_millidegrees_c"].is_number_integer() ||
            !document["timestamp_utc"].is_string())
        {
            return std::nullopt;
        }

        const std::string sensorId =
            document["sensor_id"].get<std::string>();

        const std::int64_t temperatureMillidegrees =
            document["temperature_millidegrees_c"].get<std::int64_t>();

        const std::string timestamp =
            document["timestamp_utc"].get<std::string>();

        std::tm parsedTime{};

        std::istringstream timestampStream(timestamp);

        timestampStream >> std::get_time(
            &parsedTime,
            "%Y-%m-%dT%H:%M:%S");

        if (timestampStream.fail())
        {
            return std::nullopt;
        }

        const std::time_t timestampSeconds =
            timegm(&parsedTime);

        TemperatureReading reading;

        reading.sensorId = sensorId;

        reading.timestamp =
            std::chrono::system_clock::from_time_t(
                timestampSeconds);

        reading.temperatureCelsius =
            static_cast<double>(
                temperatureMillidegrees) / 1000.0;

        return reading;
    }
    catch (const json::exception&)
    {
        return std::nullopt;
    }
}
}

RemoteTemperatureSource::RemoteTemperatureSource(
    std::string url,
    Duration pollInterval)
    : url_(std::move(url)),
      pollInterval_(pollInterval),
      nextPoll_(Clock::now())
{
}

void RemoteTemperatureSource::update()
{
    const Clock::time_point now = Clock::now();

    if (now < nextPoll_)
    {
        return;
    }

    poll();

    nextPoll_ = now + pollInterval_;
}

void RemoteTemperatureSource::poll()
{
    const std::optional<std::string> response =
        httpClient_.get(url_);

    if (!response)
    {
        Logger::warning(
            "RemoteTemperature",
            "Unable to retrieve temperature from " + url_);

        return;
    }

    const std::optional<TemperatureReading> reading =
        parseReading(*response);

    if (!reading)
    {
        Logger::warning(
            "RemoteTemperature",
            "Received an invalid temperature response");

        return;
    }

    latestReading_ = *reading;

    std::ostringstream message;

    message
        << latestReading_->sensorId
        << " = "
        << std::fixed
        << std::setprecision(2)
        << latestReading_->temperatureCelsius
        << " C";

    Logger::info(
        "RemoteTemperature",
        message.str());
}

const std::optional<TemperatureReading>&
RemoteTemperatureSource::latestReading() const
{
    return latestReading_;
}