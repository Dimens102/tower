#pragma once

#include <cstdint>
#include <string>

namespace tower::displays
{

class LCD1602
{
public:
    explicit LCD1602(
        std::string i2cDevice = "/dev/i2c-1",
        std::uint8_t address = 0x27);

    ~LCD1602();

    LCD1602(const LCD1602&) = delete;
    LCD1602& operator=(const LCD1602&) = delete;

    bool initialize();
    bool available() const;

    bool show(
        const std::string& firstLine,
        const std::string& secondLine,
        const std::string& thirdLine,
        const std::string& fourthLine);

    bool clear();
    void setBacklight(bool enabled);

private:
    bool sendCommand(std::uint8_t command);
    bool sendCharacter(std::uint8_t character);
    bool sendByte(std::uint8_t value, bool characterMode);
    bool writeNibble(std::uint8_t nibble, bool characterMode);
    bool writeExpander(std::uint8_t value);
    bool setCursor(std::uint8_t column, std::uint8_t row);
    bool writeLine(const std::string& text);

    std::string i2cDevice_;
    std::uint8_t address_;
    int fileDescriptor_ = -1;
    bool available_ = false;
    bool backlightEnabled_ = true;
};

} // namespace tower::displays