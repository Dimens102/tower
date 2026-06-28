#pragma once

#include <cstdint>
#include <string>

enum class GPIODirection
{
    Input,
    Output
};

enum class GPIOEdge
{
    None,
    Rising,
    Falling,
    Both
};

class GPIO
{
public:
    GPIO();
    ~GPIO();

    bool openChip(const std::string& chipName);
    void closeChip();

    bool requestInput(int line, GPIOEdge edge = GPIOEdge::None);
    bool requestOutput(int line, bool initialValue = false);

    bool read(int line) const;
    bool write(int line, bool value);

private:
    void* chip;
};
