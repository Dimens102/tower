#include "devices/displays/LCD1602.h"

#include <chrono>
#include <fcntl.h>
#include <linux/i2c-dev.h>
#include <sys/ioctl.h>
#include <thread>
#include <unistd.h>
#include <utility>

namespace tower::displays
{

namespace
{

constexpr std::uint8_t RegisterSelect = 0x01;
constexpr std::uint8_t Enable = 0x04;
constexpr std::uint8_t Backlight = 0x08;

constexpr std::size_t DisplayWidth = 20;

} // namespace

LCD1602::LCD1602(
    std::string i2cDevice,
    std::uint8_t address)
    : i2cDevice_(std::move(i2cDevice)),
      address_(address)
{
}

LCD1602::~LCD1602()
{
    if (fileDescriptor_ >= 0)
    {
        close(fileDescriptor_);
    }
}

bool LCD1602::initialize()
{
    available_ = false;

    if (fileDescriptor_ >= 0)
    {
        close(fileDescriptor_);
        fileDescriptor_ = -1;
    }

    fileDescriptor_ = open(i2cDevice_.c_str(), O_RDWR);

    if (fileDescriptor_ < 0)
    {
        return false;
    }

    if (ioctl(fileDescriptor_, I2C_SLAVE, address_) < 0)
    {
        close(fileDescriptor_);
        fileDescriptor_ = -1;
        return false;
    }

    std::this_thread::sleep_for(
        std::chrono::milliseconds(50));

    if (!writeNibble(0x030, false))
    {
        return false;
    }

    std::this_thread::sleep_for(
        std::chrono::milliseconds(5));

    if (!writeNibble(0x030, false))
    {
        return false;
    }

    std::this_thread::sleep_for(
        std::chrono::microseconds(150));

    if (!writeNibble(0x030, false) ||
        !writeNibble(0x020, false))
    {
        return false;
    }

    // 4-bit mode, two lines, 5x8 character font.
    if (!sendCommand(0x28))
    {
        return false;
    }

    // Display off while configuring.
    if (!sendCommand(0x08))
    {
        return false;
    }

    if (!clear())
    {
        return false;
    }

    // Cursor moves right after each character.
    if (!sendCommand(0x06))
    {
        return false;
    }

    // Display on, cursor off, blinking off.
    if (!sendCommand(0x0C))
    {
        return false;
    }

    available_ = true;
    return true;
}

bool LCD1602::available() const
{
    return available_;
}

bool LCD1602::show(
    const std::string& firstLine,
    const std::string& secondLine,
    const std::string& thirdLine,
    const std::string& fourthLine)
{
    if (!available_)
    {
        return false;
    }

    if (!setCursor(0, 0) ||
        !writeLine(firstLine) ||
        !setCursor(0, 1) ||
        !writeLine(secondLine) ||
        !setCursor(0, 2) ||
        !writeLine(thirdLine) ||
        !setCursor(0, 3) ||
        !writeLine(fourthLine))
    {
        available_ = false;
        return false;
    }

    return true;
}

bool LCD1602::clear()
{
    if (!sendCommand(0x01))
    {
        return false;
    }

    std::this_thread::sleep_for(
        std::chrono::milliseconds(2));

    return true;
}

void LCD1602::setBacklight(bool enabled)
{
    backlightEnabled_ = enabled;

    if (fileDescriptor_ >= 0)
    {
        writeExpander(0x00);
    }
}

bool LCD1602::sendCommand(std::uint8_t command)
{
    return sendByte(command, false);
}

bool LCD1602::sendCharacter(std::uint8_t character)
{
    return sendByte(character, true);
}

bool LCD1602::sendByte(
    std::uint8_t value,
    bool characterMode)
{
    const std::uint8_t upperNibble =
        value & 0xF0;

    const std::uint8_t lowerNibble =
        static_cast<std::uint8_t>((value << 4) & 0xF0);

    return writeNibble(upperNibble, characterMode) &&
           writeNibble(lowerNibble, characterMode);
}

bool LCD1602::writeNibble(
    std::uint8_t nibble,
    bool characterMode)
{
    std::uint8_t value = nibble;

    if (characterMode)
    {
        value |= RegisterSelect;
    }

    if (!writeExpander(value | Enable))
    {
        return false;
    }

    std::this_thread::sleep_for(
        std::chrono::microseconds(1));

    if (!writeExpander(value))
    {
        return false;
    }

    std::this_thread::sleep_for(
        std::chrono::microseconds(50));

    return true;
}

bool LCD1602::writeExpander(std::uint8_t value)
{
    if (fileDescriptor_ < 0)
    {
        return false;
    }

    if (backlightEnabled_)
    {
        value |= Backlight;
    }

    return write(fileDescriptor_, &value, 1) == 1;
}

bool LCD1602::setCursor(
    std::uint8_t column,
    std::uint8_t row)
{
    constexpr std::uint8_t RowAddresses[] =
    {
        0x00,
        0x40,
        0x14,
        0x54
    };

    if (row >= 4 || column >= DisplayWidth)
    {
        return false;
    }

    return sendCommand(
        static_cast<std::uint8_t>(
            0x80 | (RowAddresses[row] + column)));
}

bool LCD1602::writeLine(const std::string& text)
{
    std::string line =
        text.substr(0, DisplayWidth);

    line.resize(DisplayWidth, ' ');

    for (const char character : line)
    {
        if (!sendCharacter(
                static_cast<std::uint8_t>(character)))
        {
            return false;
        }
    }

    return true;
}

} // namespace tower::displays