#include "devices/ir/ir_receiver_array.h"

#include <algorithm>
#include <map>
#include <system_error>

namespace
{
constexpr const char* RECEIVER_PREFIX = "ir-receiver@";

bool gpioFromDeviceName(const std::string& deviceName, int& gpio)
{
    const std::string prefix(RECEIVER_PREFIX);
    if (deviceName.compare(0, prefix.size(), prefix) != 0)
    {
        return false;
    }

    const std::string hexValue = deviceName.substr(prefix.size());
    if (hexValue.empty())
    {
        return false;
    }

    try
    {
        std::size_t parsedCharacters = 0;
        const unsigned long value = std::stoul(hexValue, &parsedCharacters, 16);
        if (parsedCharacters != hexValue.size())
        {
            return false;
        }

        gpio = static_cast<int>(value);
        return true;
    }
    catch (...)
    {
        return false;
    }
}

std::string findLircDevice(const std::filesystem::path& rcPath)
{
    std::error_code error;
    std::vector<std::string> names;

    for (std::filesystem::directory_iterator entry(rcPath, error), end;
         !error && entry != end;
         entry.increment(error))
    {
        const std::string name = entry->path().filename().string();
        if (name.compare(0, 4, "lirc") == 0)
        {
            names.push_back(name);
        }
    }

    if (names.empty())
    {
        return {};
    }

    std::sort(names.begin(), names.end());
    return "/dev/" + names.front();
}

std::map<int, std::string> resolveLircDevices(
    const std::filesystem::path& sysfsRoot)
{
    std::map<int, std::string> devices;
    std::error_code error;

    for (std::filesystem::directory_iterator entry(sysfsRoot, error), end;
         !error && entry != end;
         entry.increment(error))
    {
        const std::string rcName = entry->path().filename().string();
        if (rcName.compare(0, 2, "rc") != 0)
        {
            continue;
        }

        std::error_code canonicalError;
        const std::filesystem::path devicePath =
            std::filesystem::canonical(entry->path() / "device", canonicalError);
        if (canonicalError)
        {
            continue;
        }

        int gpio = -1;
        if (!gpioFromDeviceName(devicePath.filename().string(), gpio))
        {
            continue;
        }

        const std::string lircDevice = findLircDevice(entry->path());
        if (!lircDevice.empty())
        {
            devices[gpio] = lircDevice;
        }
    }

    return devices;
}
} // namespace

const std::vector<IRReceiverDefinition>& IRReceiverArray::definitions()
{
    static const std::vector<IRReceiverDefinition> receivers = {
        {17, "TSOP38230", 30, "West"},
        {18, "TSOP38233", 33, "West"},
        {27, "TSOP34836", 36, "West"},
        {22, "TSOP38238", 38, "South"},
        {23, "TSOP38240", 40, "South"},
        {25, "TSOP38256", 56, "South"},
    };

    return receivers;
}

std::vector<IRReceiverStatus> IRReceiverArray::discover(
    const std::filesystem::path& sysfsRoot) const
{
    const std::map<int, std::string> liveDevices = resolveLircDevices(sysfsRoot);
    std::vector<IRReceiverStatus> statuses;
    statuses.reserve(definitions().size());

    for (const IRReceiverDefinition& receiver : definitions())
    {
        const auto device = liveDevices.find(receiver.gpio);
        statuses.push_back({
            receiver,
            device == liveDevices.end() ? std::string() : device->second,
        });
    }

    return statuses;
}

bool IRReceiverArray::allAvailable(const std::filesystem::path& sysfsRoot) const
{
    const std::vector<IRReceiverStatus> statuses = discover(sysfsRoot);
    return std::all_of(
        statuses.begin(),
        statuses.end(),
        [](const IRReceiverStatus& status)
        {
            return status.available();
        });
}
