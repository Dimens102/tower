#include "core/service/RFPresetService.h"

#include "core/service/RFCommandService.h"
#include "nlohmann/json.hpp"

#include <filesystem>
#include <fstream>
#include <set>
#include <stdexcept>

namespace
{
const std::filesystem::path& presetsPath()
{
    static const std::filesystem::path path =
        std::filesystem::path("data") / "rf" / "presets.json";
    return path;
}

std::vector<std::string> normalize(const std::vector<std::string>& supplied)
{
    std::vector<std::string> devices;
    std::set<std::string> seen;
    for (const std::string& device : supplied)
    {
        if (device.empty())
        {
            throw std::runtime_error("Preset device IDs cannot be empty");
        }
        if (seen.insert(device).second)
        {
            devices.push_back(device);
        }
    }
    return devices;
}

void validatePreset(int preset)
{
    if (preset < 1 || preset > 3)
    {
        throw std::runtime_error("Preset must be 1, 2, or 3");
    }
}

void writeSnapshot(const RFPresetSnapshot& snapshot)
{
    const std::filesystem::path& path = presetsPath();
    const std::filesystem::path temporary = path.string() + ".tmp";
    std::error_code filesystemError;
    std::filesystem::create_directories(path.parent_path(), filesystemError);
    if (filesystemError)
    {
        throw std::runtime_error(
            "Could not create RF preset directory: " +
            filesystemError.message());
    }

    nlohmann::json presets = nlohmann::json::object();
    for (std::size_t index = 0; index < snapshot.presets.size(); ++index)
    {
        presets[std::to_string(index + 1)] = snapshot.presets[index];
    }

    {
        std::ofstream output(temporary, std::ios::trunc);
        if (!output)
        {
            throw std::runtime_error("Could not write RF preset file");
        }
        output << nlohmann::json{
            {"version", 1},
            {"presets", presets}
        }.dump(2) << '\n';
        if (!output)
        {
            throw std::runtime_error("Could not finish writing RF preset file");
        }
    }

    std::filesystem::rename(temporary, path, filesystemError);
    if (filesystemError)
    {
        std::filesystem::remove(path, filesystemError);
        filesystemError.clear();
        std::filesystem::rename(temporary, path, filesystemError);
    }
    if (filesystemError)
    {
        const std::string message = filesystemError.message();
        std::error_code cleanupError;
        std::filesystem::remove(temporary, cleanupError);
        throw std::runtime_error("Could not replace RF preset file: " + message);
    }
}
}

bool RFPresetService::load(
    RFPresetSnapshot& snapshot,
    std::string& error) const
{
    snapshot = RFPresetSnapshot{};
    error.clear();
    try
    {
        std::ifstream input(presetsPath());
        if (!input)
        {
            return true;
        }

        const nlohmann::json stored = nlohmann::json::parse(input);
        const nlohmann::json& source =
            stored.contains("presets") ? stored.at("presets") : stored;
        if (!source.is_object())
        {
            throw std::runtime_error(
                "RF preset file must contain a presets object");
        }

        for (std::size_t index = 0; index < snapshot.presets.size(); ++index)
        {
            const std::string key = std::to_string(index + 1);
            if (!source.contains(key) || !source.at(key).is_array())
            {
                continue;
            }
            snapshot.presets[index] = normalize(
                source.at(key).get<std::vector<std::string>>());
        }
        snapshot.configured = true;
        return true;
    }
    catch (const std::exception& exception)
    {
        error = exception.what();
        return false;
    }
}

bool RFPresetService::saveOne(
    int preset,
    const std::vector<std::string>& devices,
    RFPresetSnapshot& snapshot,
    std::string& error) const
{
    try
    {
        validatePreset(preset);
        if (!load(snapshot, error))
        {
            return false;
        }
        snapshot.presets[static_cast<std::size_t>(preset - 1)] =
            normalize(devices);
        snapshot.configured = true;
        writeSnapshot(snapshot);
        return true;
    }
    catch (const std::exception& exception)
    {
        error = exception.what();
        return false;
    }
}

bool RFPresetService::saveAll(
    const std::array<std::vector<std::string>, 3>& supplied,
    RFPresetSnapshot& snapshot,
    std::string& error) const
{
    try
    {
        snapshot = RFPresetSnapshot{};
        for (std::size_t index = 0; index < supplied.size(); ++index)
        {
            snapshot.presets[index] = normalize(supplied[index]);
        }
        snapshot.configured = true;
        writeSnapshot(snapshot);
        error.clear();
        return true;
    }
    catch (const std::exception& exception)
    {
        error = exception.what();
        return false;
    }
}

bool RFPresetService::execute(
    int preset,
    const std::string& action,
    std::vector<RFPresetExecutionResult>& results,
    std::string& error) const
{
    results.clear();
    try
    {
        validatePreset(preset);
        if (action != "on" && action != "off")
        {
            throw std::runtime_error("Action must be on or off");
        }

        RFPresetSnapshot snapshot;
        if (!load(snapshot, error))
        {
            return false;
        }
        if (!snapshot.configured)
        {
            throw std::runtime_error(
                "RF presets have not been configured on Tower yet");
        }

        const auto& devices =
            snapshot.presets[static_cast<std::size_t>(preset - 1)];
        if (devices.empty())
        {
            throw std::runtime_error("RF preset has no devices selected");
        }

        RFCommandService rfService;
        bool allSucceeded = true;
        for (const std::string& device : devices)
        {
            RFPresetExecutionResult result;
            result.device = device;
            result.ok = rfService.send(device, action, result.error);
            allSucceeded = allSucceeded && result.ok;
            results.push_back(result);
        }
        if (!allSucceeded)
        {
            error = "One or more RF preset commands failed";
        }
        return allSucceeded;
    }
    catch (const std::exception& exception)
    {
        error = exception.what();
        return false;
    }
}
