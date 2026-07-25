#pragma once

class ManagedDevice
{
public:
    virtual ~ManagedDevice() = default;

    virtual void update() = 0;
};