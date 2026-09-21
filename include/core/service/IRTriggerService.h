#pragma once

#include "nlohmann/json.hpp"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

class IRTriggerService
{
public:
    IRTriggerService();
    ~IRTriggerService();

    bool start(std::string& error);
    void stop();

    nlohmann::json list() const;
    bool save(
        const nlohmann::json& triggers,
        nlohmann::json& result,
        std::string& error);
    bool remove(
        const std::string& id,
        std::string& error);
    bool teach(
        const std::string& id,
        const std::string& transmitter,
        std::string& error);
    bool runNow(
        const std::string& id,
        std::string& error);

private:
    bool load(std::string& error);
    bool write(std::string& error) const;
    void receiverLoop();
    void observationLoop();
    void processFrame(
        const std::vector<std::uint32_t>& frame);
    bool executeTrigger(
        const nlohmann::json& trigger,
        std::string& error);

    mutable std::mutex mutex_;
    nlohmann::json document_;
    std::atomic<bool> running_{false};
    std::thread receiverThread_;
    std::thread observationThread_;
    std::string receiverDevice_;
    std::string receiverStatus_ = "Stopped";
    std::map<std::string, std::chrono::steady_clock::time_point> lastTriggered_;
    std::string lastReceivedTriggerId_;
    std::atomic<long long> ignoreUntilMilliseconds_{0};
};
