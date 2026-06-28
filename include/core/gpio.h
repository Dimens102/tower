#pragma once

#include <map>
#include <string>

struct gpiod_chip;
struct gpiod_line_request;

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

    bool openChip(const std::string& chipPath);
    void closeChip();

    bool requestInput(int line, GPIOEdge edge = GPIOEdge::None);
    bool requestOutput(int line, bool initialValue = false);

    bool read(int line) const;
    bool write(int line, bool value);

private:
    gpiod_chip* chip;
    std::map<int, gpiod_line_request*> requests;
};
