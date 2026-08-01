#include "devices/ir/ir_analyzer.h"

#include <cassert>
#include <filesystem>
#include <stdexcept>
#include <string>

namespace fs = std::filesystem;

fs::path findRecording(
    const fs::path& root,
    const std::string& capture,
    unsigned khz)
{
    const std::string suffix = "_" + std::to_string(khz) + "khz.mode2";
    for (const auto& entry : fs::recursive_directory_iterator(root))
    {
        const std::string name = entry.path().filename().string();
        if (entry.is_regular_file() && name.find(capture) != std::string::npos &&
            name.size() >= suffix.size() &&
            name.compare(name.size() - suffix.size(), suffix.size(), suffix) == 0)
        {
            return entry.path();
        }
    }
    throw std::runtime_error("recording not found");
}

void expect(
    const IRAnalyzer& analyzer,
    const fs::path& root,
    const std::string& capture,
    unsigned khz,
    const std::string& protocol,
    unsigned address,
    unsigned command,
    std::size_t valid)
{
    const IRFileAnalysis result = analyzer.analyzeFile(
        findRecording(root, capture, khz));
    assert(result.protocol == protocol);
    assert(result.address == address);
    assert(result.command == command);
    assert(result.decodedCount == valid);
    const IRRepresentativeFrame frame = analyzer.representativeFrame(result);
    assert(!frame.durations.empty());
    assert(frame.decode.protocol == protocol);
    assert(frame.decode.address == address);
    assert(frame.decode.command == command);
    assert(analyzer.carrierKhz(protocol) > 0);
}

int main(int argc, char* argv[])
{
    assert(argc == 2);
    const fs::path recordings = argv[1];
    const IRAnalyzer analyzer;

    expect(analyzer, recordings, "2cc1219c", 56, "Siemens", 0x250, 0x0B, 18);
    expect(analyzer, recordings, "cb99a062", 38, "NECx", 0x504F, 0x11, 15);
    expect(analyzer, recordings, "f94fcb60", 38, "NEC", 0x08, 0x1F, 22);
    expect(analyzer, recordings, "4bcb6ef6", 40, "Sony SIRC-12", 0x01, 0x60, 62);
    expect(analyzer, recordings, "7e98f52b", 38, "Kaseikyo-Denon", 0x01, 0x27, 16);
    expect(analyzer, recordings, "a2700da3", 38, "NEC", 0x04, 0x0D, 15);

    const fs::path group = fs::temp_directory_path() / "tower-ir-analyzer-group-test";
    fs::remove_all(group);
    fs::create_directories(group);
    const unsigned gpios[] = {17, 18, 27, 22, 23, 25};
    const unsigned carriers[] = {30, 33, 36, 38, 40, 56};
    for (std::size_t index = 0; index < 6; ++index)
    {
        fs::copy_file(
            findRecording(recordings, "2cc1219c", carriers[index]),
            group / ("gpio" + std::to_string(gpios[index]) + "_" +
                     std::to_string(carriers[index]) + "khz.mode2"));
    }
    const std::vector<IRReceiverAnalysis> analyses = analyzer.analyzeDirectory(group);
    assert(analyses.size() == 6);
    const IRReceiverAnalysis& best = analyses[analyzer.best(analyses)];
    assert(best.gpio == 25);
    assert(best.nominalCarrierKhz == 56);
    assert(best.analysis.decodedCount == 18);
    fs::remove_all(group);
    return 0;
}
