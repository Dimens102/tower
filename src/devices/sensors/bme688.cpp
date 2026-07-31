#include "devices/sensors/bme688.h"

#include <chrono>
#include <fcntl.h>
#include <linux/i2c-dev.h>
#include <sys/ioctl.h>
#include <thread>
#include <unistd.h>
#include <utility>
#include <vector>

namespace tower::sensors
{

BME688::BME688(std::string i2cDevice, std::uint8_t address)
    : m_i2cDevice(std::move(i2cDevice)),
      m_address(address)
{
}

BME688::~BME688()
{
    if (m_fd >= 0)
    {
        close(m_fd);
    }
}

bool BME688::initialize()
{
    m_available = false;
    m_reading.valid = false;

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

    m_device.intf = BME68X_I2C_INTF;
    m_device.intf_ptr = this;
    m_device.read = readRegisters;
    m_device.write = writeRegisters;
    m_device.delay_us = delayMicroseconds;
    m_device.amb_temp = 25;

    if (bme68x_init(&m_device) != BME68X_OK)
    {
        close(m_fd);
        m_fd = -1;
        return false;
    }

    m_configuration.filter = BME68X_FILTER_OFF;
    m_configuration.odr = BME68X_ODR_NONE;
    m_configuration.os_hum = BME68X_OS_16X;
    m_configuration.os_pres = BME68X_OS_1X;
    m_configuration.os_temp = BME68X_OS_2X;

    if (bme68x_set_conf(&m_configuration, &m_device) != BME68X_OK)
    {
        close(m_fd);
        m_fd = -1;
        return false;
    }

    m_heaterConfiguration.enable = BME68X_ENABLE;
    m_heaterConfiguration.heatr_temp = 300;
    m_heaterConfiguration.heatr_dur = 100;

    if (bme68x_set_heatr_conf(
            BME68X_FORCED_MODE,
            &m_heaterConfiguration,
            &m_device) != BME68X_OK)
    {
        close(m_fd);
        m_fd = -1;
        return false;
    }

    m_nextUpdate_ = std::chrono::steady_clock::now();
    m_available = true;
    return true;
}

bool BME688::update()
{
    if (!m_available || m_fd < 0)
    {
        return false;
    }
	
	const auto now =
    std::chrono::steady_clock::now();

    if (now < m_nextUpdate_)
    {
        return true;
    }

    m_nextUpdate_ =
        now + m_updateInterval_;
		
	m_reading.valid = false;
	m_reading.measurements.clear();

    if (bme68x_set_op_mode(BME68X_FORCED_MODE, &m_device) != BME68X_OK)
    {
        return false;
    }

    const std::uint32_t measurementDuration =
        bme68x_get_meas_dur(
            BME68X_FORCED_MODE,
            &m_configuration,
            &m_device) +
        (static_cast<std::uint32_t>(
             m_heaterConfiguration.heatr_dur) *
         1000U);

    delayMicroseconds(measurementDuration, this);

    bme68x_data data{};
    std::uint8_t fieldCount = 0;

    const std::int8_t result =
        bme68x_get_data(
            BME68X_FORCED_MODE,
            &data,
            &fieldCount,
            &m_device);

    if (result != BME68X_OK)
    {
        return false;
    }

    if (fieldCount == 0)
    {
        return false;
    }

#ifdef BME68X_USE_FPU
    m_reading.measurements.push_back({"Temperature", "C", data.temperature});
    m_reading.measurements.push_back({"Humidity", "%", data.humidity});
    m_reading.measurements.push_back({"Pressure", "hPa", data.pressure / 100.0});
    m_reading.measurements.push_back({"Gas", "ohm", data.gas_resistance});
#else
    m_reading.measurements.push_back({"Temperature", "C", static_cast<double>(data.temperature) / 100.0});
    m_reading.measurements.push_back({"Humidity", "%", static_cast<double>(data.humidity) / 1000.0});
    m_reading.measurements.push_back({"Pressure", "hPa", static_cast<double>(data.pressure) / 100.0});
    m_reading.measurements.push_back({"Gas", "ohm", static_cast<double>(data.gas_resistance)});
#endif

    m_reading.timestamp = std::chrono::steady_clock::now();
    m_reading.valid = true;

    return true;
}

bool BME688::available() const
{
    return m_available;
}

const std::string& BME688::name() const
{
    return m_name;
}

const SensorReading& BME688::reading() const
{
    return m_reading;
}

BME68X_INTF_RET_TYPE BME688::readRegisters(
    std::uint8_t reg,
    std::uint8_t* data,
    std::uint32_t len,
    void* intfPtr)
{
    auto* sensor = static_cast<BME688*>(intfPtr);

    if (sensor == nullptr || sensor->m_fd < 0)
    {
        return BME68X_E_COM_FAIL;
    }

    if (write(sensor->m_fd, &reg, 1) != 1)
    {
        return BME68X_E_COM_FAIL;
    }

    if (read(sensor->m_fd, data, len) !=
        static_cast<ssize_t>(len))
    {
        return BME68X_E_COM_FAIL;
    }

    return BME68X_INTF_RET_SUCCESS;
}

BME68X_INTF_RET_TYPE BME688::writeRegisters(
    std::uint8_t reg,
    const std::uint8_t* data,
    std::uint32_t len,
    void* intfPtr)
{
    auto* sensor = static_cast<BME688*>(intfPtr);

    if (sensor == nullptr || sensor->m_fd < 0)
    {
        return BME68X_E_COM_FAIL;
    }

    std::vector<std::uint8_t> buffer(len + 1);

    buffer[0] = reg;

    for (std::uint32_t index = 0; index < len; ++index)
    {
        buffer[index + 1] = data[index];
    }

    if (write(
            sensor->m_fd,
            buffer.data(),
            buffer.size()) !=
        static_cast<ssize_t>(buffer.size()))
    {
        return BME68X_E_COM_FAIL;
    }

    return BME68X_INTF_RET_SUCCESS;
}

void BME688::delayMicroseconds(
    std::uint32_t period,
    void*)
{
    std::this_thread::sleep_for(
        std::chrono::microseconds(period));
}

} // namespace tower::sensors