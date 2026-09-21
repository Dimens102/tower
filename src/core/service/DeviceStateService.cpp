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
#include <atomic>
#include <cctype>
#include <cstdlib>
#include <map>
#include <vector>

using nlohmann::json;
namespace {
std::recursive_mutex execution;
std::recursive_mutex sequences;
thread_local bool suppressTracking = false;
std::atomic<long long> mutedUntil{0};
long long milliseconds(){return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();}
std::map<std::string,long long> lastObserved;
std::map<std::string,long long> pendingOff;
std::map<std::string,std::pair<long long,std::string>> channelDigits;
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
    d["states"][key]["state"]=state;d["states"][key]["source"]=source;d["states"][key]["updated"]=std::time(nullptr);
    writeStore(d);
}
void applyLinkedIr(json& d,const std::string& rfKey,const std::string& rfState,const std::string& source){
    if(rfKey.rfind("rf:",0)!=0)return;
    const auto settings=d.value("settings",json::object()).value(rfKey,json::object());
    const auto link=settings.value("linked_ir",json::object());
    const std::string irKey=link.value("device","");if(irKey.rfind("ir:",0)!=0)return;
    std::string state="unknown";
    if(rfState=="off")state="off";
    else if(rfState=="on")state=link.value("after_on","unknown");
    if(state!="on"&&state!="off")state="unknown";
    d["states"][irKey]["state"]=state;
    d["states"][irKey]["source"]="linked RF power: "+source;
    d["states"][irKey]["updated"]=std::time(nullptr);
}
std::string get(const json& d,const std::string& key) {
    if(!d.at("states").contains(key)) return "unknown";
    auto s=d.at("states").at(key).value("state","unknown");
    return s=="on"||s=="off" ? s : "unknown";
}
void validKey(const std::string& key) {
    if(key.size()<4 || (key.rfind("ir:",0)!=0 && key.rfind("rf:",0)!=0)) throw std::runtime_error("Select an IR or RF device");
}
std::string lowerText(std::string value){
    for(char& c:value)c=static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return value;
}
json inferredFields(const std::string& command){
    const std::string lower=lowerText(command);
    const bool zone2=lower.rfind("z2-",0)==0||lower.rfind("zone 2",0)==0;
    const std::string plain=lower.rfind("z2-",0)==0?lower.substr(3):lower;
    const std::string zone=zone2?"Zone 2 ":"";
    if(plain.size()==1&&plain[0]>='0'&&plain[0]<='9')return {{"property","Channel"},{"value",std::string("digit:")+plain[0]}};
    if(plain=="channel up")return {{"property","Channel"},{"value","+1"}};
    if(plain=="channel down")return {{"property","Channel"},{"value","-1"}};
    if(plain=="volume up")return {{"property",zone+"Volume"},{"value","+1"}};
    if(plain=="volume down")return {{"property",zone+"Volume"},{"value","-1"}};
    if(plain=="mute")return {{"property",zone+"Mute"},{"value","toggle"}};
    const std::vector<std::string> sources={"cbl-sat","mediaplayer","blu-ray","game","aux1","aux2","tv audio","cd","tuner","usb","phono","phone","bluetooth","heos","internetradio"};
    for(const auto& source:sources)if(plain==source){std::string label=command;if(zone2&&label.rfind("Z2-",0)==0)label=label.substr(3);return {{"property",zone+"Source"},{"value",label}};}
    if(plain=="green-movie")return {{"property","Sound mode"},{"value","Movie"}};
    if(plain=="red-music")return {{"property","Sound mode"},{"value","Music"}};
    if(plain=="blue-game")return {{"property","Sound mode"},{"value","Game"}};
    if(plain=="yellow-pure")return {{"property","Sound mode"},{"value","Pure"}};
    return json::object();
}
void applyProperty(json& state,const std::string& key,const std::string& property,const std::string& operation){
    if(property.empty()||operation.empty())return;
    auto& configuration=state["configuration"];
    if(!configuration.is_object())configuration=json::object();
    if(property=="Channel"&&operation.size()==7&&operation.rfind("digit:",0)==0&&operation[6]>='0'&&operation[6]<='9'){
        auto& digits=channelDigits[key];auto now=milliseconds();if(now-digits.first>2000||digits.second.size()>=6)digits.second.clear();digits.first=now;digits.second+=operation[6];
        configuration[property]=std::to_string(std::stoul(digits.second));state["channel"]=configuration[property];return;
    }
    channelDigits.erase(key);
    if(operation=="+1"||operation=="-1"){
        const int delta=operation=="+1"?1:-1;std::string current=configuration.value(property,"");
        if(!current.empty()&&current.size()<=7&&current.find_first_not_of("0123456789")==std::string::npos){long next=std::stol(current)+delta;configuration[property]=next>=0?std::to_string(next):"unknown";}
        else{
            int relative=0;if(current.rfind("relative ",0)==0){try{relative=std::stoi(current.substr(9));}catch(...) {relative=0;}}
            relative+=delta;configuration[property]="relative "+std::string(relative>=0?"+":"")+std::to_string(relative)+" step"+(std::abs(relative)==1?"":"s");
        }
    }else if(operation=="toggle"){
        const std::string current=configuration.value(property,"");configuration[property]=current=="On"?"Off":current=="Off"?"On":"changed (exact state unknown)";
    }else configuration[property]=operation;
    if(property=="Channel")state["channel"]=configuration[property];
    if(property=="Source"||property=="Input")state["source_input"]=configuration[property];
}
void applyFields(json& d,const std::string& key,const std::string& command){
    auto settings=d.value("settings",json::object()).value(key,json::object());
    auto fields=settings.value("command_fields",json::object()).value(command,json::object());
    if(!d["states"].contains(key))d["states"][key]={{"state","unknown"},{"source","not initialized"},{"updated",0}};
    json effect=fields;
    if(effect.empty())effect=inferredFields(command);
    if(effect.contains("source_input"))applyProperty(d["states"][key],key,"Source",effect["source_input"].get<std::string>());
    if(effect.contains("channel"))applyProperty(d["states"][key],key,"Channel",effect["channel"].get<std::string>());
    if(effect.contains("property")&&effect.contains("value"))applyProperty(d["states"][key],key,effect["property"].get<std::string>(),effect["value"].get<std::string>());
    d["states"][key]["last_command"]=command;
}
std::string powerAfter(const json& profile,const std::string& key,const std::string& command,const std::string& effect,const std::string& current){
    auto now=milliseconds();auto off=profile.value("off",json::array());
    if(effect=="unknown"&&off.size()==2&&off[0].value("command","")==command&&off[1].value("command","")==command){
        if(current=="off"){pendingOff.erase(key);return "on";}
        if(current=="on"){
            auto pending=pendingOff.find(key);auto delay=off[1].value("delay_before_seconds",2)*1000LL;
            if(pending!=pendingOff.end()&&now-pending->second>=std::max(650LL,delay-600)&&now-pending->second<=delay+2000){pendingOff.erase(key);return "off";}
            pendingOff[key]=now;
        }
        return current;
    }
    if(effect=="on"||effect=="off")return effect;
    if(effect=="toggle"&&current!="unknown")return current=="on"?"off":"on";
    return effect=="unknown"?"unknown":current;
}
}
void DeviceStateService::suppressReception(int duration){auto until=milliseconds()+duration;auto previous=mutedUntil.load();while(previous<until&&!mutedUntil.compare_exchange_weak(previous,until)){} }
bool DeviceStateService::receptionSuppressed(){return milliseconds()<mutedUntil.load();}
bool DeviceStateService::disabled(const std::string& key){std::lock_guard lock(execution);return readStore().value("settings",json::object()).value(key,json::object()).value("disabled",false);}
json DeviceStateService::inferredCommandFields(const std::string& command){return inferredFields(command);}
void DeviceStateService::configure(const std::string& key,const json& settings){
    std::lock_guard lock(execution);validKey(key);
    if(!settings.is_object())throw std::runtime_error("Invalid device settings");
    if(settings.contains("disabled")&&!settings["disabled"].is_boolean())throw std::runtime_error("Disabled must be true or false");
    if(settings.contains("command_fields")){
        if(!settings["command_fields"].is_object())throw std::runtime_error("Command mappings must be an object");
        for(const auto& entry:settings["command_fields"].items()){
            if(!entry.value().is_object())throw std::runtime_error("Invalid command mapping");
            for(const auto& field:entry.value().items())if((field.key()!="source_input"&&field.key()!="channel"&&field.key()!="property"&&field.key()!="value")||!field.value().is_string()||field.value().get<std::string>().size()>80)throw std::runtime_error("Map a property and value using text up to 80 characters");
        }
    }
    if(settings.contains("linked_ir")){
        if(key.rfind("rf:",0)!=0||!settings["linked_ir"].is_object())throw std::runtime_error("Only an RF device can have a linked IR device");
        const auto& link=settings["linked_ir"];const std::string target=link.value("device","");const std::string after=link.value("after_on","unknown");
        if(!target.empty()&&target.rfind("ir:",0)!=0)throw std::runtime_error("Linked device must be an IR device");
        if(after!="on"&&after!="off"&&after!="unknown")throw std::runtime_error("Linked IR startup state must be on, off, or unknown");
        if(!target.empty()){DeviceDatabase db;Device device;if(!db.loadDevice(target.substr(3),device)||device.type!="IR Device")throw std::runtime_error("Linked IR device was not found");}
    }
    auto d=readStore();if(!d.contains("settings"))d["settings"]=json::object();
    if(settings.contains("linked_ir")&&!settings["linked_ir"].value("device","").empty())for(const auto& item:d["settings"].items()){
        if(item.key()!=key&&item.value().value("linked_ir",json::object()).value("device","")==settings["linked_ir"].value("device",""))throw std::runtime_error("That IR device is already linked to "+item.key());
    }
    auto& s=d["settings"][key];if(s.is_null())s=json::object();
    for(const auto& field:{"disabled","command_fields","linked_ir"})if(settings.contains(field))s[field]=settings[field];
    if(settings.contains("linked_ir"))applyLinkedIr(d,key,get(d,key),"link configuration");
    writeStore(d);
}
void DeviceStateService::observe(const std::string& key,const std::string& command){
    if(receptionSuppressed())return;
    std::unique_lock<std::recursive_mutex> lock(execution,std::try_to_lock);
    if(!lock.owns_lock()||receptionSuppressed()||disabled(key))return;
    auto now=milliseconds();auto identity=key+"\n"+command;auto previous=lastObserved[identity];lastObserved[identity]=now;
    if(previous&&now-previous<650)return; // Held keys and sightings on multiple receivers.
    auto d=readStore();auto profile=d["profiles"].value(key,json::object());
    auto effect=profile.value("effects",json::object()).value(command,"");auto next=powerAfter(profile,key,command,effect,get(d,key));
    applyFields(d,key,command);d["states"][key]["state"]=next;d["states"][key]["source"]="physical IR remote (estimated)";d["states"][key]["updated"]=std::time(nullptr);writeStore(d);
}
std::recursive_mutex& DeviceStateService::executionMutex(){return execution;}
std::recursive_mutex& DeviceStateService::sequenceMutex(){return sequences;}
std::string DeviceStateService::state(const std::string& key){std::lock_guard lock(execution);return get(readStore(),key);}
void DeviceStateService::correct(const std::string& key,const std::string& state){
    std::lock_guard lock(execution);validKey(key);
    if(state!="on"&&state!="off"&&state!="unknown")throw std::runtime_error("State must be on, off, or unknown");
    pendingOff.erase(key);
    auto d=readStore();put(d,key,state,"manual correction");applyLinkedIr(d,key,state,"manual correction");writeStore(d);
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
        if(!value.contains("configuration")||!value["configuration"].is_object())value["configuration"]=json::object();
        const std::string power=get(d,key);value["configuration"]["Power"]=power=="on"?"On":power=="off"?"Off":"Unknown";
        if(value.contains("source_input")&&!value["source_input"].get<std::string>().empty())value["configuration"]["Source"]=value["source_input"];
        if(value.contains("channel")&&!value["channel"].get<std::string>().empty())value["configuration"]["Channel"]=value["channel"];
        value["id"]=key;value["name"]=name;value["profile"]=d["profiles"].value(key,json::object());value["settings"]=d.value("settings",json::object()).value(key,json::object());value["disabled"]=value["settings"].value("disabled",false);rows.push_back(value);
    };
    DeviceDatabase db;
    for(const auto& id:db.listDevices()){Device device;if(db.loadDevice(id,device)&&device.type=="IR Device")append("ir:"+id,device.name);}
    for(const auto& device:RFDatabase().listPowerDevices())append("rf:"+device.name,device.deviceName.empty()?device.name:device.deviceName);
    return {{"devices",rows},{"estimated",true}};
}
bool DeviceStateService::track(const std::string& key,const std::string& command,const std::function<bool()>& send){
    std::lock_guard lock(execution);
    if(disabled(key))return true;
    struct ReceptionGuard{bool ir;ReceptionGuard(bool value):ir(value){if(ir)DeviceStateService::suppressReception(120000);}~ReceptionGuard(){if(ir)mutedUntil.store(milliseconds()+700);}} reception(key.rfind("ir:",0)==0);
    if(suppressTracking)return send();
    auto d=readStore();std::string effect;
    if(key.rfind("rf:",0)==0 && (command=="on"||command=="off"))effect=command;
    else if(d["profiles"].contains(key))effect=d["profiles"][key].value("effects",json::object()).value(command,"");
    if(effect.empty()){
        bool ok=send();if(ok){applyFields(d,key,command);d["states"][key]["source"]="command sent (estimated)";d["states"][key]["updated"]=std::time(nullptr);writeStore(d);}return ok;
    }
    auto previous=get(d,key);
    put(d,key,"unknown","command in progress");
    const bool ok=send();
    std::string next="unknown";
    if(ok)next=powerAfter(d["profiles"].value(key,json::object()),key,command,effect,previous);
    else pendingOff.erase(key);
    put(d,key,next,ok?"command sent (estimated)":"command failed");if(ok){applyFields(d,key,command);applyLinkedIr(d,key,next,"command sent (estimated)");writeStore(d);}return ok;
}
bool DeviceStateService::ensure(const std::string& key,const std::string& desired,const json& transmitters,std::string& error){
    std::lock_guard lock(execution);
    try{
        validKey(key);if(disabled(key)){error.clear();ExecutionDisplay::publish({key,"Disabled","Skipped","No signal sent",true,5});return true;}auto d=readStore();auto current=get(d,key);auto target=desired;
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
        pendingOff.erase(key);put(d,key,target,"power sequence sent (estimated)");error.clear();return true;
    }catch(const std::exception& e){error=e.what();return false;}
}
