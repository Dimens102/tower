#pragma once

#include <string>

class Logger
{
public:
    enum class Level
    {
        Debug,
        Info,
        Warning,
        Error
    };

    static void debug(
        const std::string& component,
        const std::string& message);

    static void info(
        const std::string& component,
        const std::string& message);

    static void warning(
        const std::string& component,
        const std::string& message);

    static void error(
        const std::string& component,
        const std::string& message);

private:
    static void log(
        Level level,
        const std::string& component,
        const std::string& message);
};