#pragma once

#include <array>
#include <string>
#include <vector>

struct RFPresetSnapshot
{
    bool configured = false;
    std::array<std::vector<std::string>, 3> presets;
};

struct RFPresetExecutionResult
{
    std::string device;
    bool ok = false;
    std::string error;
};

class RFPresetService
{
public:
    bool load(RFPresetSnapshot& snapshot, std::string& error) const;

    bool saveOne(
        int preset,
        const std::vector<std::string>& devices,
        RFPresetSnapshot& snapshot,
        std::string& error) const;

    bool saveAll(
        const std::array<std::vector<std::string>, 3>& presets,
        RFPresetSnapshot& snapshot,
        std::string& error) const;

    bool execute(
        int preset,
        const std::string& action,
        std::vector<RFPresetExecutionResult>& results,
        std::string& error) const;
};
