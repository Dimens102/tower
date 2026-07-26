#pragma once

#include <string>

class ManagedDevice
{
public:
    virtual ~ManagedDevice() = default;

    virtual bool initialize() = 0;
    virtual bool update() = 0;

    virtual bool available() const = 0;
    virtual const std::string& name() const = 0;
};