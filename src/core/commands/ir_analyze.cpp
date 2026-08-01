#include "core/commands/command_handlers.h"

#include "devices/ir/ir_analyzer.h"

#include <filesystem>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <system_error>
#include <vector>

namespace
{
std::filesystem::path latestCapture()
{
    const std::filesystem::path root = std::filesystem::path("captures") / "ir";
    std::error_code error;
    std::filesystem::path latest;
    std::filesystem::file_time_type latestTime;
    bool found = false;

    for (std::filesystem::directory_iterator entry(root, error), end;
         !error && entry != end;
         entry.increment(error))
    {
        if (!entry->is_directory(error))
        {
            error.clear();
            continue;
        }
        const auto modified = entry->last_write_time(error);
        if (error)
        {
            error.clear();
            continue;
        }
        if (!found || modified > latestTime)
        {
            found = true;
            latestTime = modified;
            latest = entry->path();
        }
    }
    if (!found)
    {
        throw std::runtime_error("No captures found under captures/ir");
    }
    return latest;
}

std::string decodeText(const IRFileAnalysis& analysis)
{
    if (analysis.protocol.empty()) return "-";
    std::ostringstream output;
    output << analysis.protocol << " 0x" << std::uppercase << std::hex
           << std::right
           << std::setw(analysis.address > 0xFFF ? 4 : 3) << std::setfill('0')
           << analysis.address << "/0x" << std::setw(2) << analysis.command;
    return output.str();
}
} // namespace

int runIRAnalyzeCommand(int argc, char* argv[])
{
    if (argc > 3)
    {
        std::cerr << "Usage: tower ir-analyze [capture-directory|latest]\n";
        return 1;
    }

    std::filesystem::path directory;
    try
    {
        directory = argc < 3 || std::string(argv[2]) == "latest"
            ? latestCapture()
            : std::filesystem::path(argv[2]);

        const IRAnalyzer analyzer;
        const std::vector<IRReceiverAnalysis> analyses =
            analyzer.analyzeDirectory(directory);

        std::cout
            << "IR capture analysis\n\n"
            << "Capture: " << directory.string() << "\n\n"
            << std::left
            << std::setw(6) << "GPIO"
            << std::setw(12) << "Receiver"
            << std::setw(7) << "kHz"
            << std::setw(8) << "Frames"
            << std::setw(7) << "Valid"
            << std::setw(11) << "Result"
            << "Decode\n"
            << std::setw(6) << "----"
            << std::setw(12) << "---------"
            << std::setw(7) << "---"
            << std::setw(8) << "------"
            << std::setw(7) << "-----"
            << std::setw(11) << "---------"
            << "-----------------------\n";

        for (const IRReceiverAnalysis& item : analyses)
        {
            std::cout
                << std::setw(6) << item.gpio
                << std::setw(12) << item.model
                << std::setw(7) << item.nominalCarrierKhz
                << std::setw(8) << item.analysis.frameCount
                << std::setw(7) << item.analysis.decodedCount
                << std::setw(11) << item.analysis.result()
                << decodeText(item.analysis) << '\n';
        }

        const IRReceiverAnalysis& best = analyses[analyzer.best(analyses)];
        if (!best.analysis.decodedCount)
        {
            std::cout << "\nNo supported protocol decoded from this capture.\n";
            return 2;
        }

        std::cout
            << "\nBest capture: GPIO" << best.gpio << ", "
            << best.nominalCarrierKhz << " kHz ("
            << best.analysis.decodedCount << "/" << best.analysis.frameCount
            << " valid frames)\n"
            << "Stable decode: " << best.analysis.protocol
            << ", address 0x" << std::uppercase << std::hex
            << std::right
            << std::setw(best.analysis.address > 0xFFF ? 4 : 3)
            << std::setfill('0') << best.analysis.address
            << ", command 0x" << std::setw(2) << best.analysis.command
            << std::dec << std::setfill(' ') << "\n";
        return 0;
    }
    catch (const std::exception& error)
    {
        std::cerr << "Analysis failed: " << error.what() << "\n";
        return 1;
    }
}
