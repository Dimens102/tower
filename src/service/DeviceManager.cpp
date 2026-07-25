#include "service/DeviceManager.h"

#include <utility>

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