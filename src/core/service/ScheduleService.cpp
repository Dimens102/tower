#include "core/service/ScheduleService.h"

#include "core/service/CommandExecutor.h"
#include "core/service/RFPresetService.h"
#include "core/service/RFCommandService.h"

#include <chrono>
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iomanip>
#include <sstream>
#include <stdexcept>
#include <thread>

namespace {
const std::filesystem::path path = std::filesystem::path("data") / "schedules" / "schedules.json";
const std::filesystem::path voicePath = std::filesystem::path("data") / "voice" / "voice_commands.json";

std::string nowMinute() {
    const auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
    std::tm local{};
    localtime_r(&now, &local);
    std::ostringstream out;
    out << std::put_time(&local, "%Y-%m-%d %H:%M");
    return out.str();
}

std::string today() {
    const auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
    std::tm local{};
    localtime_r(&now, &local);
    std::ostringstream out;
    out << std::put_time(&local, "%Y-%m-%d");
    return out.str();
}

bool matches(const nlohmann::json& schedule) {
    if (!schedule.value("enabled", true) || !schedule.contains("trigger")) return false;
    const auto& trigger = schedule.at("trigger");
    const std::string type = trigger.value("type", "daily");
    const auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
    std::tm local{};
    localtime_r(&now, &local);
    std::ostringstream clock;
    clock << std::setfill('0') << std::setw(2) << local.tm_hour << ":"
          << std::setfill('0') << std::setw(2) << local.tm_min;
    if (clock.str() != trigger.value("time", "")) return false;
    if (type == "once") return trigger.value("date", "") == today();
    if (type == "weekly") {
        for (const auto& day : trigger.value("days", nlohmann::json::array()))
            if (day.is_number_integer() && day.get<int>() == local.tm_wday) return true;
        return false;
    }
    return type == "daily";
}
}

bool ScheduleService::initialize() { std::lock_guard lock(mutex_); std::string error; return load(error); }

bool ScheduleService::load(std::string& error) {
    error.clear();
    if (!std::filesystem::exists(path)) return true;
    try { std::ifstream input(path); input >> document_; if (!document_.contains("schedules") || !document_["schedules"].is_array()) throw std::runtime_error("schedules must be an array"); return true; }
    catch (const std::exception& e) { error = e.what(); return false; }
}

bool ScheduleService::save(std::string& error) const {
    try {
        std::filesystem::create_directories(path.parent_path());
        const auto temporary = path.string() + ".tmp";
        std::ofstream output(temporary); if (!output) throw std::runtime_error("cannot write schedule file");
        output << document_.dump(2) << '\n'; output.close();
        std::error_code ec; std::filesystem::rename(temporary, path, ec);
        if (ec) { std::filesystem::remove(path, ec); ec.clear(); std::filesystem::rename(temporary, path, ec); }
        if (ec) throw std::runtime_error(ec.message());
        return true;
    } catch (const std::exception& e) { error = e.what(); return false; }
}

nlohmann::json ScheduleService::list() const { std::lock_guard lock(mutex_); return document_; }

bool ScheduleService::replace(const nlohmann::json& schedules, std::string& error) {
    std::lock_guard lock(mutex_);
    if (!schedules.is_array()) { error = "schedules must be an array"; return false; }
    document_ = {{"version", 1}, {"schedules", schedules}};
    return save(error);
}

bool ScheduleService::remove(const std::string& id, std::string& error) {
    std::lock_guard lock(mutex_); auto& items = document_["schedules"];
    const auto before = items.size();
    items.erase(std::remove_if(items.begin(), items.end(), [&](const auto& item){ return item.value("id", "") == id; }), items.end());
    if (items.size() == before) { error = "Schedule not found: " + id; return false; }
    return save(error);
}

bool ScheduleService::executeSchedule(nlohmann::json& schedule, std::string& error) const {
    try {
        std::function<void(const nlohmann::json&)> executeAction;
        executeAction = [&](const nlohmann::json& action) {
            const int delay = action.value("delay_before_seconds", 0);
            if (delay > 0) std::this_thread::sleep_for(std::chrono::seconds(delay));
            const std::string type = action.value("type", "command");
            if (type == "command") {
                auto result = CommandExecutor().execute(action.at("device").get<std::string>(), action.at("command").get<std::string>(), action.value("transmitters", std::vector<std::string>{}));
                if (!result.succeeded()) throw std::runtime_error(result.message);
            } else if (type == "rf_preset") {
                std::vector<RFPresetExecutionResult> results; std::string detail;
                if (!RFPresetService().execute(action.at("preset").get<int>(), action.at("action").get<std::string>(), results, detail)) throw std::runtime_error(detail);
            } else if (type == "rf_group") {
                RFCommandService rf;
                for (const auto& device : action.at("devices")) { std::string detail; if (!rf.send(device.get<std::string>(), action.at("action").get<std::string>(), detail)) throw std::runtime_error(detail); }
            } else if (type == "voice_path") {
                std::ifstream input(voicePath);
                if (!input) throw std::runtime_error("Cannot open Voice configuration");
                nlohmann::json config; input >> config;
                const auto& phrases = action.at("path");
                if (!phrases.is_array() || phrases.empty()) throw std::runtime_error("Voice command path is empty");
                const nlohmann::json* children = &config.at("command_tree");
                const nlohmann::json* node = nullptr;
                for (std::size_t phraseIndex = 0; phraseIndex < phrases.size(); ++phraseIndex) {
                    const auto& phraseValue = phrases.at(phraseIndex);
                    const std::string phrase = phraseValue.get<std::string>();
                    const auto found = children->find(phrase);
                    if (found == children->end()) throw std::runtime_error("Voice command no longer exists: " + phrase);
                    node = &(*found);
                    if (phraseIndex + 1 < phrases.size()) {
                        if (!node->contains("children")) throw std::runtime_error("Voice command path ends early: " + phrase);
                        children = &node->at("children");
                    }
                }
                if (!node || !node->contains("actions") || !node->at("actions").is_array())
                    throw std::runtime_error("Voice command path does not end in an action set");
                for (const auto& nestedAction : node->at("actions")) executeAction(nestedAction);
            } else throw std::runtime_error("Unsupported schedule action type: " + type);
        };
        for (const auto& action : schedule.at("actions")) {
            executeAction(action);
        }
        return true;
    } catch (const std::exception& e) { error = e.what(); return false; }
}

bool ScheduleService::runNow(const std::string& id, nlohmann::json& result, std::string& error) {
    std::lock_guard lock(mutex_);
    for (auto& schedule : document_["schedules"]) if (schedule.value("id", "") == id) {
        const bool ok = executeSchedule(schedule, error); schedule["lastRun"] = nowMinute(); schedule["lastResult"] = ok ? "success" : error; save(error);
        result = {{"ok", ok}, {"schedule", schedule}}; return ok;
    }
    error = "Schedule not found: " + id; return false;
}

void ScheduleService::update() {
    const std::string minute = nowMinute(); if (minute == lastMinute_) return; lastMinute_ = minute;
    std::lock_guard lock(mutex_); bool changed = false; std::string error;
    for (auto& schedule : document_["schedules"]) if (matches(schedule)) { const bool ok = executeSchedule(schedule, error); schedule["lastRun"] = minute; schedule["lastResult"] = ok ? "success" : error; if (schedule.at("trigger").value("type", "daily") == "once") schedule["enabled"] = false; changed = true; }
    if (changed) save(error);
}
