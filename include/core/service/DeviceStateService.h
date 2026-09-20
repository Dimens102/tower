#pragma once
#include "nlohmann/json.hpp"
#include <functional>
#include <mutex>
#include <string>

// Serializes a physical operation with its persisted estimated state.
class DeviceStateService {
public:
    static std::recursive_mutex& executionMutex();
    static nlohmann::json snapshot();
    static std::string state(const std::string& key);
    static void correct(const std::string& key, const std::string& state);
    static void saveProfile(const std::string& key, const nlohmann::json& profile);
    static bool ensure(const std::string& key, const std::string& desired,
                       const nlohmann::json& transmitters, std::string& error);
    static bool track(const std::string& key, const std::string& command,
                      const std::function<bool()>& send);
};
