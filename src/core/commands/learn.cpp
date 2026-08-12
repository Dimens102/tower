#include "core/commands/command_handlers.h"
#include "core/commands/ir_learning.h"

#include "devices/device_database.h"
#include "devices/ir/ir_analyzer.h"
#include "devices/ir/ir_array_capture.h"
#include "devices/ir/ir_code.h"
#include "devices/ir/ir_database.h"
#include "devices/ir/ir_receiver_array.h"

#include <algorithm>
#include <chrono>
#include <cctype>
#include <ctime>
#include <filesystem>
#include <iomanip>
#include <iostream>
#include <map>
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

std::vector<std::string> findDuplicateCommands(
    IRDatabase& database,
    const std::string& deviceName,
    const std::string& commandName,
    const IRCode& candidate)
{
    std::vector<std::string> duplicates;
    const std::filesystem::path directory =
        std::filesystem::path("data") / "ir" / "devices" / deviceName;

    std::error_code error;
    if (!std::filesystem::is_directory(directory, error)) return duplicates;

    std::filesystem::directory_iterator iterator(directory, error);
    const std::filesystem::directory_iterator end;
    while (!error && iterator != end)
    {
        const std::filesystem::directory_entry& entry = *iterator;
        if (entry.is_regular_file(error) && entry.path().extension() == ".ir")
        {
            const std::string existingName = entry.path().stem().string();
            if (existingName != commandName)
            {
                IRCode existing;
                if (database.load(deviceName, existingName, existing) &&
                    !candidate.decodedProtocol.empty() &&
                    existing.decodedProtocol == candidate.decodedProtocol &&
                    existing.address == candidate.address &&
                    existing.decodedCommand == candidate.decodedCommand)
                {
                    duplicates.push_back(existingName);
                }
            }
        }
        iterator.increment(error);
    }

    if (error)
    {
        std::cerr << "Warning: could not finish checking for duplicate commands: "
                  << error.message() << "\n";
    }
    return duplicates;
}


unsigned int existingDeviceCarrierKhz(
    IRDatabase& database,
    const std::string& deviceName)
{
    const std::filesystem::path directory =
        std::filesystem::path("data") / "ir" / "devices" / deviceName;
    std::error_code error;
    if (!std::filesystem::is_directory(directory, error)) return 0;

    std::map<unsigned int, std::size_t> counts;
    for (const auto& entry : std::filesystem::directory_iterator(directory, error))
    {
        if (error) break;
        if (!entry.is_regular_file(error) || entry.path().extension() != ".ir") continue;
        IRCode code;
        if (database.load(deviceName, entry.path().stem().string(), code) &&
            code.carrierKhz > 0)
        {
            ++counts[code.carrierKhz];
        }
    }
    if (counts.empty()) return 0;
    return std::max_element(
        counts.begin(), counts.end(),
        [](const auto& left, const auto& right) {
            return left.second < right.second;
        })->first;
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

        // A multi-press learning capture does not need every detected frame to
        // decode successfully. Some remotes can produce a few truncated/noisy
        // frames while still providing an unambiguous supported-protocol decode.
        const bool stableDecode =
            best.analysis.decodedCount >= 2 &&
            best.analysis.consistency == 1.0;

        IRCode code;
        code.device = deviceName;
        code.command = commandName;
        code.description = description;
        code.protocol = "raw";
        code.sourceCapture = destination.string();

        const IRReceiverAnalysis* selected = &best;
        if (best.analysis.result() == "CLEAN" || stableDecode)
        {
            if (best.analysis.result() != "CLEAN")
            {
                std::cout << "\nAccepting stable partial capture: "
                          << best.analysis.decodedCount << "/"
                          << best.analysis.frameCount
                          << " frames decoded and all valid decodes agree.\n";
            }

            const IRRepresentativeFrame frame = analyzer.representativeFrame(best.analysis);
            code.decodedProtocol = best.analysis.protocol;
            code.address = best.analysis.address;
            code.decodedCommand = best.analysis.command;
            // The tuned receiver array gives a better operational carrier
            // candidate than a protocol-family constant. Final transmission
            // calibration can refine it after the remote is learned.
            code.carrierKhz = best.nominalCarrierKhz;
            code.receiverGpio = best.gpio;
            code.receiverModel = best.model;
            code.captureInitialFrames = best.analysis.initialFrames;
            code.captureRepeatFrames = best.analysis.repeatFrames;
            code.pulses = frame.durations;
        }
        else
        {
            // Unsupported-protocol raw fallback. This is intentionally only
            // enabled when this device already has learned commands with a
            // known carrier. That lets us choose the correct tuned receiver
            // without guessing the modulation frequency.
            const unsigned int knownCarrier = existingDeviceCarrierKhz(database, deviceName);
            if (knownCarrier == 0)
            {
                std::cerr << "No stable supported protocol was found, and this device has no "
                             "previous learned carrier to use for safe RAW fallback. "
                             "Capture retained for 'tower ir-analyze', but no command was saved.\n";
                return 2;
            }

            const auto receiver = std::find_if(
                analyses.begin(), analyses.end(),
                [knownCarrier](const IRReceiverAnalysis& item) {
                    return item.nominalCarrierKhz == knownCarrier;
                });
            if (receiver == analyses.end() || receiver->analysis.frameCount < 2)
            {
                std::cerr << "No stable supported protocol was found. Known device carrier is "
                          << knownCarrier << " kHz, but that receiver did not capture at least "
                             "two frames. Capture retained, but no command was saved.\n";
                return 2;
            }

            const IRRawRepresentativeFrame raw =
                analyzer.rawRepresentativeFrame(receiver->analysis);
            const std::size_t minimumMatches = std::max<std::size_t>(
                2, (raw.frameCount + 1) / 2);
            if (raw.matchingFrames < minimumMatches)
            {
                std::cerr << "No stable supported protocol was found. RAW frames at "
                          << knownCarrier << " kHz were not consistent enough ("
                          << raw.matchingFrames << "/" << raw.frameCount
                          << " matched). Capture retained, but no command was saved.\n";
                return 2;
            }

            selected = &*receiver;
            code.carrierKhz = knownCarrier;
            code.receiverGpio = receiver->gpio;
            code.receiverModel = receiver->model;
            code.captureInitialFrames = receiver->analysis.initialFrames;
            code.captureRepeatFrames = receiver->analysis.repeatFrames;
            code.pulses = raw.durations;

            std::cout << "\nSupported-protocol decode failed, but the "
                      << knownCarrier << " kHz receiver captured a stable repeated RAW frame ("
                      << raw.matchingFrames << "/" << raw.frameCount
                      << " matching). Saving verified RAW timing instead.\n";
        }

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

        const std::vector<std::string> duplicates = findDuplicateCommands(
            database, deviceName, commandName, code);
        if (!duplicates.empty())
        {
            std::cout << "\nWARNING: This IR signal is already saved as";
            if (duplicates.size() == 1)
            {
                std::cout << " '" << duplicates.front() << "'.\n";
            }
            else
            {
                std::cout << ":\n";
                for (const std::string& duplicate : duplicates)
                    std::cout << "  - " << duplicate << "\n";
            }
            std::cout << "Protocol : " << code.decodedProtocol << "\n"
                      << "Address  : ";
            printHex(code.address, code.address > 0xFFF ? 4 : 3);
            std::cout << "\nCommand  : ";
            printHex(code.decodedCommand, 2);
            std::cout << "\nKeep duplicate command '" << commandName
                      << "'? [y/N]: ";

            std::string answer;
            if (!std::getline(std::cin, answer)) return 1;
            if (answer != "y" && answer != "Y" &&
                answer != "yes" && answer != "YES")
            {
                std::cout << "Duplicate command was not saved. "
                             "Raw capture retained at "
                          << destination.string() << "\n";
                return learnIrDuplicateDeclined;
            }
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

        std::cout << "\nLearned successfully\n\n";
        if (!code.decodedProtocol.empty())
        {
            std::cout << "Protocol : " << code.decodedProtocol << "\n"
                      << "Address  : ";
            printHex(code.address, code.address > 0xFFF ? 4 : 3);
            std::cout << "\nCommand  : ";
            printHex(code.decodedCommand, 2);
            std::cout << "\n";
        }
        else
        {
            std::cout << "Protocol : RAW (stable undecoded capture)\n";
        }
        std::cout << "Receiver : GPIO" << code.receiverGpio << " "
                  << code.receiverModel << " (" << selected->nominalCarrierKhz << " kHz)\n"
                  << "Carrier candidate: " << code.carrierKhz << " kHz\n"
                  << "Capture  : " << code.captureInitialFrames << " initial / "
                  << code.captureRepeatFrames << " protocol repeat frames\n"
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
