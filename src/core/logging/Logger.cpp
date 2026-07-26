#include "core/logging/Logger.h"

#include <chrono>
#include <ctime>
#include <iomanip>
#include <iostream>
#include <mutex>

namespace
{
std::mutex logMutex;

const char* levelName(Logger::Level level)
{
    switch (level)
    {
        case Logger::Level::Debug:
            return "DEBUG";

        case Logger::Level::Info:
            return "INFO";

        case Logger::Level::Warning:
            return "WARN";

        case Logger::Level::Error:
            return "ERROR";
    }

    return "UNKNOWN";
}
}

void Logger::debug(
    const std::string& component,
    const std::string& message)
{
    log(Level::Debug, component, message);
}

void Logger::info(
    const std::string& component,
    const std::string& message)
{
    log(Level::Info, component, message);
}

void Logger::warning(
    const std::string& component,
    const std::string& message)
{
    log(Level::Warning, component, message);
}

void Logger::error(
    const std::string& component,
    const std::string& message)
{
    log(Level::Error, component, message);
}

void Logger::log(
    Level level,
    const std::string& component,
    const std::string& message)
{
    const auto now =
        std::chrono::system_clock::now();

    const std::time_t nowTime =
        std::chrono::system_clock::to_time_t(now);

    std::tm localTime{};

    localtime_r(&nowTime, &localTime);

    std::lock_guard<std::mutex> lock(logMutex);

    std::cout
        << std::put_time(
            &localTime,
            "%Y-%m-%d %H:%M:%S")
        << ' '
        << std::left
        << std::setw(5)
        << levelName(level)
        << " ["
        << component
        << "] "
        << message
        << '\n';
}