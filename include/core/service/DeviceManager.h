#pragma once

#include "core/service/ManagedDevice.h"

#include <memory>
#include <vector>

class DeviceManager
{
public:
    bool initialize();

    void addDevice(
        std::unique_ptr<ManagedDevice> device);

    void update();

    const std::vector<std::unique_ptr<ManagedDevice>>&
    devices() const;

private:
    std::vector<std::unique_ptr<ManagedDevice>> devices_;
};