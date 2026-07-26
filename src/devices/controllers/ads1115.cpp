#include "devices/controllers/ads1115.h"

#include <chrono>
#include <fcntl.h>
#include <linux/i2c-dev.h>
#include <sys/ioctl.h>
#include <thread>
#include <unistd.h>
#include <utility>

namespace tower::controllers
{

namespace
{

constexpr std::uint8_t conversionRegister = 0x00;
constexpr std::uint8_t configurationRegister = 0x01;

constexpr std::uint16_t startConversionBit = 0x8000;
constexpr std::uint16_t singleShotMode = 0x0100;
constexpr std::uint16_t gain4096Millivolts = 0x0200;
constexpr std::uint16_t dataRate860SamplesPerSecond = 0x00E0;
constexpr std::uint16_t disableComparator = 0x0003;

constexpr double voltsPerBit = 4.096 / 32768.0;

} // namespace

ADS1115::ADS1115(std::string i2cDevice, std::uint8_t address)
    : m_i2cDevice(std::move(i2cDevice)),
      m_address(address)
{
}

ADS1115::~ADS1115()
{
    if (m_fd >= 0)
    {
        close(m_fd);
    }
}

bool ADS1115::initialize()
{
    m_available = false;
    m_reading = {};

    if (m_fd >= 0)
    {
        close(m_fd);
        m_fd = -1;
    }

    m_fd = open(m_i2cDevice.c_str(), O_RDWR);

    if (m_fd < 0)
    {
        return false;
    }

    if (ioctl(m_fd, I2C_SLAVE, m_address) < 0)
    {
        close(m_fd);
        m_fd = -1;
        return false;
    }

    std::uint16_t configuration = 0;

    if (!readRegister(configurationRegister, configuration))
    {
        close(m_fd);
        m_fd = -1;
        return false;
    }

    m_available = true;
    return true;
}

bool ADS1115::update()
{
    m_reading = {};

    if (!m_available || m_fd < 0)
    {
        return false;
    }

    bool anyValid = false;

    for (std::size_t channel = 0; channel < 4; ++channel)
    {
        double voltage = 0.0;

        if (readChannel(channel, voltage))
        {
            m_reading.measurements.push_back({
                "AIN" + std::to_string(channel),
                "V",
                voltage
            });

            anyValid = true;
        }
    }

    if (!anyValid)
    {
        return false;
    }

    m_reading.timestamp = std::chrono::steady_clock::now();
    m_reading.valid = true;

    return true;
}

bool ADS1115::available() const
{
    return m_available;
}

const std::string& ADS1115::name() const
{
    return m_name;
}

const tower::sensors::SensorReading& ADS1115::reading() const
{
    return m_reading;
}

bool ADS1115::readChannel(
    std::size_t channel,
    double& voltage)
{
    if (!m_available || m_fd < 0 || channel > 3)
    {
        return false;
    }

    if (!startSingleConversion(channel))
    {
        return false;
    }

    if (!waitForConversion())
    {
        return false;
    }

    std::uint16_t rawValue = 0;

    if (!readRegister(conversionRegister, rawValue))
    {
        return false;
    }

    const auto signedValue =
        static_cast<std::int16_t>(rawValue);

    voltage =
        static_cast<double>(signedValue) *
        voltsPerBit;

    return true;
}

bool ADS1115::writeRegister(
    std::uint8_t reg,
    std::uint16_t value)
{
    const std::uint8_t buffer[] = {
        reg,
        static_cast<std::uint8_t>((value >> 8) & 0xFF),
        static_cast<std::uint8_t>(value & 0xFF)
    };

    return write(m_fd, buffer, sizeof(buffer)) ==
        static_cast<ssize_t>(sizeof(buffer));
}

bool ADS1115::readRegister(
    std::uint8_t reg,
    std::uint16_t& value)
{
    if (write(m_fd, &reg, 1) != 1)
    {
        return false;
    }

    std::uint8_t buffer[2]{};

    if (read(m_fd, buffer, sizeof(buffer)) !=
        static_cast<ssize_t>(sizeof(buffer)))
    {
        return false;
    }

    value =
        (static_cast<std::uint16_t>(buffer[0]) << 8) |
        static_cast<std::uint16_t>(buffer[1]);

    return true;
}

bool ADS1115::startSingleConversion(
    std::size_t channel)
{
    const std::uint16_t mux =
        static_cast<std::uint16_t>(0x04 + channel)
        << 12;

    const std::uint16_t configuration =
        startConversionBit |
        mux |
        gain4096Millivolts |
        singleShotMode |
        dataRate860SamplesPerSecond |
        disableComparator;

    return writeRegister(
        configurationRegister,
        configuration);
}

bool ADS1115::waitForConversion()
{
    constexpr int maximumAttempts = 20;

    for (int attempt = 0;
         attempt < maximumAttempts;
         ++attempt)
    {
        std::uint16_t configuration = 0;

        if (!readRegister(
                configurationRegister,
                configuration))
        {
            return false;
        }

        if ((configuration & startConversionBit) != 0)
        {
            return true;
        }

        std::this_thread::sleep_for(
            std::chrono::microseconds(250));
    }

    return false;
}

} // namespace tower::controllers
