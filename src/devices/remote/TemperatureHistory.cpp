#include "devices/remote/TemperatureHistory.h"

#include <ctime>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <string>
#include <system_error>
#include <utility>
#include <vector>

TemperatureHistory::TemperatureHistory(
    std::filesystem::path filePath,
    std::size_t maximumReadings)
    : filePath_(std::move(filePath)),
      maximumReadings_(maximumReadings)
{
}

bool TemperatureHistory::store(
    const TemperatureReading& reading)
{
    namespace fs = std::filesystem;

    std::error_code error;

    if (!filePath_.parent_path().empty())
    {
        fs::create_directories(
            filePath_.parent_path(),
            error);

        if (error)
        {
            return false;
        }
    }

    std::vector<std::string> records;

    std::ifstream input(filePath_);
    std::string line;

    if (input)
    {
        std::getline(input, line);

        while (std::getline(input, line))
        {
            if (!line.empty())
            {
                records.push_back(line);
            }
        }
    }

    const std::time_t timestamp =
        std::chrono::system_clock::to_time_t(
            reading.timestamp);

    std::tm utcTime{};

    if (gmtime_r(&timestamp, &utcTime) == nullptr)
    {
        return false;
    }

    std::ostringstream record;

    record
        << std::put_time(
               &utcTime,
               "%Y-%m-%dT%H:%M:%SZ")
        << ","
        << reading.sensorId
        << ","
        << std::fixed
        << std::setprecision(3)
        << reading.temperatureCelsius;

    records.push_back(record.str());

    if (records.size() > maximumReadings_)
    {
        records.erase(
            records.begin(),
            records.begin() +
                (records.size() - maximumReadings_));
    }

    fs::path temporaryPath = filePath_;
    temporaryPath += ".tmp";

    std::ofstream output(
        temporaryPath,
        std::ios::trunc);

    if (!output)
    {
        return false;
    }

    output
        << "timestamp_utc,sensor_id,temperature_celsius\n";

    for (const std::string& recordLine : records)
    {
        output << recordLine << '\n';
    }

    output.close();

    if (!output)
    {
        return false;
    }

    fs::rename(
        temporaryPath,
        filePath_,
        error);

    return !error;
}