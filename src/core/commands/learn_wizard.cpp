#include "core/commands/command_handlers.h"
#include "core/commands/ir_learning.h"

#include "devices/ir/ir_database.h"
#include "devices/device.h"
#include "devices/device_database.h"

#include <cctype>
#include <filesystem>
#include <iostream>
#include <string>

namespace
{
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
} // namespace

int runLearnWizard()
{
    std::cout
        << "IR device recording wizard\n\n"
        << "Every button is captured through all six IR receivers.\n"
        << "Leave the command name empty when this device is complete.\n\n";

    std::string manufacturer;
    std::cout << "Manufacturer: ";
    if (!std::getline(std::cin, manufacturer)) return 1;
    manufacturer = trim(manufacturer);

    std::string remoteName;
    std::cout << "Remote name: ";
    if (!std::getline(std::cin, remoteName)) return 1;
    remoteName = trim(remoteName);

    std::string deviceName;
    while (!validName(deviceName))
    {
        std::cout << "Device name: ";
        if (!std::getline(std::cin, deviceName)) return 1;
        deviceName = trim(deviceName);
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

    std::cout
        << "\nUse transmitter 001 until the completed IR array hardware is "
           "installed and verified.\n"
        << "Enter 001-006 or a full Tower-IR-TX name.\n";

    while (true)
    {
        const std::string requested = promptValue(
            "Transmitter",
            device.transmitter,
            "Tower-IR-TX-001");
        if (!std::cin) return 1;

        const std::string normalized = normalizeTransmitter(requested);
        if (!normalized.empty())
        {
            device.transmitter = normalized;
            break;
        }

        std::cout << "Choose transmitter 001 through 006.\n";
    }

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

    return 0;
}
