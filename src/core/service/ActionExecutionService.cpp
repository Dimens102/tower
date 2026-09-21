#include "core/service/ActionExecutionService.h"

#include "core/service/CommandExecutor.h"
#include "core/service/DeviceStateService.h"
#include "core/service/ScriptService.h"
#include "core/service/ExecutionDisplay.h"
#include "core/service/RFCommandService.h"
#include "core/service/RFPresetService.h"

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <thread>
#include <vector>

namespace
{
const std::filesystem::path voicePath =
    std::filesystem::path("data") / "voice" / "voice_commands.json";
}

bool ActionExecutionService::execute(
    const nlohmann::json& action,
    std::string& error) const
{
    try
    {
        const int delay =
            std::max(0, action.value("delay_before_seconds", 0));
        if (delay > 0)
        {
            std::this_thread::sleep_for(std::chrono::seconds(delay));
        }

        const std::string type = action.value("type", "command");
        if (type == "device_power") {
            if (!DeviceStateService::ensure(action.at("device").get<std::string>(), action.at("state").get<std::string>(), action.value("transmitters", nlohmann::json::array()), error)) return false;
        }
        else if(type == "script") {
            std::string detail;
            const bool ok=ScriptService::run(action.at("script").get<std::string>(), detail);
            ExecutionDisplay::publish({"Saved script",action.at("script").get<std::string>(),ok?(detail.rfind("Queued",0)==0?"Queued":"Completed"):"Failed",detail,ok,5});
            if(!ok){error=detail;return false;}
        }
        else if (type == "command")
        {
            const CommandExecutionResult result =
                CommandExecutor().execute(
                    action.at("device").get<std::string>(),
                    action.at("command").get<std::string>(),
                    action.value(
                        "transmitters",
                        std::vector<std::string>{}));
            if (!result.succeeded())
            {
                throw std::runtime_error(result.message);
            }
        }
        else if (type == "rf_preset")
        {
            std::vector<RFPresetExecutionResult> results;
            std::string detail;
            if (!RFPresetService().execute(
                    action.at("preset").get<int>(),
                    action.at("action").get<std::string>(),
                    results,
                    detail))
            {
                throw std::runtime_error(detail);
            }
        }
        else if (type == "rf_group")
        {
            RFCommandService rf;
            for (const auto& device : action.at("devices"))
            {
                std::string detail;
                if (!rf.send(
                        device.get<std::string>(),
                        action.at("action").get<std::string>(),
                        detail))
                {
                    throw std::runtime_error(detail);
                }
            }
        }
        else if (type == "voice_path")
        {
            std::ifstream input(voicePath);
            if (!input)
            {
                throw std::runtime_error(
                    "Cannot open Voice configuration");
            }

            nlohmann::json config;
            input >> config;
            const auto& phrases = action.at("path");
            if (!phrases.is_array() || phrases.empty())
            {
                throw std::runtime_error(
                    "Voice command path is empty");
            }

            const nlohmann::json* children =
                &config.at("command_tree");
            const nlohmann::json* node = nullptr;
            std::string displayPath;
            for (std::size_t index = 0; index < phrases.size(); ++index)
            {
                const std::string phrase =
                    phrases.at(index).get<std::string>();
                if (!displayPath.empty())
                {
                    displayPath += " > ";
                }
                displayPath += phrase;
                const auto found = children->find(phrase);
                if (found == children->end())
                {
                    throw std::runtime_error(
                        "Voice command no longer exists: " + phrase);
                }

                node = &(*found);
                if (index + 1 < phrases.size())
                {
                    if (!node->contains("children"))
                    {
                        throw std::runtime_error(
                            "Voice command path ends early: " + phrase);
                    }
                    children = &node->at("children");
                }
            }

            if (node == nullptr || !node->contains("actions") ||
                !node->at("actions").is_array())
            {
                throw std::runtime_error(
                    "Voice command path does not end in an action set");
            }

            ExecutionDisplay::publish({
                displayPath,
                "Voice sequence",
                "starting",
                "Running actions...",
                true,
                5,
            });

            const bool completed = executeAll(node->at("actions"), error);
            ExecutionDisplay::publish({
                displayPath,
                "Voice sequence",
                completed ? "completed" : "failed",
                completed ? "OK - sequence done" : "FAILED - check log",
                completed,
                5,
            });
            if (!completed)
            {
                return false;
            }
        }
        else
        {
            throw std::runtime_error(
                "Unsupported action type: " + type);
        }

        error.clear();
        return true;
    }
    catch (const std::exception& exception)
    {
        error = exception.what();
        return false;
    }
}

bool ActionExecutionService::executeAll(
    const nlohmann::json& actions,
    std::string& error) const
{
    if (!actions.is_array())
    {
        error = "Actions must be an array";
        return false;
    }

    // Serialize action lists while allowing receiver observations between actions.
    // Individual sends and multi-press power operations hold the state mutex.
    std::lock_guard<std::recursive_mutex> lock(DeviceStateService::sequenceMutex());
    static thread_local int depth=0;
    if(depth>=8){error="Too many nested action sets";return false;}
    struct DepthGuard{int& n;DepthGuard(int& n):n(n){++n;}~DepthGuard(){--n;}} guard(depth);
    for (const auto& action : actions)
    {
        const int repeats = std::max(1, action.value("repeat", 1));
        if (repeats > 100) { error = "Action repeat limit is 100"; return false; }
        for (int repetition = 0; repetition < repeats; ++repetition) {
            auto next = action;
            if (repetition > 0) next["delay_before_seconds"] = 0;
            if (!execute(next, error)) return false;
            const int delayMs = std::clamp(action.value("delay_ms", 0), 0, 300000);
            if (delayMs && (repetition + 1 < repeats || &action != &actions.back()))
                std::this_thread::sleep_for(std::chrono::milliseconds(delayMs));
        }
    }

    error.clear();
    return true;
}
