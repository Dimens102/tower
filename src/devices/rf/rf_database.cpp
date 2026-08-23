#include "devices/rf/rf_database.h"

#include <fstream>
#include <iostream>
#include <sstream>
#include <algorithm>
#include <filesystem>
#include <vector>

static void applyKeyValue(RFDevice& device, const std::string& key, const std::string& value)
{
    if (key == "name") device.name = value;
    else if (key == "protocol") device.protocol = value;
    else if (key == "description") device.description = value;
    else if (key == "house") device.house = value;
    else if (key == "unit") device.unit = std::stoi(value);
    else if (key == "gpio") device.gpio = std::stoi(value);
    else if (key == "pulse") device.pulse = std::stoi(value);
    else if (key == "repeat") device.repeat = std::stoi(value);
    else if (key == "on") device.onCode = std::stoul(value);
    else if (key == "off") device.offCode = std::stoul(value);
    else if (key == "transmitter_id") device.transmitterId = value;
    else if (key == "status") device.status = value;
    else if (key == "device_name") device.deviceName = value;
}

bool RFDatabase::loadPowerDevice(const std::string& name, RFDevice& device)
{
    std::string path = "data/rf/power/" + name + ".rf";
    std::ifstream file(path);

    if (!file)
    {
        std::cerr << "Failed to open RF device file: " << path << "\n";
        return false;
    }

    std::string line;

    while (std::getline(file, line))
    {
        if (line.empty()) continue;

        std::size_t pos = line.find('=');

        if (pos == std::string::npos) continue;

        std::string key = line.substr(0, pos);
        std::string value = line.substr(pos + 1);

        applyKeyValue(device, key, value);
    }

    return true;
}

std::vector<RFDevice> RFDatabase::listPowerDevices()
{
    std::vector<RFDevice> devices;
    const std::filesystem::path directory = "data/rf/power";

    if (!std::filesystem::exists(directory))
    {
        return devices;
    }

    for (const auto& entry : std::filesystem::directory_iterator(directory))
    {
        if (!entry.is_regular_file() || entry.path().extension() != ".rf")
        {
            continue;
        }

        RFDevice device;
        if (loadPowerDevice(entry.path().stem().string(), device))
        {
            devices.push_back(std::move(device));
        }
    }

    std::sort(
        devices.begin(),
        devices.end(),
        [](const RFDevice& left, const RFDevice& right)
        {
            return left.name < right.name;
        });

    return devices;
}


namespace
{

bool isSafeRfRecordName(const std::string& name)
{
    if (name.empty() || name == "." || name == "..")
    {
        return false;
    }

    const std::filesystem::path supplied(name);

    return
        supplied.filename().string() == name &&
        name.find('/') == std::string::npos &&
        name.find('\\') == std::string::npos;
}

bool hasLineBreak(const std::string& value)
{
    return
        value.find('\r') != std::string::npos ||
        value.find('\n') != std::string::npos;
}

} // namespace

bool RFDatabase::savePowerDevice(
    const RFDevice& device,
    bool overwrite)
{
    if (!isSafeRfRecordName(device.name) ||
        device.protocol.empty() ||
        hasLineBreak(device.description) ||
        hasLineBreak(device.deviceName) ||
        hasLineBreak(device.transmitterId) ||
        hasLineBreak(device.status))
    {
        return false;
    }

    const std::filesystem::path directory = "data/rf/power";
    const std::filesystem::path path =
        directory / (device.name + ".rf");
    const std::filesystem::path temporaryPath =
        directory / (device.name + ".rf.tmp");

    std::error_code error;
    std::filesystem::create_directories(directory, error);
    if (error)
    {
        return false;
    }

    error.clear();
    if (!overwrite && std::filesystem::exists(path, error))
    {
        return false;
    }

    std::ofstream file(
        temporaryPath,
        std::ios::out | std::ios::trunc);

    if (!file)
    {
        return false;
    }

    file << "name=" << device.name << "\n";
    file << "protocol=" << device.protocol << "\n";
    file << "description=" << device.description << "\n";

    if (device.protocol == "kaku_ac")
    {
        file << "transmitter_id=" << device.transmitterId << "\n";
        file << "unit=" << device.unit << "\n";
    }
    else if (device.protocol == "kaku_old")
    {
        file << "house=" << device.house << "\n";
        file << "unit=" << device.unit << "\n";
        file << "on=" << device.onCode << "\n";
        file << "off=" << device.offCode << "\n";
    }

    file << "gpio=" << device.gpio << "\n";
    file << "status=" << device.status << "\n";
    file << "pulse=" << device.pulse << "\n";
    file << "repeat=" << device.repeat << "\n";
    file << "device_name=" << device.deviceName << "\n";

    file.flush();

    if (!file.good())
    {
        file.close();
        std::filesystem::remove(temporaryPath, error);
        return false;
    }

    file.close();

    error.clear();
    std::filesystem::rename(
        temporaryPath,
        path,
        error);

    if (error)
    {
        std::filesystem::remove(temporaryPath, error);
        return false;
    }

    return true;
}

bool RFDatabase::updatePowerDeviceStatus(
    const std::string& name,
    const std::string& status)
{
    if (status.empty() || hasLineBreak(status))
    {
        return false;
    }

    RFDevice device;
    if (!loadPowerDevice(name, device))
    {
        return false;
    }

    device.status = status;
    return savePowerDevice(device, true);
}


bool RFDatabase::deletePowerDevice(const std::string& name)
{
    if (!isSafeRfRecordName(name))
    {
        return false;
    }

    const std::filesystem::path path =
        std::filesystem::path("data/rf/power") / (name + ".rf");

    std::error_code error;
    if (!std::filesystem::is_regular_file(path, error) || error)
    {
        return false;
    }

    return std::filesystem::remove(path, error) && !error;
}
