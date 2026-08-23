#include "core/commands/command_handlers.h"
#include "core/commands/ir_learning.h"
#include "core/service/IRLearningService.h"

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
    IRLearningService learning;
    IRLearnResult result;
    std::string error;

    std::cout
        << "IR learning\n\n"
        << "Device   : " << deviceName << "\n"
        << "Command  : " << commandName << "\n"
        << "Duration : " << seconds << " seconds\n\n"
        << "Recording NOW - press the same button several times.\n";

    if (!learning.captureAndAnalyze(
            deviceName,
            commandName,
            description,
            seconds,
            force,
            result,
            error))
    {
        std::cerr << error << "\n";

        if (!result.capturePath.empty())
        {
            std::cerr
                << "Capture  : "
                << result.capturePath
                << "\n";
        }

        return result.failureCode;
    }

    std::cout
        << "\nIR capture analysis\n\n"
        << "Capture: "
        << result.capturePath
        << "\n\n"
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

    for (const IRAnalysisRow& row :
         result.code.analysis)
    {
        std::ostringstream decode;

        if (!row.decodedProtocol.empty())
        {
            decode
                << row.decodedProtocol
                << " 0x"
                << std::uppercase
                << std::hex
                << std::right
                << std::setw(
                    row.address > 0xFFF ? 4 : 3)
                << std::setfill('0')
                << row.address
                << "/0x"
                << std::setw(2)
                << row.decodedCommand
                << std::dec
                << std::setfill(' ');
        }
        else
        {
            decode << "-";
        }

        std::cout
            << std::left
            << std::setw(6) << row.gpio
            << std::setw(12) << row.receiverModel
            << std::setw(7) << row.nominalCarrierKhz
            << std::setw(8) << row.frameCount
            << std::setw(7) << row.validFrameCount
            << std::setw(11) << row.result
            << decode.str()
            << "\n";
    }

    if (!result.note.empty())
    {
        std::cout
            << "\n"
            << result.note
            << "\n";
    }

    bool acceptDuplicate = false;

    if (!result.duplicates.empty())
    {
        std::cout
            << "\nWARNING: This IR signal is already saved as";

        if (result.duplicates.size() == 1)
        {
            std::cout
                << " '"
                << result.duplicates.front()
                << "'.\n";
        }
        else
        {
            std::cout << ":\n";

            for (const std::string& duplicate :
                 result.duplicates)
            {
                std::cout
                    << "  - "
                    << duplicate
                    << "\n";
            }
        }

        if (!result.code.decodedProtocol.empty())
        {
            std::cout
                << "Protocol : "
                << result.code.decodedProtocol
                << "\nAddress  : ";
            printHex(
                result.code.address,
                result.code.address > 0xFFF ? 4 : 3);
            std::cout
                << "\nCommand  : ";
            printHex(
                result.code.decodedCommand,
                2);
            std::cout << "\n";
        }

        std::cout
            << "Keep duplicate command '"
            << commandName
            << "'? [y/N]: ";

        std::string answer;

        if (!std::getline(std::cin, answer))
        {
            return 1;
        }

        acceptDuplicate =
            answer == "y" ||
            answer == "Y" ||
            answer == "yes" ||
            answer == "YES";

        if (!acceptDuplicate)
        {
            std::cout
                << "Duplicate command was not saved. "
                << "Raw capture retained at "
                << result.capturePath
                << "\n";

            return learnIrDuplicateDeclined;
        }
    }

    if (!learning.saveResult(
            result,
            force,
            acceptDuplicate,
            error))
    {
        std::cerr
            << error
            << "\n";
        return 1;
    }

    IRDatabase database;

    std::cout
        << "\nLearned successfully\n\n";

    if (!result.code.decodedProtocol.empty())
    {
        std::cout
            << "Protocol : "
            << result.code.decodedProtocol
            << "\nAddress  : ";

        printHex(
            result.code.address,
            result.code.address > 0xFFF ? 4 : 3);

        std::cout
            << "\nCommand  : ";

        printHex(
            result.code.decodedCommand,
            2);

        std::cout << "\n";
    }
    else
    {
        std::cout
            << "Protocol : RAW "
            << "(stable undecoded capture)\n";
    }

    std::cout
        << "Receiver : GPIO"
        << result.code.receiverGpio
        << " "
        << result.code.receiverModel
        << "\nCarrier candidate: "
        << result.code.carrierKhz
        << " kHz\n"
        << "Capture  : "
        << result.code.captureInitialFrames
        << " initial / "
        << result.code.captureRepeatFrames
        << " protocol repeat frames\n"
        << "Raw frame: "
        << result.code.pulses.size()
        << " timings\n"
        << "Saved    : "
        << database.path(
            deviceName,
            commandName).string()
        << "\n";

    return 0;
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
