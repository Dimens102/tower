#pragma once

#include <cstddef>
#include <filesystem>
#include <string>
#include <vector>

struct IRDecode
{
    std::string protocol;
    unsigned address = 0;
    unsigned command = 0;
    unsigned rawCommand = 0;
    bool repeat = false;
    double timingError = 0.0;
};

struct IRFileAnalysis
{
    std::filesystem::path path;
    std::size_t eventCount = 0;
    std::size_t frameCount = 0;
    std::size_t decodedCount = 0;
    std::string protocol;
    unsigned address = 0;
    unsigned command = 0;
    double consistency = 0.0;
    double meanTimingError = 1.0;
    std::size_t repeatFrames = 0;
    std::size_t initialFrames = 0;

    std::string result() const;
};

struct IRReceiverAnalysis
{
    unsigned gpio = 0;
    std::string model;
    unsigned nominalCarrierKhz = 0;
    IRFileAnalysis analysis;
};

struct IRRepresentativeFrame
{
    std::vector<unsigned int> durations;
    IRDecode decode;
};

struct IRRawRepresentativeFrame
{
    std::vector<unsigned int> durations;
    std::size_t matchingFrames = 0;
    std::size_t frameCount = 0;
    double meanTimingError = 1.0;
};

class IRAnalyzer
{
public:
    IRFileAnalysis analyzeFile(const std::filesystem::path& path) const;
    std::vector<IRReceiverAnalysis> analyzeDirectory(
        const std::filesystem::path& directory) const;
    std::size_t best(const std::vector<IRReceiverAnalysis>& analyses) const;
    IRRepresentativeFrame representativeFrame(
        const IRFileAnalysis& analysis) const;
    IRRawRepresentativeFrame rawRepresentativeFrame(
        const IRFileAnalysis& analysis) const;
    unsigned int carrierKhz(const std::string& protocol) const;
};
