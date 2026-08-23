#include "core/service/IRLearningService.h"

#include "devices/device_database.h"
#include "devices/ir/ir_analyzer.h"
#include "devices/ir/ir_array_capture.h"
#include "devices/ir/ir_database.h"
#include "devices/ir/ir_receiver_array.h"

#include <algorithm>
#include <cctype>
#include <ctime>
#include <filesystem>
#include <iomanip>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <system_error>
#include <vector>

namespace
{

constexpr const char* kDefaultTransmitter = "Tower-IR-TX-001";

bool validDatabaseName(const std::string& value)
{
    return
        !value.empty() &&
        value != "." &&
        value != ".." &&
        value.find('/') == std::string::npos &&
        value.find('\\') == std::string::npos;
}

bool validTransmitter(const std::string& value)
{
    if (value.rfind("Tower-IR-TX-", 0) != 0)
    {
        return false;
    }

    const std::string suffix = value.substr(12);
    return
        suffix.size() == 3 &&
        suffix >= "001" &&
        suffix <= "006";
}

bool hasLineBreak(const std::string& value)
{
    return
        value.find('\r') != std::string::npos ||
        value.find('\n') != std::string::npos;
}

std::string safeName(const std::string& value)
{
    std::string result;
    bool separator = false;

    for (const unsigned char character : value)
    {
        if (std::isalnum(character) ||
            character == '.' ||
            character == '_' ||
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

    while (!result.empty() &&
           (result.back() == '.' || result.back() == '-'))
    {
        result.pop_back();
    }

    if (result.empty())
    {
        throw std::invalid_argument(
            "Invalid device or command name");
    }

    return result;
}

std::string utcTimestamp()
{
    const std::time_t now = std::time(nullptr);
    std::tm utc = {};
    gmtime_r(&now, &utc);

    std::ostringstream output;
    output << std::put_time(
        &utc,
        "%Y%m%dT%H%M%SZ");

    return output.str();
}

std::vector<std::string> findDuplicateCommands(
    IRDatabase& database,
    const std::string& deviceName,
    const std::string& commandName,
    const IRCode& candidate)
{
    std::vector<std::string> duplicates;

    // RAW captures do not have a stable protocol/address/command identity,
    // so global duplicate matching is only reliable for decoded signals.
    if (candidate.decodedProtocol.empty())
    {
        return duplicates;
    }

    const std::filesystem::path root =
        std::filesystem::path("data") /
        "ir" /
        "devices";

    std::error_code error;
    if (!std::filesystem::is_directory(root, error))
    {
        return duplicates;
    }

    // Duplicate detection is intentionally GLOBAL across the full IR
    // database. A Logitech Mute signal learned under a temporary test device
    // must still be detected as matching Z5500 5.1 Audio / Mute.
    for (const auto& deviceEntry :
         std::filesystem::directory_iterator(root, error))
    {
        if (error)
        {
            break;
        }

        if (!deviceEntry.is_directory(error))
        {
            continue;
        }

        const std::string existingDevice =
            deviceEntry.path().filename().string();

        std::error_code commandError;

        for (const auto& commandEntry :
             std::filesystem::directory_iterator(
                 deviceEntry.path(),
                 commandError))
        {
            if (commandError)
            {
                break;
            }

            if (!commandEntry.is_regular_file(commandError) ||
                commandEntry.path().extension() != ".ir")
            {
                continue;
            }

            const std::string existingCommand =
                commandEntry.path().stem().string();

            // Never report the command currently being replaced as a
            // duplicate of itself.
            if (existingDevice == deviceName &&
                existingCommand == commandName)
            {
                continue;
            }

            IRCode existing;

            if (!database.load(
                    existingDevice,
                    existingCommand,
                    existing))
            {
                continue;
            }

            if (existing.decodedProtocol ==
                    candidate.decodedProtocol &&
                existing.address == candidate.address &&
                existing.decodedCommand ==
                    candidate.decodedCommand)
            {
                duplicates.push_back(
                    existingDevice +
                    " / " +
                    existingCommand);
            }
        }
    }

    std::sort(
        duplicates.begin(),
        duplicates.end());

    duplicates.erase(
        std::unique(
            duplicates.begin(),
            duplicates.end()),
        duplicates.end());

    return duplicates;
}


unsigned int existingDeviceCarrierKhz(
    IRDatabase& database,
    const std::string& deviceName)
{
    const std::filesystem::path directory =
        std::filesystem::path("data") /
        "ir" /
        "devices" /
        deviceName;

    std::error_code error;
    if (!std::filesystem::is_directory(directory, error))
    {
        return 0;
    }

    std::map<unsigned int, std::size_t> counts;

    for (const auto& entry :
         std::filesystem::directory_iterator(directory, error))
    {
        if (error)
        {
            break;
        }

        if (!entry.is_regular_file(error) ||
            entry.path().extension() != ".ir")
        {
            continue;
        }

        IRCode code;

        if (database.load(
                deviceName,
                entry.path().stem().string(),
                code) &&
            code.carrierKhz > 0)
        {
            ++counts[code.carrierKhz];
        }
    }

    if (counts.empty())
    {
        return 0;
    }

    return std::max_element(
        counts.begin(),
        counts.end(),
        [](const auto& left, const auto& right)
        {
            return left.second < right.second;
        })->first;
}

bool updateLogicalCommand(
    const std::string& deviceName,
    const std::string& commandName,
    const std::string& description,
    std::string& error)
{
    DeviceDatabase database;
    Device device;

    if (!database.deviceExists(deviceName))
    {
        error =
            "Logical device does not exist: " +
            deviceName;
        return false;
    }

    if (!database.loadDevice(deviceName, device))
    {
        error =
            "Could not load logical device: " +
            deviceName;
        return false;
    }

    for (DeviceCommand& command : device.commands)
    {
        if (command.id != commandName)
        {
            continue;
        }

        command.name = commandName;
        command.description = description;
        command.transport = TransportType::IR;
        command.transportDevice = deviceName;
        command.transportCommand = commandName;

        if (command.transmitter.empty())
        {
            command.transmitter =
                device.transmitter.empty()
                    ? kDefaultTransmitter
                    : device.transmitter;
        }

        command.enabled = true;

        if (!database.saveDevice(device))
        {
            error =
                "Could not update logical device command.";
            return false;
        }

        error.clear();
        return true;
    }

    DeviceCommand command;
    command.id = commandName;
    command.name = commandName;
    command.description = description;
    command.transport = TransportType::IR;
    command.transportDevice = deviceName;
    command.transportCommand = commandName;
    command.transmitter =
        device.transmitter.empty()
            ? kDefaultTransmitter
            : device.transmitter;
    command.enabled = true;

    device.commands.push_back(command);

    if (!database.saveDevice(device))
    {
        error =
            "Could not add logical device command.";
        return false;
    }

    error.clear();
    return true;
}

bool analyzeCaptureDirectory(
    const std::filesystem::path& directory,
    const std::string& deviceName,
    const std::string& commandName,
    const std::string& description,
    IRLearnResult& result,
    std::string& error)
{
    try
    {
        IRDatabase database;
        const IRAnalyzer analyzer;

        const std::vector<IRReceiverAnalysis> analyses =
            analyzer.analyzeDirectory(directory);

        if (analyses.empty())
        {
            result.failureCode = 2;
            error =
                "No analyzable IR receiver captures were found.";
            return false;
        }

        const IRReceiverAnalysis& best =
            analyses[analyzer.best(analyses)];

        const bool stableDecode =
            best.analysis.decodedCount >= 2 &&
            best.analysis.consistency == 1.0;

        IRCode code;
        code.device = deviceName;
        code.command = commandName;
        code.description = description;
        code.protocol = "raw";
        code.sourceCapture = directory.string();

        if (best.analysis.result() == "CLEAN" ||
            stableDecode)
        {
            const IRRepresentativeFrame frame =
                analyzer.representativeFrame(best.analysis);

            code.decodedProtocol =
                best.analysis.protocol;
            code.address =
                best.analysis.address;
            code.decodedCommand =
                best.analysis.command;
            code.carrierKhz =
                best.nominalCarrierKhz;
            code.receiverGpio =
                best.gpio;
            code.receiverModel =
                best.model;
            code.captureInitialFrames =
                best.analysis.initialFrames;
            code.captureRepeatFrames =
                best.analysis.repeatFrames;
            code.pulses =
                frame.durations;

            result.stablePartialDecode =
                best.analysis.result() != "CLEAN";

            if (result.stablePartialDecode)
            {
                std::ostringstream note;
                note
                    << "Stable partial decode accepted: "
                    << best.analysis.decodedCount
                    << "/"
                    << best.analysis.frameCount
                    << " frames decoded and all valid decodes agree.";
                result.note = note.str();
            }
        }
        else
        {
            const unsigned int knownCarrier =
                existingDeviceCarrierKhz(
                    database,
                    deviceName);

            if (knownCarrier == 0)
            {
                result.failureCode = 2;
                error =
                    "No stable supported protocol was found, and this "
                    "device has no previous learned carrier for safe RAW "
                    "fallback. The capture was retained for analysis.";
                return false;
            }

            const auto receiver =
                std::find_if(
                    analyses.begin(),
                    analyses.end(),
                    [knownCarrier](
                        const IRReceiverAnalysis& item)
                    {
                        return
                            item.nominalCarrierKhz ==
                            knownCarrier;
                    });

            if (receiver == analyses.end() ||
                receiver->analysis.frameCount < 2)
            {
                result.failureCode = 2;

                std::ostringstream message;
                message
                    << "No stable supported protocol was found. "
                    << "The known device carrier is "
                    << knownCarrier
                    << " kHz, but that receiver did not capture "
                    << "at least two frames. The capture was retained.";

                error = message.str();
                return false;
            }

            const IRRawRepresentativeFrame raw =
                analyzer.rawRepresentativeFrame(
                    receiver->analysis);

            const std::size_t minimumMatches =
                std::max<std::size_t>(
                    2,
                    (raw.frameCount + 1) / 2);

            if (raw.matchingFrames < minimumMatches)
            {
                result.failureCode = 2;

                std::ostringstream message;
                message
                    << "RAW frames at "
                    << knownCarrier
                    << " kHz were not consistent enough ("
                    << raw.matchingFrames
                    << "/"
                    << raw.frameCount
                    << " matched). The capture was retained.";

                error = message.str();
                return false;
            }

            code.carrierKhz =
                knownCarrier;
            code.receiverGpio =
                receiver->gpio;
            code.receiverModel =
                receiver->model;
            code.captureInitialFrames =
                receiver->analysis.initialFrames;
            code.captureRepeatFrames =
                receiver->analysis.repeatFrames;
            code.pulses =
                raw.durations;

            result.rawFallback = true;

            std::ostringstream note;
            note
                << "Stable undecoded RAW timing accepted at "
                << knownCarrier
                << " kHz ("
                << raw.matchingFrames
                << "/"
                << raw.frameCount
                << " matching frames).";
            result.note = note.str();
        }

        for (const IRReceiverAnalysis& receiver :
             analyses)
        {
            IRAnalysisRow row;
            row.gpio = receiver.gpio;
            row.receiverModel = receiver.model;
            row.nominalCarrierKhz =
                receiver.nominalCarrierKhz;
            row.frameCount =
                receiver.analysis.frameCount;
            row.validFrameCount =
                receiver.analysis.decodedCount;
            row.result =
                receiver.analysis.result();
            row.decodedProtocol =
                receiver.analysis.protocol;
            row.address =
                receiver.analysis.address;
            row.decodedCommand =
                receiver.analysis.command;

            code.analysis.push_back(row);
        }

        result.code = code;
        result.duplicates =
            findDuplicateCommands(
                database,
                deviceName,
                commandName,
                code);
        result.failureCode = 0;

        error.clear();
        return true;
    }
    catch (const std::exception& exception)
    {
        result.failureCode = 1;
        error =
            std::string(
                "IR learning analysis failed: ") +
            exception.what();
        return false;
    }
}

} // namespace

bool IRLearningService::createDevice(
    const std::string& manufacturer,
    const std::string& remoteName,
    const std::string& deviceName,
    const std::string& location,
    const std::string& transmitter,
    Device& created,
    std::string& error) const
{
    if (!validDatabaseName(deviceName))
    {
        error =
            "Device name cannot be empty, '.', '..', "
            "or contain slashes.";
        return false;
    }

    if (hasLineBreak(manufacturer) ||
        hasLineBreak(remoteName) ||
        hasLineBreak(deviceName) ||
        hasLineBreak(location))
    {
        error =
            "IR device fields may not contain line breaks.";
        return false;
    }

    const std::string selectedTransmitter =
        transmitter.empty()
            ? kDefaultTransmitter
            : transmitter;

    if (!validTransmitter(selectedTransmitter))
    {
        error =
            "Transmitter must be Tower-IR-TX-001 through "
            "Tower-IR-TX-006.";
        return false;
    }

    DeviceDatabase database;

    if (database.deviceExists(deviceName))
    {
        error =
            "A Tower device with that name already exists.";
        return false;
    }

    Device device;
    device.id = deviceName;
    device.name = deviceName;
    device.type = "IR Device";
    device.manufacturer = manufacturer;
    device.remoteName = remoteName;
    device.location = location;
    device.transmitter = selectedTransmitter;
    device.enabled = true;

    if (!database.saveDevice(device))
    {
        error =
            "Could not save the new IR device profile.";
        return false;
    }

    created = device;
    error.clear();
    return true;
}

bool IRLearningService::captureAndAnalyze(
    const std::string& deviceName,
    const std::string& commandName,
    const std::string& description,
    double seconds,
    bool force,
    IRLearnResult& result,
    std::string& error) const
{
    result = {};
    result.deviceName = deviceName;
    result.commandName = commandName;
    result.description = description;

    if (!validDatabaseName(deviceName) ||
        !validDatabaseName(commandName))
    {
        error =
            "Device and command names cannot be empty, '.', '..', "
            "or contain slashes.";
        return false;
    }

    if (hasLineBreak(description))
    {
        error =
            "Command description may not contain line breaks.";
        return false;
    }

    if (seconds <= 0.0 || seconds > 300.0)
    {
        error =
            "Capture duration must be greater than 0 and no more "
            "than 300 seconds.";
        return false;
    }

    DeviceDatabase deviceDatabase;
    if (!deviceDatabase.deviceExists(deviceName))
    {
        error =
            "Logical device does not exist: " +
            deviceName;
        return false;
    }

    IRDatabase database;
    if (database.exists(deviceName, commandName) &&
        !force)
    {
        error =
            "IR command already exists. Use force only when "
            "deliberately replacing it.";
        return false;
    }

    const IRReceiverArray array;
    const std::vector<IRReceiverStatus> receivers =
        array.discover();

    if (!array.allAvailable())
    {
        error =
            "All six IR receivers must be available. "
            "Run 'tower ir-receivers' for details.";
        return false;
    }

    std::filesystem::path destination;

    try
    {
        destination =
            std::filesystem::path("captures") /
            "ir" /
            (
                utcTimestamp() +
                "_" +
                safeName(deviceName) +
                "_" +
                safeName(commandName)
            );
    }
    catch (const std::exception& exception)
    {
        error = exception.what();
        return false;
    }

    result.captureId =
        destination.filename().string();
    result.capturePath =
        destination.string();

    std::vector<IRArrayCaptureResult> captures;

    try
    {
        captures =
            IRArrayCapture().capture(
                receivers,
                destination,
                seconds);
    }
    catch (const std::exception& exception)
    {
        error =
            std::string("Capture failed: ") +
            exception.what();
        return false;
    }

    bool anySignal = false;

    result.receiverStats.clear();

    for (const IRArrayCaptureResult& capture :
         captures)
    {
        anySignal =
            anySignal ||
            capture.pulseCount > 0;

        IRReceiverCaptureStat stat;
        stat.gpio =
            static_cast<unsigned int>(
                capture.receiver.receiver.gpio);
        stat.receiverModel =
            capture.receiver.receiver.model;
        stat.nominalCarrierKhz =
            static_cast<unsigned int>(
                capture.receiver.receiver.nominalCarrierKhz);
        stat.timingCount =
            capture.timingCount;
        stat.pulseCount =
            capture.pulseCount;

        result.receiverStats.push_back(stat);

        if (irCaptureDiagnosticHasError(
                capture.diagnostic))
        {
            error =
                "Capture error on " +
                capture.receiver.lircDevice +
                ": " +
                capture.diagnostic;
            return false;
        }
    }

    if (!anySignal)
    {
        result.failureCode = 2;
        error =
            "No IR signal was captured. "
            "The capture was retained, but nothing was saved.";
        return false;
    }

    const bool analyzed =
        analyzeCaptureDirectory(
            destination,
            deviceName,
            commandName,
            description,
            result,
            error);

    if (analyzed)
    {
        for (IRReceiverCaptureStat& stat :
             result.receiverStats)
        {
            const auto row =
                std::find_if(
                    result.code.analysis.begin(),
                    result.code.analysis.end(),
                    [&stat](const IRAnalysisRow& candidate)
                    {
                        return candidate.gpio == stat.gpio;
                    });

            if (row == result.code.analysis.end())
            {
                continue;
            }

            stat.frameCount =
                row->frameCount;
            stat.validFrameCount =
                row->validFrameCount;
            stat.result =
                row->result;
        }
    }

    return analyzed;
}

bool IRLearningService::analyzeExistingCapture(
    const std::string& captureId,
    const std::string& deviceName,
    const std::string& commandName,
    const std::string& description,
    IRLearnResult& result,
    std::string& error) const
{
    result = {};
    result.captureId = captureId;
    result.deviceName = deviceName;
    result.commandName = commandName;
    result.description = description;

    if (!validDatabaseName(captureId) ||
        !validDatabaseName(deviceName) ||
        !validDatabaseName(commandName))
    {
        error =
            "Invalid capture, device, or command identifier.";
        return false;
    }

    const std::filesystem::path directory =
        std::filesystem::path("captures") /
        "ir" /
        captureId;

    if (!std::filesystem::is_directory(directory))
    {
        error =
            "IR capture directory was not found.";
        return false;
    }

    result.capturePath = directory.string();

    return analyzeCaptureDirectory(
        directory,
        deviceName,
        commandName,
        description,
        result,
        error);
}

bool IRLearningService::saveResult(
    const IRLearnResult& result,
    bool force,
    bool acceptDuplicate,
    std::string& error) const
{
    if (result.failureCode != 0 ||
        result.code.pulses.empty())
    {
        error =
            "The IR capture is not in a savable state.";
        return false;
    }

    if (!result.duplicates.empty() &&
        !acceptDuplicate)
    {
        error =
            "This decoded IR signal is already stored under "
            "another command name.";
        return false;
    }

    IRDatabase database;

    if (database.exists(
            result.deviceName,
            result.commandName) &&
        !force)
    {
        error =
            "IR command already exists and replacement was "
            "not authorized.";
        return false;
    }

    if (database.exists(
            result.deviceName,
            result.commandName))
    {
        std::filesystem::path backup =
            database.path(
                result.deviceName,
                result.commandName);

        backup += ".tower-learn-backup";

        std::error_code copyError;
        std::filesystem::copy_file(
            database.path(
                result.deviceName,
                result.commandName),
            backup,
            std::filesystem::copy_options::overwrite_existing,
            copyError);

        if (copyError)
        {
            error =
                "Could not back up existing command: " +
                copyError.message();
            return false;
        }
    }

    if (!database.save(
            result.deviceName,
            result.commandName,
            result.code))
    {
        error =
            "Could not save the IR command file.";
        return false;
    }

    if (!updateLogicalCommand(
            result.deviceName,
            result.commandName,
            result.description,
            error))
    {
        return false;
    }

    error.clear();
    return true;
}
