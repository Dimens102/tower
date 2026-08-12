#pragma once

#include <map>
#include <string>
#include <vector>

#include "devices/device_command.h"


struct IRTransmissionProfile
{
    bool calibrated = false;
    unsigned int carrierKhz = 0;
    unsigned int dutyPercent = 0;
    // Optional per-output duty overrides discovered during transmitter qualification.
    // Missing entries inherit dutyPercent.
    std::map<std::string, unsigned int> transmitterDutyPercent;
    std::string calibrationCommand;
    std::vector<std::string> verifiedTransmitters;
    std::vector<std::string> unreliableTransmitters;
    std::vector<std::string> incompatibleTransmitters;
};

class Device
{
public:
    std::string id;

    std::string name;

    std::string type;

    std::string manufacturer;
    std::string model;

    // Physical handset used to record this logical device's IR commands.
    std::string remoteName;

    std::string location;

    // Default IR output for every command on this device.  Individual
    // commands retain their transmitter field for exceptional overrides.
    std::string transmitter;

    // Device-level IR transmission calibration. Recording data remains in
    // the per-command .ir files; operational carrier/duty and transmitter
    // qualification belong to the physical target device.
    IRTransmissionProfile irProfile;

    bool enabled = true;

    std::vector<std::string> aliases;

    std::vector<DeviceCommand> commands;
};
