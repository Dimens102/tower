#include "core/commands/command_handlers.h"
#include "core/commands/ir_learning.h"

#include "devices/device_database.h"
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
constexpr const char* defaultTransmitter = "Tower-IR-TX-001";

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

std::string analysisDecodeText(const IRFileAnalysis& analysis)
{
    if (analysis.protocol.empty()) return "-";

    std::ostringstream output;
    output << analysis.protocol << " 0x" << std::uppercase << std::hex
           << std::right
           << std::setw(analysis.address > 0xFFF ? 4 : 3) << std::setfill('0')
           << analysis.address << "/0x" << std::setw(2) << analysis.command;
    return output.str();
}

void printAnalysisTable(
    const std::filesystem::path& captureDirectory,
    const std::vector<IRReceiverAnalysis>& analyses)
{
    std::cout
        << "\nIR capture analysis\n\n"
        << "Capture: " << captureDirectory.string() << "\n\n"
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
            << analysisDecodeText(item.analysis) << '\n';
    }
}

bool updateLogicalCommand(
    const std::string& deviceName,
    const std::string& commandName,
    const std::string& description)
{
    DeviceDatabase database;
    Device device;

    if (!database.deviceExists(deviceName))
    {
        device.id = deviceName;
        device.name = deviceName;
        device.transmitter = defaultTransmitter;
        device.enabled = true;
    }
    else if (!database.loadDevice(deviceName, device))
    {
        return false;
    }

    for (DeviceCommand& command : device.commands)
    {
        if (command.id != commandName) continue;

        command.name = commandName;
        command.description = description;
        command.transport = TransportType::IR;
        command.transportDevice = deviceName;
        command.transportCommand = commandName;
        if (command.transmitter.empty())
            command.transmitter = device.transmitter.empty()
                ? defaultTransmitter : device.transmitter;
        command.enabled = true;
        return database.saveDevice(device);
    }

    DeviceCommand command;
    command.id = commandName;
    command.name = commandName;
    command.description = description;
    command.transport = TransportType::IR;
    command.transportDevice = deviceName;
    command.transportCommand = commandName;
    command.transmitter = device.transmitter.empty()
        ? defaultTransmitter : device.transmitter;
    command.enabled = true;
    device.commands.push_back(command);
    return database.saveDevice(device);
}
} // namespace

int learnIRCommand(
    const std::string& deviceName,
    const std::string& commandName,
    const std::string& description,
    double seconds,
    bool force)
{
    if (!validDatabaseName(deviceName) || !validDatabaseName(commandName))
    {
        std::cerr << "Device and command names cannot be empty, '.', '..', or contain slashes.\n";
        return 1;
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
        printAnalysisTable(destination, analyses);
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
        code.description = description;
        code.protocol = "raw";
        code.decodedProtocol = best.analysis.protocol;
        code.address = best.analysis.address;
        code.decodedCommand = best.analysis.command;
        code.carrierKhz = analyzer.carrierKhz(best.analysis.protocol);
        code.receiverGpio = best.gpio;
        code.receiverModel = best.model;
        code.sourceCapture = destination.string();
        code.pulses = frame.durations;
        for (const IRReceiverAnalysis& receiver : analyses)
        {
            IRAnalysisRow row;
            row.gpio = receiver.gpio;
            row.receiverModel = receiver.model;
            row.nominalCarrierKhz = receiver.nominalCarrierKhz;
            row.frameCount = receiver.analysis.frameCount;
            row.validFrameCount = receiver.analysis.decodedCount;
            row.result = receiver.analysis.result();
            row.decodedProtocol = receiver.analysis.protocol;
            row.address = receiver.analysis.address;
            row.decodedCommand = receiver.analysis.command;
            code.analysis.push_back(row);
        }

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
        if (!updateLogicalCommand(deviceName, commandName, description))
        {
            std::cerr << "Capture was saved, but the logical device command could not be updated.\n";
            return 1;
        }

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

int runLearnCommand(int argc, char* argv[])
{
    if (argc == 2) return runLearnWizard();

    if (argc < 4 || argc > 6)
    {
        std::cerr << "Usage: tower learn [<device-name> <command-name> "
                     "[seconds] [--force]]\n";
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

    return learnIRCommand(argv[2], argv[3], "", seconds, force);
}
