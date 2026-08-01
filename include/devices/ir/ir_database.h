#pragma once

#include <string>
#include <filesystem>

#include "devices/ir/ir_code.h"

class IRDatabase
{
public:
    bool save(const std::string& deviceName, const std::string& commandName, const IRCode& code);
    bool load(const std::string& deviceName, const std::string& commandName, IRCode& code);
    bool exists(const std::string& deviceName, const std::string& commandName) const;
    std::filesystem::path path(
        const std::string& deviceName,
        const std::string& commandName) const;
};
