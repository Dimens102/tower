#pragma once

#include <string>

constexpr int learnIrDuplicateDeclined = 3;

int learnIRCommand(
    const std::string& deviceName,
    const std::string& commandName,
    const std::string& description,
    double seconds,
    bool force);
