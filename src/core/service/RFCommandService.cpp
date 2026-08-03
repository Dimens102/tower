#include "core/service/RFCommandService.h"

#include "devices/rf/rf_database.h"
#include "devices/rf/rf_sender.h"

bool RFCommandService::send(
    const std::string& deviceName,
    const std::string& action,
    std::string& error)
{
    if (action != "on" && action != "off")
    {
        error = "Action must be on or off";
        return false;
    }

    RFDatabase database;
    RFDevice device;

    if (!database.loadPowerDevice(deviceName, device))
    {
        error = "RF device not found";
        return false;
    }

    RFSender sender;
    if (!sender.send(device, action == "on"))
    {
        error = "RF transmission failed";
        return false;
    }

    error.clear();
    return true;
}
