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

struct GPIORequest
{
    gpiod_line_request* handle;
    GPIOEdge edge;
    bool isOutput;
};

struct GPIOEvent
{
    int line;
    GPIOEdge edge;
    unsigned long long timestampNs;
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
    bool waitForEdge(int line, GPIOEvent& event, int timeoutMs);
    bool write(int line, bool value);

private:
    gpiod_chip* chip;
    std::map<int, GPIORequest> requests;
};
