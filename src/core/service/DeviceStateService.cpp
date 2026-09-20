#include "core/service/DeviceStateService.h"
#include "core/service/CommandExecutor.h"
#include "core/service/RFCommandService.h"
#include "core/service/ExecutionDisplay.h"
#include "devices/device_database.h"
#include "devices/rf/rf_database.h"
#include <filesystem>
#include <fstream>
#include <chrono>
#include <ctime>
#include <thread>
#include <stdexcept>
#include <fcntl.h>
#include <unistd.h>

using nlohmann::json;
namespace {
std::recursive_mutex execution;
thread_local bool suppressTracking = false;
const std::filesystem::path path = "data/control/device_states.json";
json readStore() {
    if (!std::filesystem::exists(path)) return {{"version",1},{"profiles",json::object()},{"states",json::object()}};
    std::ifstream in(path); json d; in >> d;
    if (!d.at("profiles").is_object() || !d.at("states").is_object()) throw std::runtime_error("Invalid device-state file; restore its backup before sending power commands");
    return d;
}
void writeStore(const json& d) {
    std::filesystem::create_directories(path.parent_path());
    auto temporary = path.string()+".tmp";
    const auto bytes = d.dump(2)+"\n";
    int fd = ::open(temporary.c_str(), O_WRONLY|O_CREAT|O_TRUNC, 0600);
    if (fd < 0) throw std::runtime_error("Cannot save device state");
    std::size_t sent=0;
    while (sent<bytes.size()) {
        auto n=::write(fd,bytes.data()+sent,bytes.size()-sent);
        if(n<=0){::close(fd);throw std::runtime_error("Device-state write failed");} sent+=n;
    }
    int synced=::fsync(fd); ::close(fd);
    if(synced<0) throw std::runtime_error("Device-state sync failed");
    std::filesystem::rename(temporary,path);
    fd=::open(path.parent_path().c_str(),O_RDONLY|O_DIRECTORY);
    if(fd>=0){::fsync(fd);::close(fd);}
}
void put(json& d,const std::string& key,const std::string& state,const std::string& source) {
    d["states"][key]={{"state",state},{"source",source},{"updated",std::time(nullptr)}};
    writeStore(d);
}
std::string get(const json& d,const std::string& key) {
    if(!d.at("states").contains(key)) return "unknown";
    auto s=d.at("states").at(key).value("state","unknown");
    return s=="on"||s=="off" ? s : "unknown";
}
void validKey(const std::string& key) {
    if(key.size()<4 || (key.rfind("ir:",0)!=0 && key.rfind("rf:",0)!=0)) throw std::runtime_error("Select an IR or RF device");
}
}
std::recursive_mutex& DeviceStateService::executionMutex(){return execution;}
std::string DeviceStateService::state(const std::string& key){std::lock_guard lock(execution);return get(readStore(),key);}
void DeviceStateService::correct(const std::string& key,const std::string& state){
    std::lock_guard lock(execution);validKey(key);
    if(state!="on"&&state!="off"&&state!="unknown")throw std::runtime_error("State must be on, off, or unknown");
    auto d=readStore();put(d,key,state,"manual correction");
}
void DeviceStateService::saveProfile(const std::string& key,const json& profile){
    std::lock_guard lock(execution); validKey(key);
    if(key.rfind("ir:",0)!=0)throw std::runtime_error("RF devices already have separate ON/OFF signals");
    for(const auto* operation:{"on","off"}) {
        const auto& steps=profile.at(operation);
        if(!steps.is_array()||steps.empty()||steps.size()>10)throw std::runtime_error("Power sequence must contain 1-10 commands");
        for(const auto& step:steps) {
            int delay=step.value("delay_before_seconds",0);
            if(step.value("command","").empty()||delay<0||delay>30)throw std::runtime_error("Invalid power command or delay (0-30 seconds)");
        }
    }
    if(!profile.at("effects").is_object())throw std::runtime_error("Power effects must be an object");
    if(profile.value("discrete",false)) {
        for(const auto& on:profile.at("on")) for(const auto& off:profile.at("off"))
            if(on.at("command")==off.at("command"))throw std::runtime_error("Separate ON/OFF signals cannot share a command");
    }
    for(const auto& effect:profile.at("effects"))if(effect!="on"&&effect!="off"&&effect!="toggle"&&effect!="unknown")throw std::runtime_error("Invalid power effect");
    // Editing future power behavior does not change the device's current state.
    // Preserve the last observation, including its source and timestamp.
    auto d=readStore();d["profiles"][key]=profile;writeStore(d);
}
json DeviceStateService::snapshot(){
    std::lock_guard lock(execution);auto d=readStore();json rows=json::array();
    auto append=[&](const std::string& key,const std::string& name){
        auto value=d["states"].value(key,json{{"state","unknown"},{"source","not initialized"},{"updated",0}});
        value["id"]=key;value["name"]=name;value["profile"]=d["profiles"].value(key,json::object());rows.push_back(value);
    };
    DeviceDatabase db;
    for(const auto& id:db.listDevices()){Device device;if(db.loadDevice(id,device)&&device.type=="IR Device")append("ir:"+id,device.name);}
    for(const auto& device:RFDatabase().listPowerDevices())append("rf:"+device.name,device.deviceName.empty()?device.name:device.deviceName);
    return {{"devices",rows},{"estimated",true}};
}
bool DeviceStateService::track(const std::string& key,const std::string& command,const std::function<bool()>& send){
    std::lock_guard lock(execution);
    if(suppressTracking)return send();
    auto d=readStore();std::string effect;
    if(key.rfind("rf:",0)==0 && (command=="on"||command=="off"))effect=command;
    else if(d["profiles"].contains(key))effect=d["profiles"][key].value("effects",json::object()).value(command,"");
    if(effect.empty())return send();
    auto previous=get(d,key);
    put(d,key,"unknown","command in progress");
    const bool ok=send();
    std::string next="unknown";
    if(ok){if(effect=="on"||effect=="off")next=effect;else if(effect=="toggle"&&previous!="unknown")next=previous=="on"?"off":"on";}
    put(d,key,next,ok?"command sent (estimated)":"command failed");return ok;
}
bool DeviceStateService::ensure(const std::string& key,const std::string& desired,const json& transmitters,std::string& error){
    std::lock_guard lock(execution);
    try{
        validKey(key);auto d=readStore();auto current=get(d,key);auto target=desired;
        if(target=="toggle"){
            if(current=="unknown")throw std::runtime_error("Current state unknown: set "+key+" state in Devices first");
            target=current=="on"?"off":"on";
        }
        if(target!="on"&&target!="off")throw std::runtime_error("Choose on, off, or toggle");
        if(current==target){ExecutionDisplay::publish({key,"Already "+target,"Skipped","No signal sent",true,5});error.clear();return true;}
        if(key.rfind("rf:",0)==0)return RFCommandService().send(key.substr(3),target,error);
        if(!d["profiles"].contains(key))throw std::runtime_error("Configure power controls for "+key+" in Devices first");
        const auto profile=d["profiles"][key];
        if(current=="unknown"&&!profile.value("discrete",false))throw std::runtime_error("Current state unknown: set "+key+" state in Devices before using toggle power");
        const auto outputs=transmitters.empty()?profile.value("transmitters",json::array()):transmitters;
        put(d,key,"unknown","power sequence in progress");
        struct Guard{bool old=suppressTracking;Guard(){suppressTracking=true;}~Guard(){suppressTracking=old;}} guard;
        for(const auto& step:profile.at(target)){
            std::this_thread::sleep_for(std::chrono::seconds(step.value("delay_before_seconds",0)));
            auto r=CommandExecutor().execute(key.substr(3),step.at("command").get<std::string>(),outputs.get<std::vector<std::string>>());
            if(!r.succeeded())throw std::runtime_error(r.message);
        }
        put(d,key,target,"power sequence sent (estimated)");error.clear();return true;
    }catch(const std::exception& e){error=e.what();return false;}
}
