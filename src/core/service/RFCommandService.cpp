#include "core/service/RFCommandService.h"

#include "core/service/ExecutionDisplay.h"

#include "devices/rf/rf_database.h"
#include "devices/rf/rf_sender.h"

#include "core/service/DeviceStateService.h"
#include <map>
#include <mutex>


bool RFCommandService::send(
    const std::string& deviceName,
    const std::string& action,
    std::string& error)
{
    std::lock_guard<std::recursive_mutex> stateLock(DeviceStateService::executionMutex());
    if(DeviceStateService::disabled("rf:"+deviceName)){error.clear();ExecutionDisplay::publish({deviceName,"Disabled","Skipped","No signal sent",true,5});return true;}
    if (action != "on" && action != "off" && action != "toggle")
    {
        error = "Action must be on, off, or toggle";
        return false;
    }

    RFDatabase database;
    RFDevice device;

    if (!database.loadPowerDevice(deviceName, device))
    {
        error = "RF device not found";
        return false;
    }

    const std::string resolvedAction = action == "toggle"
        ? (DeviceStateService::state("rf:"+deviceName)=="on" ? "off" : "on") : action;
    RFSender sender;
    if (!DeviceStateService::track("rf:"+deviceName, resolvedAction, [&]{return sender.send(device, resolvedAction == "on");}))
    {
        error = "RF transmission failed";
        ExecutionDisplay::publish({
            "RF command",
            device.deviceName.empty() ? device.name : device.deviceName,
            resolvedAction,
            "FAILED",
            false,
            5,
        });
        return false;
    }

    error.clear();
    ExecutionDisplay::publish({
        "RF command",
        device.deviceName.empty() ? device.name : device.deviceName,
        resolvedAction,
        "OK - command sent",
        true,
        5,
    });
    return true;
}
