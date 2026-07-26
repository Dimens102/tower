#pragma once

#include <string>

#include "core/service/ManagedDevice.h"

namespace tower::controllers
{

class Controller : public ManagedDevice
{
public:
    ~Controller() override = default;
};

} // namespace tower::controllers