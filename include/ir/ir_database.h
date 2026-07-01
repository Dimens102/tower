#pragma once

#include <string>

#include "ir/ir_code.h"

class IRDatabase
{
public:
    bool save(const std::string& deviceName, const std::string& commandName, const IRCode& code);
    bool load(const std::string& deviceName, const std::string& commandName, IRCode& code);
};
