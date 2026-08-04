#pragma once

#include <string>

int learnIRCommand(
    const std::string& deviceName,
    const std::string& commandName,
    const std::string& description,
    double seconds,
    bool force);
