#pragma once

#include <string>

#include "devices/rf/rf_device.h"

struct RFModernDefaults
{
    std::string recordName;
    std::string transmitterId;
    std::string description;
    int unit = 1;
    int gpio = 24;
    int pulse = 260;
    int repeat = 16;
};

class RFProvisioningService
{
public:
    bool getNextModernDefaults(
        RFModernDefaults& defaults,
        std::string& error) const;

    bool createModernPowerDevice(
        const std::string& deviceName,
        const std::string& description,
        const std::string& transmitterId,
        int unit,
        RFDevice& created,
        std::string& error) const;

    bool setPairingStatus(
        const std::string& recordName,
        bool paired,
        std::string& error) const;

    static bool normalizeTransmitterId(
        const std::string& input,
        std::string& normalized,
        std::string& error);
};
