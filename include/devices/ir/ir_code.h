#pragma once

#include <cstddef>
#include <string>
#include <vector>

struct IRAnalysisRow
{
    unsigned int gpio = 0;
    std::string receiverModel;
    unsigned int nominalCarrierKhz = 0;
    std::size_t frameCount = 0;
    std::size_t validFrameCount = 0;
    std::string result;
    std::string decodedProtocol;
    unsigned int address = 0;
    unsigned int decodedCommand = 0;
};

struct IRCode
{
    std::string device;
    std::string command;
    std::string description;
    std::string protocol;
    std::string decodedProtocol;
    unsigned int address = 0;
    unsigned int decodedCommand = 0;
    unsigned int carrierKhz = 0;
    unsigned int receiverGpio = 0;
    std::string receiverModel;
    std::string sourceCapture;
    std::size_t captureInitialFrames = 0;
    std::size_t captureRepeatFrames = 0;
    std::vector<IRAnalysisRow> analysis;
    std::vector<unsigned int> pulses;
};
