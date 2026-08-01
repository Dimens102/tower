#include "core/commands/command_handlers.h"

#include "devices/ir/ir_analyzer.h"
#include "devices/ir/ir_array_capture.h"
#include "devices/ir/ir_code.h"
#include "devices/ir/ir_database.h"
#include "devices/ir/ir_receiver_array.h"

#include <chrono>
#include <cctype>
#include <ctime>
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
std::string safeName(const std::string& value)
{
    std::string result;
    bool separator = false;
    for (const unsigned char character : value)
    {
        if (std::isalnum(character) || character == '.' || character == '_' ||
            character == '-')
        {
            result.push_back(static_cast<char>(character));
            separator = false;
        }
        else if (!result.empty() && !separator)
        {
            result.push_back('-');
            separator = true;
        }
    }
    while (!result.empty() && (result.back() == '.' || result.back() == '-'))
        result.pop_back();
    if (result.empty()) throw std::invalid_argument("Invalid device or command name");
    return result;
}

bool validDatabaseName(const std::string& value)
{
    return !value.empty() && value != "." && value != ".." &&
        value.find('/') == std::string::npos &&
        value.find('\\') == std::string::npos;
}

std::string utcTimestamp()
{
    const std::time_t now = std::time(nullptr);
    std::tm utc = {};
    gmtime_r(&now, &utc);
    std::ostringstream output;
    output << std::put_time(&utc, "%Y%m%dT%H%M%SZ");
    return output.str();
}

void printHex(unsigned value, unsigned width)
{
    std::cout << "0x" << std::uppercase << std::hex << std::right
              << std::setw(width) << std::setfill('0') << value
              << std::dec << std::setfill(' ');
}
} // namespace

int runLearnCommand(int argc, char* argv[])
{
    if (argc < 4 || argc > 6)
    {
        std::cerr << "Usage: tower learn <device-name> <command-name> "
                     "[seconds] [--force]\n";
        return 1;
    }

    const std::string deviceName = argv[2];
    const std::string commandName = argv[3];
    if (!validDatabaseName(deviceName) || !validDatabaseName(commandName))
    {
        std::cerr << "Device and command names cannot be empty, '.', '..', or contain slashes.\n";
        return 1;
    }

    double seconds = 8.0;
    bool force = false;
    bool durationSet = false;
    for (int index = 4; index < argc; ++index)
    {
        const std::string argument = argv[index];
        if (argument == "--force")
        {
            force = true;
            continue;
        }
        if (durationSet)
        {
            std::cerr << "Only one capture duration may be specified.\n";
            return 1;
        }
        try
        {
            std::size_t parsed = 0;
            seconds = std::stod(argument, &parsed);
            if (parsed != argument.size() || seconds <= 0.0 || seconds > 300.0)
                throw std::invalid_argument("duration");
            durationSet = true;
        }
        catch (...)
        {
            std::cerr << "Capture duration must be between 0 and 300 seconds.\n";
            return 1;
        }
    }

    IRDatabase database;
    if (database.exists(deviceName, commandName) && !force)
    {
        std::cerr << "IR command already exists: " << database.path(deviceName, commandName)
                  << "\nUse --force to replace it after a successful validated capture.\n";
        return 1;
    }

    const IRReceiverArray array;
    const std::vector<IRReceiverStatus> receivers = array.discover();
    if (!array.allAvailable())
    {
        std::cerr << "All six IR receivers must be available. "
                     "Run 'tower ir-receivers' for details.\n";
        return 1;
    }

    std::filesystem::path destination;
    try
    {
        destination = std::filesystem::path("captures") / "ir" /
            (utcTimestamp() + "_" + safeName(deviceName) + "_" + safeName(commandName));
    }
    catch (const std::exception& error)
    {
        std::cerr << error.what() << "\n";
        return 1;
    }

    std::cout << "IR learning\n\n"
              << "Device   : " << deviceName << "\n"
              << "Command  : " << commandName << "\n"
              << "Duration : " << seconds << " seconds\n"
              << "Capture  : " << destination.string() << "\n\n"
              << "Recording NOW - press the same button several times.\n";

    std::vector<IRArrayCaptureResult> captures;
    try
    {
        captures = IRArrayCapture().capture(receivers, destination, seconds);
    }
    catch (const std::exception& error)
    {
        std::cerr << "Capture failed: " << error.what() << "\n";
        return 1;
    }

    bool anySignal = false;
    for (const IRArrayCaptureResult& capture : captures)
    {
        anySignal = anySignal || capture.pulseCount > 0;
        if (irCaptureDiagnosticHasError(capture.diagnostic))
        {
            std::cerr << "Capture error on " << capture.receiver.lircDevice
                      << ": " << capture.diagnostic;
            return 1;
        }
    }
    if (!anySignal)
    {
        std::cerr << "No IR signal was captured. Nothing was saved.\n";
        return 2;
    }

    try
    {
        const IRAnalyzer analyzer;
        const std::vector<IRReceiverAnalysis> analyses =
            analyzer.analyzeDirectory(destination);
        const IRReceiverAnalysis& best = analyses[analyzer.best(analyses)];
        if (best.analysis.result() != "CLEAN")
        {
            std::cerr << "No clean, stable supported protocol was found. "
                         "Capture retained for 'tower ir-analyze', but no command was saved.\n";
            return 2;
        }

        const IRRepresentativeFrame frame = analyzer.representativeFrame(best.analysis);
        IRCode code;
        code.device = deviceName;
        code.command = commandName;
        code.protocol = "raw";
        code.decodedProtocol = best.analysis.protocol;
        code.address = best.analysis.address;
        code.decodedCommand = best.analysis.command;
        code.carrierKhz = analyzer.carrierKhz(best.analysis.protocol);
        code.receiverGpio = best.gpio;
        code.receiverModel = best.model;
        code.sourceCapture = destination.string();
        code.pulses = frame.durations;

        if (database.exists(deviceName, commandName))
        {
            std::filesystem::path backup = database.path(deviceName, commandName);
            backup += ".tower-learn-backup";
            std::error_code error;
            std::filesystem::copy_file(
                database.path(deviceName, commandName), backup,
                std::filesystem::copy_options::overwrite_existing, error);
            if (error)
            {
                std::cerr << "Could not back up existing command: " << error.message() << "\n";
                return 1;
            }
            std::cout << "\nBackup   : " << backup.string() << "\n";
        }

        if (!database.save(deviceName, commandName, code)) return 1;

        std::cout << "\nLearned successfully\n\n"
                  << "Protocol : " << code.decodedProtocol << "\n"
                  << "Address  : ";
        printHex(code.address, code.address > 0xFFF ? 4 : 3);
        std::cout << "\nCommand  : ";
        printHex(code.decodedCommand, 2);
        std::cout << "\nReceiver : GPIO" << code.receiverGpio << " "
                  << code.receiverModel << " (" << best.nominalCarrierKhz << " kHz)\n"
                  << "Carrier  : " << code.carrierKhz << " kHz\n"
                  << "Frames   : " << best.analysis.decodedCount << "/"
                  << best.analysis.frameCount << " valid\n"
                  << "Raw frame: " << code.pulses.size() << " timings\n"
                  << "Saved    : " << database.path(deviceName, commandName).string()
                  << "\n";
        return 0;
    }
    catch (const std::exception& error)
    {
        std::cerr << "Learning analysis failed: " << error.what()
                  << "\nCapture retained, but no command was saved.\n";
        return 1;
    }
}
