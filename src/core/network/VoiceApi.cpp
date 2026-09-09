#include "core/network/VoiceApi.h"

#include "core/service/RFPresetService.h"
#include "devices/device.h"
#include "devices/device_database.h"
#include "devices/rf/rf_database.h"
#include "nlohmann/json.hpp"

#include <algorithm>
#include <cctype>
#include <filesystem>
#include <fstream>
#include <set>
#include <stdexcept>
#include <utility>

namespace
{
using json = nlohmann::json;

const std::filesystem::path voiceConfigPath =
    std::filesystem::path("data") / "voice" / "voice_commands.json";

const std::filesystem::path voiceStatusPath =
    std::filesystem::path("runtime") / "voice" / "status.json";

VoiceApiResponse response(
    int status,
    const std::string& statusText,
    const json& body)
{
    return {status, statusText, body.dump()};
}

VoiceApiResponse errorResponse(
    int status,
    const std::string& statusText,
    const std::string& message)
{
    return response(
        status,
        statusText,
        {{"ok", false}, {"error", message}});
}

json readJsonFile(const std::filesystem::path& path)
{
    std::ifstream input(path);
    if (!input)
    {
        throw std::runtime_error("Could not open " + path.string());
    }

    json document;
    input >> document;
    return document;
}

std::string normalizedPhrase(const std::string& supplied)
{
    const auto first = supplied.find_first_not_of(" \t\r\n");
    if (first == std::string::npos)
    {
        return {};
    }
    const auto last = supplied.find_last_not_of(" \t\r\n");
    std::string phrase = supplied.substr(first, last - first + 1);
    std::transform(
        phrase.begin(),
        phrase.end(),
        phrase.begin(),
        [](unsigned char value)
        {
            return static_cast<char>(std::tolower(value));
        });
    return phrase;
}

void validateActions(const json& actions, const std::string& path)
{
    if (!actions.is_array() || actions.empty())
    {
        throw std::runtime_error(
            "Voice leaf '" + path + "' must contain at least one action");
    }

    for (const json& action : actions)
    {
        if (!action.is_object())
        {
            throw std::runtime_error(
                "Voice leaf '" + path + "' contains an invalid action");
        }

        const std::string type = action.value("type", "command");
        if (action.contains("delay_before_seconds") &&
            (!action.at("delay_before_seconds").is_number_integer() ||
             action.at("delay_before_seconds").get<int>() < 0 ||
             action.at("delay_before_seconds").get<int>() > 300))
        {
            throw std::runtime_error(
                "Action delay at '" + path + "' must be 0-300 seconds");
        }
        if (type == "command")
        {
            if (action.value("device", "").empty() ||
                action.value("command", "").empty())
            {
                throw std::runtime_error(
                    "IR action at '" + path + "' requires a device and command");
            }
        }
        else if (type == "rf_group")
        {
            const std::string operation = action.value("action", "");
            if ((operation != "on" && operation != "off") ||
                !action.contains("devices") ||
                !action.at("devices").is_array() ||
                action.at("devices").empty())
            {
                throw std::runtime_error(
                    "RF device action at '" + path + "' is incomplete");
            }
        }
        else if (type == "rf_preset")
        {
            const int preset = action.value("preset", 0);
            const std::string operation = action.value("action", "");
            if (preset < 1 || preset > 3 ||
                (operation != "on" && operation != "off"))
            {
                throw std::runtime_error(
                    "RF preset action at '" + path + "' is incomplete");
            }
        }
        else
        {
            throw std::runtime_error(
                "Unsupported action type '" + type + "' at '" + path + "'");
        }
    }
}

void validateChildren(const json& children, const std::string& parentPath)
{
    if (!children.is_object())
    {
        throw std::runtime_error(
            "Voice children below '" + parentPath + "' must be an object");
    }

    std::set<std::string> spokenAtLevel;
    for (auto item = children.begin(); item != children.end(); ++item)
    {
        const std::string phrase = normalizedPhrase(item.key());
        if (phrase.empty() || phrase.size() > 80)
        {
            throw std::runtime_error("Voice phrases must contain 1-80 characters");
        }
        if (!item.value().is_object())
        {
            throw std::runtime_error("Voice node '" + phrase + "' must be an object");
        }

        const std::string path =
            parentPath.empty() ? phrase : parentPath + " -> " + phrase;

        if (!spokenAtLevel.insert(phrase).second)
        {
            throw std::runtime_error("Duplicate voice phrase '" + phrase + "'");
        }

        if (item.value().contains("aliases"))
        {
            const json& aliases = item.value().at("aliases");
            if (!aliases.is_array())
            {
                throw std::runtime_error("Aliases at '" + path + "' must be an array");
            }
            for (const json& aliasValue : aliases)
            {
                if (!aliasValue.is_string())
                {
                    throw std::runtime_error("Aliases at '" + path + "' must be text");
                }
                const std::string alias = normalizedPhrase(aliasValue.get<std::string>());
                if (alias.empty() || alias.size() > 80)
                {
                    throw std::runtime_error("Aliases must contain 1-80 characters");
                }
                if (!spokenAtLevel.insert(alias).second)
                {
                    throw std::runtime_error(
                        "Duplicate phrase or alias '" + alias + "' below '" + parentPath + "'");
                }
            }
        }

        const bool hasChildren = item.value().contains("children");
        const bool hasActions = item.value().contains("actions");
        if (hasChildren == hasActions)
        {
            throw std::runtime_error(
                "Voice node '" + path + "' must contain children or actions, not both");
        }
        if (hasChildren)
        {
            if (item.value().at("children").empty())
            {
                throw std::runtime_error("Voice branch '" + path + "' has no children");
            }
            validateChildren(item.value().at("children"), path);
        }
        else
        {
            validateActions(item.value().at("actions"), path);
        }
    }
}

void validateConfig(const json& config)
{
    if (!config.is_object())
    {
        throw std::runtime_error("Voice config must be an object");
    }
    const std::string wakePhrase =
        normalizedPhrase(config.value("wake_phrase", ""));
    if (wakePhrase.empty() || wakePhrase.size() > 80)
    {
        throw std::runtime_error("Wake phrase must contain 1-80 characters");
    }
    if (config.contains("listening_enabled") &&
        !config.at("listening_enabled").is_boolean())
    {
        throw std::runtime_error("Voice listening_enabled must be true or false");
    }
    if (config.contains("minimum_wake_confidence"))
    {
        if (!config.at("minimum_wake_confidence").is_number())
        {
            throw std::runtime_error(
                "Voice minimum_wake_confidence must be a number");
        }
        const double confidence =
            config.at("minimum_wake_confidence").get<double>();
        if (confidence < 0.0 || confidence > 1.0)
        {
            throw std::runtime_error(
                "Voice minimum_wake_confidence must be between 0 and 1");
        }
    }
    if (config.contains("wake_reject_phrases"))
    {
        if (!config.at("wake_reject_phrases").is_array())
        {
            throw std::runtime_error(
                "Voice wake_reject_phrases must be an array");
        }
        for (const json& phrase : config.at("wake_reject_phrases"))
        {
            if (!phrase.is_string() ||
                normalizedPhrase(phrase.get<std::string>()).empty())
            {
                throw std::runtime_error(
                    "Voice wake_reject_phrases must contain non-empty text");
            }
        }
    }
    if (!config.contains("command_tree") ||
        !config.at("command_tree").is_object() ||
        config.at("command_tree").empty())
    {
        throw std::runtime_error("Voice command_tree must contain at least one command");
    }
    validateChildren(config.at("command_tree"), wakePhrase);
}

void writeConfig(const json& config)
{
    std::error_code filesystemError;
    std::filesystem::create_directories(
        voiceConfigPath.parent_path(),
        filesystemError);
    if (filesystemError)
    {
        throw std::runtime_error(
            "Could not create voice config directory: " +
            filesystemError.message());
    }

    const std::filesystem::path temporary =
        voiceConfigPath.string() + ".tmp";
    const std::filesystem::path backup =
        voiceConfigPath.string() + ".bak";

    {
        std::ofstream output(temporary, std::ios::trunc);
        if (!output)
        {
            throw std::runtime_error("Could not write temporary voice config");
        }
        output << config.dump(2) << '\n';
        if (!output)
        {
            throw std::runtime_error("Could not finish writing voice config");
        }
    }

    if (std::filesystem::exists(voiceConfigPath))
    {
        std::filesystem::copy_file(
            voiceConfigPath,
            backup,
            std::filesystem::copy_options::overwrite_existing,
            filesystemError);
        if (filesystemError)
        {
            std::filesystem::remove(temporary);
            throw std::runtime_error(
                "Could not back up voice config: " +
                filesystemError.message());
        }
    }

    std::filesystem::rename(temporary, voiceConfigPath, filesystemError);
    if (filesystemError)
    {
        std::filesystem::remove(voiceConfigPath, filesystemError);
        filesystemError.clear();
        std::filesystem::rename(temporary, voiceConfigPath, filesystemError);
    }
    if (filesystemError)
    {
        std::filesystem::remove(temporary);
        throw std::runtime_error(
            "Could not replace voice config: " +
            filesystemError.message());
    }
}

json voiceCatalog()
{
    json rfDevices = json::array();
    RFDatabase rfDatabase;
    for (const RFDevice& device : rfDatabase.listPowerDevices())
    {
        rfDevices.push_back({
            {"id", device.name},
            {"name", device.deviceName.empty() ? device.name : device.deviceName}
        });
    }

    json irDevices = json::array();
    DeviceDatabase deviceDatabase;
    for (const std::string& deviceId : deviceDatabase.listDevices())
    {
        Device device;
        if (!deviceDatabase.loadDevice(deviceId, device) || !device.enabled)
        {
            continue;
        }

        json commands = json::array();
        for (const DeviceCommand& command : device.commands)
        {
            if (!command.enabled || command.transport != TransportType::IR)
            {
                continue;
            }
            commands.push_back({
                {"id", command.id},
                {"name", command.name.empty() ? command.id : command.name}
            });
        }
        if (!commands.empty())
        {
            irDevices.push_back({
                {"id", device.id},
                {"name", device.name.empty() ? device.id : device.name},
                {"commands", commands}
            });
        }
    }

    RFPresetService presetService;
    RFPresetSnapshot snapshot;
    std::string presetError;
    if (!presetService.load(snapshot, presetError))
    {
        throw std::runtime_error(presetError);
    }

    json presets = json::array();
    for (std::size_t index = 0; index < snapshot.presets.size(); ++index)
    {
        presets.push_back({
            {"id", static_cast<int>(index + 1)},
            {"name", "Preset " + std::to_string(index + 1)},
            {"deviceCount", snapshot.presets[index].size()}
        });
    }

    return {
        {"rfDevices", rfDevices},
        {"irDevices", irDevices},
        {"presets", presets}
    };
}
} // namespace

bool isVoiceApiPath(const std::string& path)
{
    return path.rfind("/api/v1/voice/", 0) == 0;
}

VoiceApiResponse handleVoiceApiRequest(
    const std::string& method,
    const std::string& path,
    const std::string& body,
    const VoiceDisplayNotificationHandler& notificationHandler)
{
    try
    {
        if (path == "/api/v1/voice/config" && method == "GET")
        {
            return response(
                200,
                "OK",
                {{"ok", true}, {"config", readJsonFile(voiceConfigPath)}});
        }

        if (path == "/api/v1/voice/config" && method == "POST")
        {
            const json request = json::parse(body);
            const json config =
                request.contains("config") ? request.at("config") : request;
            validateConfig(config);
            writeConfig(config);
            return response(
                200,
                "OK",
                {
                    {"ok", true},
                    {"message", "Voice configuration saved on Tower; listener will reload automatically"}
                });
        }

        if (path == "/api/v1/voice/listening" && method == "POST")
        {
            const json request = json::parse(body);
            if (!request.contains("enabled") ||
                !request.at("enabled").is_boolean())
            {
                return errorResponse(
                    400,
                    "Bad Request",
                    "Voice listening request requires boolean enabled");
            }

            json config = readJsonFile(voiceConfigPath);
            const bool enabled = request.at("enabled").get<bool>();
            config["listening_enabled"] = enabled;
            validateConfig(config);
            writeConfig(config);
            return response(
                200,
                "OK",
                {
                    {"ok", true},
                    {"enabled", enabled},
                    {"message", enabled
                        ? "Voice listening enabled; microphone discovery is restarting"
                        : "Voice listening disabled; microphone will be released"}
                });
        }

        if (path == "/api/v1/voice/catalog" && method == "GET")
        {
            return response(
                200,
                "OK",
                {{"ok", true}, {"catalog", voiceCatalog()}});
        }

        if (path == "/api/v1/voice/status" && method == "GET")
        {
            if (!std::filesystem::exists(voiceStatusPath))
            {
                return response(
                    200,
                    "OK",
                    {
                        {"ok", true},
                        {"status", {{"state", "unavailable"}, {"message", "Voice listener has not reported yet"}}}
                    });
            }
            return response(
                200,
                "OK",
                {{"ok", true}, {"status", readJsonFile(voiceStatusPath)}});
        }

        if (path == "/api/v1/voice/notification" && method == "POST")
        {
            if (!notificationHandler)
            {
                return errorResponse(
                    503,
                    "Service Unavailable",
                    "Tower display notification handler is unavailable");
            }

            const json request = json::parse(body);
            VoiceDisplayNotification notification;
            notification.path =
                request.at("path").get<std::vector<std::string>>();
            if (request.contains("actions") && request.at("actions").is_array())
            {
                for (const json& action : request.at("actions"))
                {
                    if (!action.is_object())
                    {
                        continue;
                    }
                    VoiceDisplayAction displayAction;
                    displayAction.target = action.value("target", "");
                    displayAction.command = action.value("command", "");
                    if (!displayAction.target.empty() || !displayAction.command.empty())
                    {
                        notification.actions.push_back(std::move(displayAction));
                    }
                }
            }
            notification.ok = request.value("ok", false);
            notification.durationSeconds =
                std::clamp(request.value("durationSeconds", 2), 1, 300);
            if (notification.path.empty())
            {
                return errorResponse(400, "Bad Request", "Notification path cannot be empty");
            }
            notificationHandler(notification);
            return response(
                200,
                "OK",
                {{"ok", true}, {"message", "Voice confirmation displayed"}});
        }

        return errorResponse(404, "Not Found", "Voice endpoint not found");
    }
    catch (const std::exception& exception)
    {
        return errorResponse(400, "Bad Request", exception.what());
    }
}
