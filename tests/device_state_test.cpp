#include "core/service/DeviceStateService.h"
#include "core/service/CommandExecutor.h"
#include "core/service/RFCommandService.h"
#include "core/service/ExecutionDisplay.h"
#include "core/service/ActionExecutionService.h"
#include "core/service/RFPresetService.h"
#include "devices/device_database.h"
#include "devices/rf/rf_database.h"
#include <cassert>
#include <filesystem>
#include <fstream>
#include <thread>
#include <iostream>
using nlohmann::json;
int sends=0,failAt=0;
CommandExecutionResult CommandExecutor::execute(const std::string&,const std::string&,const std::vector<std::string>&){
    ++sends;CommandExecutionResult r;r.status=sends==failAt?CommandExecutionStatus::TransmissionFailed:CommandExecutionStatus::Success;r.message="simulated";return r;
}
bool RFCommandService::send(const std::string&,const std::string&,std::string&){return true;}
bool RFPresetService::execute(int,const std::string&,std::vector<RFPresetExecutionResult>&,std::string&)const{return true;}
void ExecutionDisplay::publish(const ExecutionDisplayNotification&){}
std::vector<std::string> DeviceDatabase::listDevices(){return {};}
bool DeviceDatabase::loadDevice(const std::string&,Device&){return false;}
std::vector<RFDevice> RFDatabase::listPowerDevices(){return {};}
int main(){
    auto root=std::filesystem::temp_directory_path()/"tower-state-test-XXXXXX";std::string name=root.string();assert(mkdtemp(name.data()));std::filesystem::current_path(name);
    json profile={{"discrete",false},{"on",json::array({{{"command","Power"}}})},{"off",json::array({{{"command","Power"}},{{"command","Power"},{"delay_before_seconds",0}}})},{"effects",{{"Power","unknown"}}}};
    DeviceStateService::saveProfile("ir:Dell",profile);std::string error;
    assert(!DeviceStateService::ensure("ir:Dell","off",json::array(),error));assert(sends==0);
    DeviceStateService::correct("ir:Dell","on");
    // Saving either unchanged or edited settings must preserve a manual mark
    // and its provenance; saving a profile must not transmit anything.
    json beforeSave;{std::ifstream in("data/control/device_states.json");in>>beforeSave;}
    DeviceStateService::saveProfile("ir:Dell",profile);
    auto editedProfile=profile;editedProfile["transmitters"]=json::array({"Tower-IR-TX-004"});
    DeviceStateService::saveProfile("ir:Dell",editedProfile);
    json afterSave;{std::ifstream in("data/control/device_states.json");in>>afterSave;}
    assert(afterSave["states"]==beforeSave["states"]);assert(sends==0);
    assert(afterSave["profiles"]["ir:Dell"]==editedProfile);
    assert(DeviceStateService::ensure("ir:Dell","off",json::array(),error));assert(sends==2);assert(DeviceStateService::state("ir:Dell")=="off");
    assert(DeviceStateService::ensure("ir:Dell","off",json::array(),error));assert(sends==2); // Remote then schedule.
    DeviceStateService::correct("ir:Dell","on");sends=0;
    std::thread a([]{std::string e;assert(DeviceStateService::ensure("ir:Dell","off",json::array(),e));});
    std::thread b([]{std::string e;assert(DeviceStateService::ensure("ir:Dell","off",json::array(),e));});a.join();b.join();assert(sends==2);
    DeviceStateService::correct("ir:Dell","on");sends=0;failAt=2;
    assert(!DeviceStateService::ensure("ir:Dell","off",json::array(),error));assert(DeviceStateService::state("ir:Dell")=="unknown");
    failAt=0;
    auto toggle=profile;toggle["off"]=toggle["on"];toggle["effects"]["Power"]="toggle";DeviceStateService::saveProfile("ir:KPN",toggle);DeviceStateService::correct("ir:KPN","off");
    assert(DeviceStateService::track("ir:KPN","Power",[]{return true;}));assert(DeviceStateService::state("ir:KPN")=="on");
    assert(!DeviceStateService::track("ir:KPN","Power",[]{return false;}));assert(DeviceStateService::state("ir:KPN")=="unknown");
    DeviceStateService::correct("ir:KPN","off");assert(DeviceStateService::track("ir:KPN","1",[]{return true;}));assert(DeviceStateService::state("ir:KPN")=="off");
    // State is read from disk each time; an interrupted operation stays unknown.
    std::ifstream in("data/control/device_states.json");json stored;in>>stored;assert(stored["states"]["ir:Dell"]["state"]=="unknown");in.close();
    // Run the same voice path as both the remote and scheduler do.
    std::filesystem::create_directories("data/voice");
    json actions=json::array({{{"type","device_power"},{"device","ir:Dell"},{"state","off"}},{{"type","device_power"},{"device","ir:KPN"},{"state","off"}}});
    {std::ofstream out("data/voice/voice_commands.json");out<<json{{"command_tree",{{"zone",{{"children",{{"shutdown",{{"actions",actions}}}}}}}}}};}
    DeviceStateService::correct("ir:Dell","on");DeviceStateService::correct("ir:KPN","off");sends=0;
    json pathAction={{"type","voice_path"},{"path",json::array({"zone","shutdown"})}};
    assert(ActionExecutionService().execute(pathAction,error));assert(sends==2); // Only Dell was on.
    assert(ActionExecutionService().execute(pathAction,error));assert(sends==2); // Later schedule skips all.
    std::filesystem::remove_all(name);std::cout<<"Device-state and shared-action tests passed\n";
}
