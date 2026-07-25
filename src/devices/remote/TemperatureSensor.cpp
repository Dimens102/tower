#include "devices/remote/TemperatureSensor.h"

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
            document["temperature_millidegrees_c"]
                .get<std::int64_t>();

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

} // namespace

TemperatureSensor::TemperatureSensor(
    std::string url,
    Duration pollInterval)
    : url_(std::move(url)),
      pollInterval_(pollInterval),
      nextPoll_(Clock::now())
{
}

bool TemperatureSensor::initialize()
{
    nextPoll_ = Clock::now();

    return true;
}

bool TemperatureSensor::update()
{
    const Clock::time_point now = Clock::now();

    if (now < nextPoll_)
    {
        return true;
    }

    const bool success = poll();

    nextPoll_ = now + pollInterval_;

    return success;
}

bool TemperatureSensor::available() const
{
    return latestReading_.has_value();
}

const std::string& TemperatureSensor::name() const
{
    return name_;
}

const std::optional<TemperatureReading>&
TemperatureSensor::latestReading() const
{
    return latestReading_;
}

bool TemperatureSensor::poll()
{
    const std::optional<std::string> response =
        httpClient_.get(url_);

    if (!response)
    {
        Logger::warning(
            name_,
            "Unable to retrieve temperature from " + url_);

        return false;
    }

    const std::optional<TemperatureReading> reading =
        parseReading(*response);

    if (!reading)
    {
        Logger::warning(
            name_,
            "Received an invalid temperature response");

        return false;
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
        name_,
        message.str());

    return true;
}