#pragma once
#include "nlohmann/json.hpp"
#include <functional>
#include <mutex>
#include <string>

// Serializes a physical operation with its persisted estimated state.
class DeviceStateService {
public:
    static std::recursive_mutex& executionMutex();
    static std::recursive_mutex& sequenceMutex();
    static nlohmann::json snapshot();
    static std::string state(const std::string& key);
    static void correct(const std::string& key, const std::string& state);
    static void saveProfile(const std::string& key, const nlohmann::json& profile);
    static bool disabled(const std::string& key);
    static nlohmann::json inferredCommandFields(const std::string& command);
    static void configure(const std::string& key, const nlohmann::json& settings);
    static void observe(const std::string& key, const std::string& command);
    static void suppressReception(int milliseconds);
    static bool receptionSuppressed();
    static bool ensure(const std::string& key, const std::string& desired,
                       const nlohmann::json& transmitters, std::string& error);
    static bool track(const std::string& key, const std::string& command,
                      const std::function<bool()>& send);
};
