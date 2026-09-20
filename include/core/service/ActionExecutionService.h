#pragma once

#include "nlohmann/json.hpp"

#include <string>

class ActionExecutionService
{
public:
    bool execute(
        const nlohmann::json& action,
        std::string& error) const;

    bool executeAll(
        const nlohmann::json& actions,
        std::string& error) const;
};
