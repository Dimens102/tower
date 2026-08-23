#include "core/commands/command_handlers.h"
#include "core/commands/ir_learning.h"

#include "devices/ir/ir_database.h"
#include "devices/ir/ir_sender.h"
#include "devices/ir/ir_transmitter.h"
#include "devices/ir/ir_transmitter_database.h"
#include "devices/device.h"
#include "devices/device_database.h"

#include <cctype>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <chrono>
#include <thread>
#include <vector>
#include <algorithm>
#include <string>

namespace
{
struct LearnWizardDefaults
{
    std::string manufacturer;
    std::string remoteName;
    std::string deviceName;
};

std::string trim(const std::string& value)
{
    std::size_t first = 0;
    while (first < value.size() &&
           std::isspace(static_cast<unsigned char>(value[first])))
        ++first;

    std::size_t last = value.size();
    while (last > first &&
           std::isspace(static_cast<unsigned char>(value[last - 1])))
        --last;

    return value.substr(first, last - first);
}

bool answerIsYes(const std::string& answer, bool defaultYes)
{
    const std::string cleaned = trim(answer);
    if (cleaned.empty()) return defaultYes;
    return cleaned == "y" || cleaned == "Y" || cleaned == "yes" || cleaned == "YES";
}

bool validName(const std::string& value)
{
    return !value.empty() && value != "." && value != ".." &&
        value.find('/') == std::string::npos &&
        value.find('\\') == std::string::npos;
}

const std::filesystem::path& learnWizardDefaultsPath()
{
    static const std::filesystem::path path =
        std::filesystem::path("data") / "ir" / ".learn_wizard_defaults";
    return path;
}

LearnWizardDefaults loadLearnWizardDefaults()
{
    LearnWizardDefaults defaults;
    std::ifstream input(learnWizardDefaultsPath());
    if (!input) return defaults;

    std::getline(input, defaults.manufacturer);
    std::getline(input, defaults.remoteName);
    std::getline(input, defaults.deviceName);

    defaults.manufacturer = trim(defaults.manufacturer);
    defaults.remoteName = trim(defaults.remoteName);
    defaults.deviceName = trim(defaults.deviceName);
    if (!validName(defaults.deviceName)) defaults.deviceName.clear();
    return defaults;
}

bool saveLearnWizardDefaults(const LearnWizardDefaults& defaults)
{
    std::error_code error;
    std::filesystem::create_directories(
        learnWizardDefaultsPath().parent_path(), error);
    if (error) return false;

    std::ofstream output(
        learnWizardDefaultsPath(), std::ios::out | std::ios::trunc);
    if (!output) return false;

    output << defaults.manufacturer << '\n'
           << defaults.remoteName << '\n'
           << defaults.deviceName << '\n';
    return static_cast<bool>(output);
}

std::string promptValue(
    const std::string& label,
    const std::string& currentValue,
    const std::string& newDefault = "")
{
    const std::string fallback = currentValue.empty() ? newDefault : currentValue;
    std::cout << label;
    if (!fallback.empty()) std::cout << " [" << fallback << "]";
    std::cout << ": ";

    std::string value;
    if (!std::getline(std::cin, value)) return "";
    value = trim(value);
    return value.empty() ? fallback : value;
}

std::string normalizeTransmitter(const std::string& value)
{
    const std::string cleaned = trim(value);
    if (cleaned.rfind("Tower-IR-TX-", 0) == 0)
    {
        const std::string suffix = cleaned.substr(12);
        if (suffix.size() == 3 && suffix >= "001" && suffix <= "006")
            return cleaned;
        return "";
    }

    try
    {
        std::size_t parsed = 0;
        const int output = std::stoi(cleaned, &parsed);
        if (parsed == cleaned.size() && output >= 1 && output <= 6)
        {
            std::string result = "Tower-IR-TX-00";
            result.back() = static_cast<char>('0' + output);
            return result;
        }
    }
    catch (...)
    {
    }

    return "";
}

std::string defaultCalibrationCommand(const Device& device)
{
    const char* preferred[] = {"Volume Up", "Volume Down", "Program Up", "Program Down",
                               "Channel Up", "Channel Down", "Temperature Up", "Temperature Down"};
    for (const char* name : preferred)
        for (const DeviceCommand& command : device.commands)
            if (command.transport == TransportType::IR && command.id == name) return command.id;
    for (const DeviceCommand& command : device.commands)
        if (command.transport == TransportType::IR && command.id.find("Power") == std::string::npos)
            return command.id;
    return "";
}

int promptObservedActions(unsigned int sent)
{
    while (true)
    {
        std::cout << "How many device actions occurred? [0-" << (sent * 3) << "]: ";
        std::string text;
        if (!std::getline(std::cin, text)) return -1;
        try
        {
            std::size_t used = 0;
            const int value = std::stoi(trim(text), &used);
            if (used == trim(text).size() && value >= 0 && value <= static_cast<int>(sent * 3))
                return value;
        }
        catch (...) {}
        std::cout << "Enter the number of visible actions. Values above " << sent
                  << " are allowed so over-triggering can be detected.\n";
    }
}

bool sendCalibrationBatch(
    const IRCode& code,
    const std::string& transmitterName,
    unsigned int carrierKhz,
    unsigned int dutyPercent,
    unsigned int count)
{
    IRTransmitterDatabase transmitterDatabase;
    IRTransmitter transmitter;
    if (!transmitterDatabase.load(transmitterName, transmitter))
    {
        std::cerr << "Could not load " << transmitterName << " for calibration.\n";
        return false;
    }
    IRSender sender;

    std::cout << "Starting in 5 seconds...\n";
    std::this_thread::sleep_for(std::chrono::seconds(5));

    for (unsigned int index = 0; index < count; ++index)
    {
        std::cout << "Sending " << (index + 1) << "/" << count << "...\n";
        if (!sender.send(code, transmitter, dutyPercent, carrierKhz)) return false;
        if (index + 1 < count)
            std::this_thread::sleep_for(std::chrono::seconds(1));
    }
    return true;
}

enum class CandidateResult
{
    Fail,
    Marginal,
    CleanPass,
    OverTriggered
};

struct CandidateCheck
{
    CandidateResult result = CandidateResult::Fail;
    int firstObserved = 0;
    int secondObserved = -1;
};

constexpr unsigned int kCalibrationBatchSize = 10;
constexpr unsigned int kCalibrationConfirmThreshold = 8;

CandidateCheck testCalibrationCandidate(
    const IRCode& code,
    const std::string& transmitterName,
    unsigned int carrierKhz,
    unsigned int dutyPercent)
{
    CandidateCheck check;

    if (!sendCalibrationBatch(
            code, transmitterName, carrierKhz, dutyPercent, kCalibrationBatchSize))
    {
        check.firstObserved = -1;
        return check;
    }

    check.firstObserved = promptObservedActions(kCalibrationBatchSize);
    if (check.firstObserved < 0) return check;

    if (check.firstObserved > static_cast<int>(kCalibrationBatchSize))
    {
        check.result = CandidateResult::OverTriggered;
        return check;
    }

    // Below 80% is clearly not reliable enough to spend a confirmation batch on.
    if (check.firstObserved < static_cast<int>(kCalibrationConfirmThreshold))
    {
        check.result = CandidateResult::Fail;
        return check;
    }

    std::cout << "Result " << check.firstObserved << "/" << kCalibrationBatchSize
              << ". Confirming the same setting with another "
              << kCalibrationBatchSize << " transmissions.\n";

    if (!sendCalibrationBatch(
            code, transmitterName, carrierKhz, dutyPercent, kCalibrationBatchSize))
    {
        check.secondObserved = -1;
        return check;
    }

    check.secondObserved = promptObservedActions(kCalibrationBatchSize);
    if (check.secondObserved < 0) return check;

    if (check.secondObserved > static_cast<int>(kCalibrationBatchSize))
    {
        check.result = CandidateResult::OverTriggered;
        return check;
    }

    if (check.firstObserved == static_cast<int>(kCalibrationBatchSize) &&
        check.secondObserved == static_cast<int>(kCalibrationBatchSize))
    {
        check.result = CandidateResult::CleanPass;
        return check;
    }

    if (check.firstObserved >= static_cast<int>(kCalibrationConfirmThreshold) &&
        check.secondObserved >= static_cast<int>(kCalibrationConfirmThreshold))
    {
        check.result = CandidateResult::Marginal;
        return check;
    }

    check.result = CandidateResult::Fail;
    return check;
}

bool calibrateDeviceIR(Device& device, DeviceDatabase& deviceDatabase)
{
    std::string answer;
    std::cout << "\nRun IR transmission calibration now? [Y/n]: ";
    if (!std::getline(std::cin, answer)) return false;
    if (!answerIsYes(answer, true)) return true;

    const std::string suggested = defaultCalibrationCommand(device);
    if (suggested.empty())
    {
        std::cout << "No safe non-power IR command is available for calibration. Skipping.\n";
        return true;
    }

    std::cout << "Use a command where one transmission produces one clearly countable action.\n";
    const std::string commandName = promptValue("Calibration command", device.irProfile.calibrationCommand, suggested);
    if (!std::cin) return false;

    IRDatabase irDatabase;
    IRCode code;
    if (!irDatabase.load(device.id, commandName, code))
    {
        std::cerr << "Could not load calibration command '" << commandName << "'.\n";
        return false;
    }

    unsigned int carrier = device.irProfile.carrierKhz > 0
        ? device.irProfile.carrierKhz
        : (code.carrierKhz > 0 ? code.carrierKhz : 38);
    unsigned int duty = device.irProfile.dutyPercent > 0 ? device.irProfile.dutyPercent : 33;
    // Temporary single-output calibration mode while the multi-emitter power
    // distribution is being investigated.
    std::string calibrationTransmitter = "Tower-IR-TX-001";

    std::cout << "\nCalibration transmitter is temporarily fixed to Tower-IR-TX-001.\n"
              << "TX-002 through TX-006 will not be transmitted during calibration.\n";
    std::cout << "\nCalibration uses 10 discrete taps per batch.\n"
              << "Each batch waits 5 seconds before starting, then sends one tap every second.\n"
              << "An 8/10, 9/10 or 10/10 result is confirmed with a second batch.\n"
              << "Only 10/10 in both batches is a clean pass; more than 10 means over-triggering.\n";

    // Duty search: choose the lowest reliable duty. Preserve an already calibrated
    // value as the first candidate when revisiting an existing device.
    std::vector<unsigned int> duties;
    if (device.irProfile.dutyPercent >= 10 && device.irProfile.dutyPercent <= 60)
        duties.push_back(device.irProfile.dutyPercent);
    for (unsigned int candidate : {33U, 40U, 50U, 60U})
        if (std::find(duties.begin(), duties.end(), candidate) == duties.end()) duties.push_back(candidate);

    bool dutyFound = false;
    int centerCarrierHits = -1;
    for (unsigned int candidate : duties)
    {
        std::cout << "\nTesting " << carrier << " kHz at " << candidate << "% duty on "
                  << calibrationTransmitter << ".\n";

        const CandidateCheck check =
            testCalibrationCandidate(code, calibrationTransmitter, carrier, candidate);
        if (check.firstObserved < 0 || check.secondObserved < -1) return false;

        if (check.result == CandidateResult::OverTriggered)
        {
            std::cout << "Over-triggering detected. This command is unsuitable for calibration; "
                         "choose a different calibration command.\n";
            return true;
        }

        if (check.result == CandidateResult::CleanPass)
        {
            duty = candidate;
            dutyFound = true;
            centerCarrierHits = static_cast<int>(kCalibrationBatchSize);
            break;
        }

        if (check.result == CandidateResult::Marginal)
        {
            std::cout << candidate
                      << "% duty was close but did not achieve 10/10 in both batches. "
                         "Trying the next duty.\n";
        }
    }
    if (!dutyFound)
    {
        std::cout
            << "\nNo reliably confirmed duty setting was found on Tower-IR-TX-001.\n"
            << "TX-002 through TX-006 are currently excluded from calibration while "
               "the multi-emitter power distribution is being investigated.\n"
            << "The existing device profile has not been replaced.\n";
        return true;
    }

    // Carrier refinement around the analyzer-selected tuned receiver.
    // The center carrier already passed during duty calibration, so do not
    // transmit it a second time. Test only -1/+1 kHz and prefer the center on ties.
    int bestHits = centerCarrierHits;
    unsigned int bestCarrier = carrier;

    for (int offset : {-1, 1})
    {
        const int candidateInt = static_cast<int>(carrier) + offset;
        if (candidateInt < 20 || candidateInt > 60) continue;
        const unsigned int candidate = static_cast<unsigned int>(candidateInt);

        std::cout << "\nCarrier check: " << candidate << " kHz at " << duty << "% duty.\n";
        if (!sendCalibrationBatch(
                code, calibrationTransmitter, candidate, duty, kCalibrationBatchSize))
            return false;
        const int observed = promptObservedActions(kCalibrationBatchSize);
        if (observed < 0) return false;

        if (observed > static_cast<int>(kCalibrationBatchSize))
        {
            std::cout << "Over-triggering detected at " << candidate
                      << " kHz; keeping center carrier " << carrier << " kHz.\n";
            continue;
        }

        // Strictly better only. Equal scores retain the analyzer/center carrier.
        if (observed > bestHits)
        {
            bestHits = observed;
            bestCarrier = candidate;
        }
    }

    carrier = bestCarrier;

    device.irProfile.calibrationCommand = commandName;
    device.irProfile.carrierKhz = carrier;
    device.irProfile.dutyPercent = duty;
    device.irProfile.calibrated = true;

    std::cout << "\nPrimary calibration result\n"
              << "Carrier     : " << carrier << " kHz\n"
              << "Duty        : " << duty << "%\n"
              << "Transmitter : " << calibrationTransmitter << "\n"
              << "Command     : " << commandName << "\n";

    // Temporary TX-001-only qualification mode. The primary calibration above
    // already confirmed this output, so do not pulse TX-002..TX-006.
    device.irProfile.verifiedTransmitters = {"Tower-IR-TX-001"};
    device.irProfile.unreliableTransmitters.clear();
    device.irProfile.incompatibleTransmitters.clear();
    device.irProfile.transmitterDutyPercent.clear();

    std::cout << "\nTX-001-only calibration mode\n"
              << "Verified transmitter : Tower-IR-TX-001\n"
              << "TX-002..TX-006        : not tested / not classified\n";


    if (!deviceDatabase.saveDevice(device))
    {
        std::cerr << "Could not save IR transmission calibration.\n";
        return false;
    }

    std::cout << "\nIR transmission profile saved to data/devices/" << device.id << ".json\n";
    return true;
}

} // namespace

int runLearnWizard()
{
    std::cout
        << "IR device recording wizard\n\n"
        << "Every button is captured through all six IR receivers.\n"
        << "Leave the command name empty when this device is complete.\n\n";

    const LearnWizardDefaults defaults = loadLearnWizardDefaults();

    const std::string manufacturer = promptValue(
        "Manufacturer", "", defaults.manufacturer);
    if (!std::cin) return 1;

    const std::string remoteName = promptValue(
        "Remote name", "", defaults.remoteName);
    if (!std::cin) return 1;

    std::string deviceName;
    while (!validName(deviceName))
    {
        deviceName = promptValue("Device name", "", defaults.deviceName);
        if (!std::cin) return 1;
        if (!validName(deviceName))
            std::cout << "Use a name without '/' or '\\'.\n";
    }

    DeviceDatabase deviceDatabase;
    Device device;
    if (deviceDatabase.deviceExists(deviceName))
    {
        if (!deviceDatabase.loadDevice(deviceName, device))
        {
            std::cerr << "Could not load the existing device details.\n";
            return 1;
        }
    }
    else
    {
        device.id = deviceName;
        device.name = deviceName;
        device.type = "IR Device";
        device.enabled = true;
    }

    device.name = deviceName;
    if (!manufacturer.empty()) device.manufacturer = manufacturer;
    if (!remoteName.empty()) device.remoteName = remoteName;

    device.location = promptValue("Location", device.location);
    if (!std::cin) return 1;

    // Temporary single-transmitter mode while the multi-emitter power
    // distribution is being investigated.
    device.transmitter = "Tower-IR-TX-001";
    std::cout
        << "\nTransmitter fixed to Tower-IR-TX-001 while TX-002 through TX-006 "
           "remain out of service.\n";

    // The wizard's transmitter selection is a device-level setting.  Apply
    // it to existing IR commands as well as every command recorded below.
    for (DeviceCommand& command : device.commands)
    {
        if (command.transport == TransportType::IR)
            command.transmitter = device.transmitter;
    }

    if (!deviceDatabase.saveDevice(device))
    {
        std::cerr << "Could not save the device information.\n";
        return 1;
    }

    if (!saveLearnWizardDefaults(
            {device.manufacturer, device.remoteName, device.name}))
    {
        std::cerr << "Warning: could not remember the wizard defaults.\n";
    }

    std::cout
        << "\nDevice saved\n"
        << "Manufacturer : " << device.manufacturer << "\n"
        << "Remote name  : " << device.remoteName << "\n"
        << "Device name  : " << device.name << "\n"
        << "Location     : " << device.location << "\n"
        << "Transmitter  : " << device.transmitter << "\n";

    IRDatabase database;
    unsigned int recorded = 0;

    while (true)
    {
        std::string commandName;
        std::cout << "\nCommand name (Enter to finish): ";
        if (!std::getline(std::cin, commandName)) return 1;
        commandName = trim(commandName);
        if (commandName.empty()) break;
        if (!validName(commandName))
        {
            std::cout
                << "Use a stable name without '/' or '\\', for example "
                   "PausePlay or VolumeUp.\n";
            continue;
        }

        std::string description;
        std::cout << "Description: ";
        if (!std::getline(std::cin, description)) return 1;
        description = trim(description);

        bool force = false;
        if (database.exists(deviceName, commandName))
        {
            std::string answer;
            std::cout << "That command already exists. Replace it? [y/N]: ";
            if (!std::getline(std::cin, answer)) return 1;
            force = answerIsYes(answer, false);
            if (!force)
            {
                std::cout << "Existing command kept.\n";
                continue;
            }
        }

        bool tryAgain = false;
        do
        {
            std::cout
                << "Aim the remote at the receiver array.\n"
                << "Press Enter when ready, then press the '" << commandName
                << "' button several times during the 8-second recording.";
            std::string ready;
            if (!std::getline(std::cin, ready)) return 1;

            const int result = learnIRCommand(
                deviceName, commandName, description, 8.0, force);
            if (result == 0)
            {
                ++recorded;
                tryAgain = false;
                continue;
            }
            if (result == learnIrDuplicateDeclined)
            {
                tryAgain = false;
                continue;
            }

            std::string answer;
            std::cout << "Recording was not saved. Try this command again? [Y/n]: ";
            if (!std::getline(std::cin, answer)) return 1;
            tryAgain = answerIsYes(answer, true);
        }
        while (tryAgain);
    }

    const std::filesystem::path directory =
        std::filesystem::path("data") / "ir" / "devices" / deviceName;

    std::cout
        << "\nDevice complete\n\n"
        << "Device   : " << deviceName << "\n"
        << "Recorded : " << recorded << " command"
        << (recorded == 1 ? "" : "s") << "\n"
        << "Folder   : " << directory.string() << "\n";

    // Reload because learnIRCommand updates the logical command list while the
    // wizard is running. Calibration is deliberately device-level and generic.
    if (!deviceDatabase.loadDevice(deviceName, device)) return 1;
    if (!calibrateDeviceIR(device, deviceDatabase)) return 1;

    return 0;
}
