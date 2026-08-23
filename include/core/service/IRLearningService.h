#pragma once

#include "devices/device.h"
#include "devices/ir/ir_code.h"

#include <string>
#include <vector>

struct IRReceiverCaptureStat
{
    unsigned int gpio = 0;
    std::string receiverModel;
    unsigned int nominalCarrierKhz = 0;
    std::size_t timingCount = 0;
    std::size_t pulseCount = 0;
    std::size_t frameCount = 0;
    std::size_t validFrameCount = 0;
    std::string result;
};

struct IRLearnResult
{
    int failureCode = 1;
    std::string captureId;
    std::string capturePath;
    std::string deviceName;
    std::string commandName;
    std::string description;
    IRCode code;
    std::vector<std::string> duplicates;
    std::vector<IRReceiverCaptureStat> receiverStats;
    bool rawFallback = false;
    bool stablePartialDecode = false;
    std::string note;
};

class IRLearningService
{
public:
    bool createDevice(
        const std::string& manufacturer,
        const std::string& remoteName,
        const std::string& deviceName,
        const std::string& location,
        const std::string& transmitter,
        Device& created,
        std::string& error) const;

    bool captureAndAnalyze(
        const std::string& deviceName,
        const std::string& commandName,
        const std::string& description,
        double seconds,
        bool force,
        IRLearnResult& result,
        std::string& error) const;

    bool analyzeExistingCapture(
        const std::string& captureId,
        const std::string& deviceName,
        const std::string& commandName,
        const std::string& description,
        IRLearnResult& result,
        std::string& error) const;

    bool saveResult(
        const IRLearnResult& result,
        bool force,
        bool acceptDuplicate,
        std::string& error) const;
};
