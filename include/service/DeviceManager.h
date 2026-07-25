#pragma once

#include "service/ManagedDevice.h"

#include <memory>
#include <vector>

class DeviceManager
{
public:
    void addDevice(
        std::unique_ptr<ManagedDevice> device);

    void update();

private:
    std::vector<std::unique_ptr<ManagedDevice>> devices_;
};