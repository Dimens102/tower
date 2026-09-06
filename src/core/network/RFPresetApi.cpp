#include "core/network/RFPresetApi.h"

#include "core/service/RFPresetService.h"
#include "nlohmann/json.hpp"

#include <array>
#include <vector>

namespace
{
RFPresetApiResponse errorResponse(
    int status,
    const std::string& statusText,
    const std::string& error)
{
    return {
        status,
        statusText,
        nlohmann::json{{"ok", false}, {"error", error}}.dump()
    };
}

nlohmann::json presetsJson(const RFPresetSnapshot& snapshot)
{
    nlohmann::json presets = nlohmann::json::object();
    for (std::size_t index = 0; index < snapshot.presets.size(); ++index)
    {
        presets[std::to_string(index + 1)] = snapshot.presets[index];
    }
    return presets;
}
}

RFPresetApiResponse saveRFPresetsFromJson(const std::string& body)
{
    try
    {
        const nlohmann::json json = nlohmann::json::parse(body);
        RFPresetService service;
        RFPresetSnapshot snapshot;
        std::string error;
        bool saved = false;

        if (json.contains("presets"))
        {
            const auto& incoming = json.at("presets");
            std::array<std::vector<std::string>, 3> presets;
            for (std::size_t index = 0; index < presets.size(); ++index)
            {
                presets[index] = incoming.at(
                    std::to_string(index + 1)).get<std::vector<std::string>>();
            }
            saved = service.saveAll(presets, snapshot, error);
        }
        else
        {
            saved = service.saveOne(
                json.at("preset").get<int>(),
                json.at("devices").get<std::vector<std::string>>(),
                snapshot,
                error);
        }

        if (!saved)
        {
            return errorResponse(400, "Bad Request", error);
        }

        return {
            200,
            "OK",
            nlohmann::json{
                {"ok", true},
                {"presets", presetsJson(snapshot)},
                {"message", "RF preset saved on Tower"}
            }.dump()
        };
    }
    catch (const std::exception& exception)
    {
        return errorResponse(400, "Bad Request", exception.what());
    }
}

RFPresetApiResponse executeRFPresetFromJson(const std::string& body)
{
    try
    {
        const nlohmann::json json = nlohmann::json::parse(body);
        const int preset = json.at("preset").get<int>();
        const std::string action = json.at("action").get<std::string>();

        RFPresetService service;
        std::vector<RFPresetExecutionResult> executionResults;
        std::string error;
        const bool allSucceeded = service.execute(
            preset,
            action,
            executionResults,
            error);

        nlohmann::json results = nlohmann::json::array();
        for (const RFPresetExecutionResult& result : executionResults)
        {
            results.push_back({
                {"device", result.device},
                {"ok", result.ok},
                {"error", result.error}
            });
        }

        if (!allSucceeded && results.empty())
        {
            return errorResponse(400, "Bad Request", error);
        }

        const int status = allSucceeded ? 200 : 500;
        return {
            status,
            allSucceeded ? "OK" : "Internal Server Error",
            nlohmann::json{
                {"ok", allSucceeded},
                {"preset", preset},
                {"action", action},
                {"results", results},
                {"message", allSucceeded ?
                    "RF preset action completed" : error}
            }.dump()
        };
    }
    catch (const std::exception& exception)
    {
        return errorResponse(400, "Bad Request", exception.what());
    }
}
