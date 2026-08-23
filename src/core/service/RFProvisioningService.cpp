#include "core/service/RFProvisioningService.h"

#include "devices/rf/rf_database.h"

#include <algorithm>
#include <cctype>
#include <iomanip>
#include <sstream>
#include <string>
#include <vector>

namespace
{

constexpr unsigned long kFirstModernAddress = 0x123456UL;
constexpr unsigned long kMaxModernAddress = 0x3FFFFFFUL;
constexpr const char* kModernPrefix = "Tower-RF-Power-M2-";
constexpr const char* kModernDescription =
    "Modern KlikAanKlikUit self-learning receiver";

bool containsLineBreak(const std::string& value)
{
    return
        value.find('\r') != std::string::npos ||
        value.find('\n') != std::string::npos;
}

std::string trim(const std::string& value)
{
    const auto first = std::find_if_not(
        value.begin(),
        value.end(),
        [](unsigned char character)
        {
            return std::isspace(character) != 0;
        });

    const auto last = std::find_if_not(
        value.rbegin(),
        value.rend(),
        [](unsigned char character)
        {
            return std::isspace(character) != 0;
        }).base();

    if (first >= last)
    {
        return {};
    }

    return std::string(first, last);
}

std::string formatAddress(unsigned long value)
{
    std::ostringstream stream;
    stream << "0x"
           << std::uppercase
           << std::hex
           << value;
    return stream.str();
}

bool parseAddress(
    const std::string& input,
    unsigned long& value)
{
    const std::string cleaned = trim(input);
    if (cleaned.empty())
    {
        return false;
    }

    std::size_t consumed = 0;

    try
    {
        value = std::stoul(cleaned, &consumed, 0);
    }
    catch (...)
    {
        return false;
    }

    return
        consumed == cleaned.size() &&
        value <= kMaxModernAddress;
}

int recordSequence(const std::string& name)
{
    if (name.rfind(kModernPrefix, 0) != 0)
    {
        return 0;
    }

    const std::string suffix =
        name.substr(std::string(kModernPrefix).size());

    if (suffix.empty())
    {
        return 0;
    }

    try
    {
        std::size_t consumed = 0;
        const int value = std::stoi(suffix, &consumed, 10);
        return consumed == suffix.size() ? value : 0;
    }
    catch (...)
    {
        return 0;
    }
}

std::string formatRecordName(int sequence)
{
    std::ostringstream stream;
    stream << kModernPrefix
           << std::setw(3)
           << std::setfill('0')
           << sequence;
    return stream.str();
}

} // namespace

bool RFProvisioningService::normalizeTransmitterId(
    const std::string& input,
    std::string& normalized,
    std::string& error)
{
    unsigned long value = 0;
    if (!parseAddress(input, value))
    {
        error =
            "Transmitter ID must be a valid 26-bit number. "
            "Use hexadecimal notation such as 0x12345A.";
        return false;
    }

    normalized = formatAddress(value);
    error.clear();
    return true;
}

bool RFProvisioningService::getNextModernDefaults(
    RFModernDefaults& defaults,
    std::string& error) const
{
    RFDatabase database;
    const std::vector<RFDevice> devices =
        database.listPowerDevices();

    int highestSequence = 0;
    unsigned long highestAddress =
        kFirstModernAddress - 1;

    for (const RFDevice& device : devices)
    {
        highestSequence =
            std::max(
                highestSequence,
                recordSequence(device.name));

        if (device.protocol != "kaku_ac")
        {
            continue;
        }

        unsigned long address = 0;
        if (parseAddress(device.transmitterId, address))
        {
            highestAddress =
                std::max(highestAddress, address);
        }
    }

    if (highestAddress >= kMaxModernAddress)
    {
        error =
            "No free modern KAKU transmitter ID remains "
            "inside the supported 26-bit range.";
        return false;
    }

    defaults = {};
    defaults.recordName =
        formatRecordName(highestSequence + 1);
    defaults.transmitterId =
        formatAddress(highestAddress + 1);
    defaults.description =
        kModernDescription;
    defaults.unit = 1;
    defaults.gpio = 24;
    defaults.pulse = 260;
    defaults.repeat = 16;

    error.clear();
    return true;
}

bool RFProvisioningService::createModernPowerDevice(
    const std::string& deviceName,
    const std::string& description,
    const std::string& transmitterId,
    int unit,
    RFDevice& created,
    std::string& error) const
{
    const std::string cleanedName = trim(deviceName);
    const std::string cleanedDescription = trim(description);

    if (cleanedName.empty())
    {
        error = "Device name is required.";
        return false;
    }

    if (containsLineBreak(cleanedName) ||
        containsLineBreak(cleanedDescription))
    {
        error =
            "Device name and description may not contain line breaks.";
        return false;
    }

    if (unit < 0 || unit > 15)
    {
        error = "Modern KAKU unit must be between 0 and 15.";
        return false;
    }

    RFModernDefaults defaults;
    if (!getNextModernDefaults(defaults, error))
    {
        return false;
    }

    std::string normalizedId;
    if (!normalizeTransmitterId(
            transmitterId.empty()
                ? defaults.transmitterId
                : transmitterId,
            normalizedId,
            error))
    {
        return false;
    }

    unsigned long requestedAddress = 0;
    if (!parseAddress(normalizedId, requestedAddress))
    {
        error = "Could not parse the transmitter ID.";
        return false;
    }

    RFDatabase database;
    for (const RFDevice& existing :
         database.listPowerDevices())
    {
        if (existing.protocol != "kaku_ac")
        {
            continue;
        }

        unsigned long existingAddress = 0;
        if (parseAddress(
                existing.transmitterId,
                existingAddress) &&
            existingAddress == requestedAddress &&
            existing.unit == unit)
        {
            error =
                "That modern KAKU transmitter ID + unit is already in use.";
            return false;
        }
    }

    RFDevice device;
    device.name = defaults.recordName;
    device.protocol = "kaku_ac";
    device.description =
        cleanedDescription.empty()
            ? defaults.description
            : cleanedDescription;
    device.transmitterId = normalizedId;
    device.unit = unit;
    device.gpio = defaults.gpio;
    device.status = "unpaired";
    device.pulse = defaults.pulse;
    device.repeat = defaults.repeat;
    device.deviceName = cleanedName;

    if (!database.savePowerDevice(device, false))
    {
        error =
            "Failed to create RF power definition " +
            device.name + ".rf";
        return false;
    }

    created = device;
    error.clear();
    return true;
}

bool RFProvisioningService::setPairingStatus(
    const std::string& recordName,
    bool paired,
    std::string& error) const
{
    RFDatabase database;

    RFDevice existing;
    if (!database.loadPowerDevice(recordName, existing))
    {
        error = "RF power device not found.";
        return false;
    }

    if (existing.protocol != "kaku_ac")
    {
        error =
            "Pairing status can only be changed by this wizard "
            "for modern KAKU devices.";
        return false;
    }

    if (!database.updatePowerDeviceStatus(
            recordName,
            paired ? "paired" : "unpaired"))
    {
        error = "Failed to update RF pairing status.";
        return false;
    }

    error.clear();
    return true;
}
