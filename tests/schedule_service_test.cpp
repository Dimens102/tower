#include "core/service/ScheduleService.h"
#include "core/service/ActionExecutionService.h"
#include "core/logging/Logger.h"

#include <cassert>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <unistd.h>

using nlohmann::json;
namespace {int executions=0;}

bool ActionExecutionService::executeAll(const json&,std::string& error) const {++executions;error.clear();return true;}
void Logger::debug(const std::string&,const std::string&){}
void Logger::info(const std::string&,const std::string&){}
void Logger::warning(const std::string&,const std::string&){}
void Logger::error(const std::string&,const std::string&){}

int main(){
    char temporary[]="/tmp/tower-schedule-test-XXXXXX";auto* root=::mkdtemp(temporary);assert(root);assert(::chdir(root)==0);
    std::filesystem::create_directories("data/schedules");
    auto point=std::chrono::system_clock::now();auto raw=std::chrono::system_clock::to_time_t(point);std::tm local{};localtime_r(&raw,&local);
    std::ostringstream minute;minute<<std::setfill('0')<<std::setw(2)<<local.tm_hour<<":"<<std::setw(2)<<local.tm_min;
    json document={{"version",1},{"schedules",json::array({{{"id","daily-test"},{"name","Daily test"},{"enabled",true},{"trigger",{{"type","daily"},{"time",minute.str()}}},{"actions",json::array()}}})}};
    {std::ofstream out("data/schedules/schedules.json");out<<document.dump(2)<<'\n';}
    ScheduleService schedules;assert(schedules.initialize());schedules.update();assert(executions==1);
    auto saved=schedules.list()["schedules"][0];assert(saved["lastResult"]=="success");assert(!saved.value("lastRun","").empty());
    schedules.update();assert(executions==1);
    std::filesystem::remove_all(root);
}
