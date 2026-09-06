#pragma once

#include <mutex>
#include <string>

#include "nlohmann/json.hpp"

class ScheduleService
{
public:
    bool initialize();
    void update();

    nlohmann::json list() const;
    bool replace(const nlohmann::json& schedules, std::string& error);
    bool remove(const std::string& id, std::string& error);
    bool runNow(const std::string& id, nlohmann::json& result, std::string& error);

private:
    bool load(std::string& error);
    bool save(std::string& error) const;
    bool executeSchedule(nlohmann::json& schedule, std::string& error) const;

    mutable std::mutex mutex_;
    nlohmann::json document_ = {{"version", 1}, {"schedules", nlohmann::json::array()}};
    std::string lastMinute_;
};
