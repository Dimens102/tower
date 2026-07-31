#pragma once

#include <cstdint>
#include <string>
#include <chrono>

#include "bme68x.h"
#include "devices/sensors/sensor.h"

namespace tower::sensors
{

class BME688 : public Sensor
{
public:
    explicit BME688(
        std::string i2cDevice = "/dev/i2c-1",
        std::uint8_t address = 0x76);

    ~BME688() override;

    bool initialize() override;
    bool update() override;

    bool available() const override;
    const std::string& name() const override;
    const SensorReading& reading() const override;

private:
    static BME68X_INTF_RET_TYPE readRegisters(
        std::uint8_t reg,
        std::uint8_t* data,
        std::uint32_t len,
        void* intfPtr);

    static BME68X_INTF_RET_TYPE writeRegisters(
        std::uint8_t reg,
        const std::uint8_t* data,
        std::uint32_t len,
        void* intfPtr);

    static void delayMicroseconds(
        std::uint32_t period,
        void* intfPtr);

    std::string m_name = "BME688";
    std::string m_i2cDevice;
    std::uint8_t m_address;

    int m_fd = -1;
    bool m_available = false;

    bme68x_dev m_device{};
    bme68x_conf m_configuration{};
    bme68x_heatr_conf m_heaterConfiguration{};
	
	std::chrono::milliseconds m_updateInterval_{5000};
    std::chrono::steady_clock::time_point m_nextUpdate_{};

    SensorReading m_reading{};
};

} // namespace tower::sensors