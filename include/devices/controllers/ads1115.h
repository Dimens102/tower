#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

#include "devices/controllers/controller.h"
#include "devices/sensors/sensor_reading.h"

namespace tower::controllers
{

class ADS1115 : public Controller
{
public:
    explicit ADS1115(
        std::string i2cDevice = "/dev/i2c-1",
        std::uint8_t address = 0x48);

    ~ADS1115() override;

    bool initialize() override;
    bool update() override;

    bool available() const override;
    const std::string& name() const override;
    const tower::sensors::SensorReading& reading() const;

    bool readChannel(std::size_t channel, double& voltage);

private:
    bool writeRegister(std::uint8_t reg, std::uint16_t value);
    bool readRegister(std::uint8_t reg, std::uint16_t& value);
    bool startSingleConversion(std::size_t channel);
    bool waitForConversion();

    std::string m_name = "ADS1115";
    std::string m_i2cDevice;
    std::uint8_t m_address;

    int m_fd = -1;
    bool m_available = false;

    tower::sensors::SensorReading m_reading{};
};

} // namespace tower::controllers
