#include "core/service/DeviceManager.h"

#include <utility>

bool DeviceManager::initialize()
{
    bool success = true;

    for (auto& device : devices_)
    {
        if (!device->initialize())
        {
            success = false;
        }
    }

    return success;
}

void DeviceManager::addDevice(
    std::unique_ptr<ManagedDevice> device)
{
    devices_.push_back(std::move(device));
}

void DeviceManager::update()
{
    for (auto& device : devices_)
    {
        device->update();
    }
}

const std::vector<std::unique_ptr<ManagedDevice>>&
DeviceManager::devices() const
{
    return devices_;
}