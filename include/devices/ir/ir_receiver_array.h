#pragma once

#include <filesystem>
#include <string>
#include <vector>

struct IRReceiverDefinition
{
    int gpio;
    std::string model;
    int nominalCarrierKhz;
    std::string position;
};

struct IRReceiverStatus
{
    IRReceiverDefinition receiver;
    std::string lircDevice;

    bool available() const
    {
        return !lircDevice.empty();
    }
};

class IRReceiverArray
{
public:
    static const std::vector<IRReceiverDefinition>& definitions();

    std::vector<IRReceiverStatus> discover(
        const std::filesystem::path& sysfsRoot = "/sys/class/rc") const;

    bool allAvailable(
        const std::filesystem::path& sysfsRoot = "/sys/class/rc") const;
};
