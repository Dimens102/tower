#include "commands/command_handlers.h"
#include "sensors/bme688.h"

#include "network/HttpClient.h"
#include "nlohmann/json.hpp"

#include <cstdint>
#include <ctime>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

namespace
{

using json = nlohmann::json;

constexpr const char* temperatureUrl =
    "http://192.168.2.26:8765/temperature";

constexpr const char* historyFilePath =
    "runtime/temperature/temperature_history.csv";

struct DisplayReading
{
    std::time_t timestamp;
    std::string sensorId;
    double temperatureCelsius;
};

std::optional<std::time_t> parseUtcTimestamp(
    const std::string& timestamp)
{
    std::tm parsedTime{};
    std::istringstream stream(timestamp);

    stream >> std::get_time(
        &parsedTime,
        "%Y-%m-%dT%H:%M:%S");

    if (stream.fail())
    {
        return std::nullopt;
    }

    return timegm(&parsedTime);
}

std::string formatLocalTime(
    const std::time_t timestamp)
{
    std::tm localTime{};

    if (localtime_r(&timestamp, &localTime) == nullptr)
    {
        return "Unknown";
    }

    std::ostringstream output;

    output << std::put_time(
        &localTime,
        "%Y-%m-%d %H:%M:%S");

    return output.str();
}

std::string weekIdentifier(
    const std::time_t timestamp)
{
    std::tm localTime{};

    if (localtime_r(&timestamp, &localTime) == nullptr)
    {
        return {};
    }

    char identifier[16]{};

    std::strftime(
        identifier,
        sizeof(identifier),
        "%G-%V",
        &localTime);

    return identifier;
}

std::string weekHeading(
    const std::time_t timestamp)
{
    std::tm localTime{};

    if (localtime_r(&timestamp, &localTime) == nullptr)
    {
        return "UNKNOWN WEEK";
    }

    char weekNumber[8]{};

    std::strftime(
        weekNumber,
        sizeof(weekNumber),
        "%V",
        &localTime);

    const int daysSinceMonday =
        (localTime.tm_wday + 6) % 7;

    std::tm monday = localTime;
    monday.tm_mday -= daysSinceMonday;
    monday.tm_hour = 12;
    monday.tm_min = 0;
    monday.tm_sec = 0;

    const std::time_t mondayTimestamp =
        std::mktime(&monday);

    std::tm normalizedMonday{};

    if (localtime_r(
            &mondayTimestamp,
            &normalizedMonday) == nullptr)
    {
        return "WEEK " + std::string(weekNumber);
    }

    std::tm sunday = normalizedMonday;
    sunday.tm_mday += 6;

    const std::time_t sundayTimestamp =
        std::mktime(&sunday);

    std::tm normalizedSunday{};

    if (localtime_r(
            &sundayTimestamp,
            &normalizedSunday) == nullptr)
    {
        return "WEEK " + std::string(weekNumber);
    }

    char mondayText[16]{};
    char sundayText[20]{};

    std::strftime(
        mondayText,
        sizeof(mondayText),
        "%d %b",
        &normalizedMonday);

    std::strftime(
        sundayText,
        sizeof(sundayText),
        "%d %b %Y",
        &normalizedSunday);

    std::ostringstream heading;

    heading
        << "WEEK "
        << weekNumber
        << " - "
        << mondayText
        << " to "
        << sundayText;

    return heading.str();
}

std::optional<DisplayReading> retrieveCurrentReading()
{
    const HttpClient httpClient;

    const std::optional<std::string> response =
        httpClient.get(temperatureUrl);

    if (!response)
    {
        return std::nullopt;
    }

    try
    {
        const json document = json::parse(*response);

        if (!document.contains("sensor_id") ||
            !document.contains(
                "temperature_millidegrees_c") ||
            !document.contains("timestamp_utc"))
        {
            return std::nullopt;
        }

        if (!document["sensor_id"].is_string() ||
            !document["temperature_millidegrees_c"]
                 .is_number_integer() ||
            !document["timestamp_utc"].is_string())
        {
            return std::nullopt;
        }

        const std::optional<std::time_t> timestamp =
            parseUtcTimestamp(
                document["timestamp_utc"]
                    .get<std::string>());

        if (!timestamp)
        {
            return std::nullopt;
        }

        DisplayReading reading;

        reading.timestamp = *timestamp;
        reading.sensorId =
            document["sensor_id"].get<std::string>();

        reading.temperatureCelsius =
            static_cast<double>(
                document["temperature_millidegrees_c"]
                    .get<std::int64_t>()) /
            1000.0;

        return reading;
    }
    catch (const json::exception&)
    {
        return std::nullopt;
    }
}

std::vector<DisplayReading> loadHistory()
{
    std::vector<DisplayReading> readings;
    std::ifstream input(historyFilePath);

    if (!input)
    {
        return readings;
    }

    std::string line;

    std::getline(input, line);

    while (std::getline(input, line))
    {
        if (line.empty())
        {
            continue;
        }

        const std::size_t firstComma =
            line.find(',');

        const std::size_t secondComma =
            line.find(
                ',',
                firstComma == std::string::npos
                    ? firstComma
                    : firstComma + 1);

        if (firstComma == std::string::npos ||
            secondComma == std::string::npos)
        {
            continue;
        }

        const std::string timestampText =
            line.substr(0, firstComma);

        const std::string sensorId =
            line.substr(
                firstComma + 1,
                secondComma - firstComma - 1);

        const std::string temperatureText =
            line.substr(secondComma + 1);

        const std::optional<std::time_t> timestamp =
            parseUtcTimestamp(timestampText);

        if (!timestamp)
        {
            continue;
        }

        try
        {
            DisplayReading reading;

            reading.timestamp = *timestamp;
            reading.sensorId = sensorId;
            reading.temperatureCelsius =
                std::stod(temperatureText);

            readings.push_back(reading);
        }
        catch (const std::exception&)
        {
            continue;
        }
    }

    return readings;
}

void printWeekStart(
    const DisplayReading& reading)
{
    std::cout
        << "\n"
        << weekHeading(reading.timestamp)
        << "\n"
        << "+---------------------+-------------+\n"
        << "| Time                | Temperature |\n"
        << "+---------------------+-------------+\n";
}

void printWeekEnd()
{
    std::cout
        << "+---------------------+-------------+\n";
}

int runLocalTemperatureCommand()
{
    tower::sensors::BME688 sensor;

    if (!sensor.initialize())
    {
        std::cerr
            << "Unable to initialize the local BME688 sensor.\n";

        return 1;
    }

    if (!sensor.update())
    {
        std::cerr
            << "Unable to retrieve a local BME688 reading.\n";

        return 1;
    }

    const auto& reading = sensor.reading();

    if (!reading.valid)
    {
        std::cerr
            << "The local BME688 returned no valid reading.\n";

        return 1;
    }

    for (const auto& measurement : reading.measurements)
    {
        if (measurement.name == "Temperature")
        {
            std::cout
                << "LOCAL TEMPERATURE\n"
                << "=================\n"
                << std::fixed
                << std::setprecision(2)
                << "Current temperature : "
                << measurement.value
                << " "
                << measurement.unit
                << "\n"
                << "Sensor              : "
                << sensor.name()
                << "\n";

            return 0;
        }
    }

    std::cerr
        << "The BME688 reading did not contain temperature data.\n";

    return 1;
}

void printTemperatureUsage()
{
    std::cout
        << "Usage:\n"
        << "  tower temperature local\n"
        << "  tower temperature remote <ID or name>\n"
        << "\n"
        << "Configured remote sensors:\n"
        << "  ID1  aquarium\n";
}

} // namespace

int runTemperatureCommand(int argc, char* argv[])
{
    if (argc == 3 &&
        std::string(argv[2]) == "local")
    {
        return runLocalTemperatureCommand();
    }

    if (argc != 4 ||
        std::string(argv[2]) != "remote")
    {
        printTemperatureUsage();
        return 1;
    }

    const std::string remoteIdentifier = argv[3];

    if (remoteIdentifier != "ID1" &&
        remoteIdentifier != "aquarium")
    {
        std::cerr
            << "Unknown remote temperature sensor: "
            << remoteIdentifier
            << "\n\n";

        printTemperatureUsage();
        return 1;
    }

    std::cout
        << "REMOTE TEMPERATURE: AQUARIUM\n"
        << "============================\n"
        << "Source ID           : ID1\n";

    const std::optional<DisplayReading> currentReading =
        retrieveCurrentReading();

    if (currentReading)
    {
        std::cout
            << std::fixed
            << std::setprecision(2)
            << "Current temperature : "
            << currentReading->temperatureCelsius
            << " C\n"
            << "Remote timestamp    : "
            << formatLocalTime(
                currentReading->timestamp)
            << "\n"
            << "Sensor ID           : "
            << currentReading->sensorId
            << "\n";
    }
    else
    {
        std::cout
            << "Current temperature : Unavailable\n";
    }

    const std::vector<DisplayReading> history =
        loadHistory();

    std::cout
        << "\nTEMPERATURE HISTORY\n"
        << "===================\n";

    if (history.empty())
    {
        std::cout
            << "No stored temperature readings.\n";

        return currentReading ? 0 : 1;
    }

    std::string currentWeek;

    for (const DisplayReading& reading : history)
    {
        const std::string readingWeek =
            weekIdentifier(reading.timestamp);

        if (readingWeek != currentWeek)
        {
            if (!currentWeek.empty())
            {
                printWeekEnd();
            }

            printWeekStart(reading);
            currentWeek = readingWeek;
        }

        std::cout
            << "| "
            << std::left
            << std::setw(19)
            << formatLocalTime(reading.timestamp)
            << " | "
            << std::right
            << std::fixed
            << std::setprecision(2)
            << std::setw(7)
            << reading.temperatureCelsius
            << " C |"
            << "\n";
    }

    printWeekEnd();

    return currentReading ? 0 : 1;
}