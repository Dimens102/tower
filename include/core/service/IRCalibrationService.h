#pragma once

#include <string>
#include <vector>

struct IRCalibrationCommandInfo
{
    std::string id;
    std::string description;
    unsigned int carrierKhz = 38;
};

struct IRCalibrationPreparation
{
    std::vector<IRCalibrationCommandInfo> commands;
    std::string suggestedCommand;
    std::string transmitter = "Tower-IR-TX-001";
    std::vector<unsigned int> dutyCandidates;
    unsigned int batchSize = 10;
    unsigned int confirmThreshold = 8;
    bool alreadyCalibrated = false;
    unsigned int existingCarrierKhz = 0;
    unsigned int existingDutyPercent = 0;
    std::string existingCommand;
};

class IRCalibrationService
{
public:
    bool prepare(
        const std::string& deviceName,
        IRCalibrationPreparation& preparation,
        std::string& error) const;

    bool sendBatch(
        const std::string& deviceName,
        const std::string& commandName,
        unsigned int carrierKhz,
        unsigned int dutyPercent,
        unsigned int count,
        unsigned int preDelaySeconds,
        unsigned int intervalMilliseconds,
        std::string& error) const;

    bool saveProfile(
        const std::string& deviceName,
        const std::string& commandName,
        unsigned int carrierKhz,
        unsigned int dutyPercent,
        std::string& error) const;
};
