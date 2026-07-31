#include "core/service/TowerService.h"

#include "devices/remote/TemperatureSensor.h"
#include "core/logging/Logger.h"

#include <chrono>
#include <csignal>
#include <memory>
#include <thread>

#include <iomanip>
#include <optional>
#include <sstream>
#include <string>

namespace
{

volatile std::sig_atomic_t keepRunning = 1;

void handleSignal(int)
{
    keepRunning = 0;
}

std::optional<double> findMeasurement(
    const tower::sensors::SensorReading& reading,
    const std::string& name)
{
    if (!reading.valid)
    {
        return std::nullopt;
    }

    for (const auto& measurement : reading.measurements)
    {
        if (measurement.name == name)
        {
            return measurement.value;
        }
    }

    return std::nullopt;
}

std::string formatValue(
    const std::optional<double>& value,
    int precision,
    const std::string& suffix,
    const std::string& placeholder)
{
    if (!value)
    {
        return placeholder;
    }

    std::ostringstream output;

    output
        << std::fixed
        << std::setprecision(precision)
        << *value
        << suffix;

    return output.str();
}

} // namespace

TowerService::TowerService()
{
    auto aquariumSensor =
        std::make_unique<TemperatureSensor>(
            "ID1",
            "aquarium",
            "http://192.168.2.26:8765/temperature",
            std::chrono::seconds(30));

    aquariumSensor_ = aquariumSensor.get();

    scheduler_.addDevice(
        std::move(aquariumSensor));

    auto roomSensor =
        std::make_unique<tower::sensors::BME688>(
            "/dev/i2c-1",
            0x76);

    roomSensor_ = roomSensor.get();

    scheduler_.addDevice(
        std::move(roomSensor));
}

bool TowerService::start()
{
    keepRunning = 1;

    std::signal(SIGINT, handleSignal);
    std::signal(SIGTERM, handleSignal);

    Logger::info(
        "TowerService",
        "Tower service starting");

	if (!scheduler_.initialize())
    {
        Logger::warning(
            "TowerService",
            "One or more managed devices failed to initialize");
    }

    if (lcd_.initialize())
    {
        lcd_.show(
            "Room  Tower Aquarium",
            "--.-C Temp     --.-C",
            "--.-% Hum",
            "----  Press");

        Logger::info(
            "TowerService",
            "LCD1602 initialized at address 0x27");
    }
    else
    {
        Logger::info(
            "TowerService",
            "LCD1602 initialization failed");
    }
    
	if (gpio_.openChip("/dev/gpiochip0") &&
    gpio_.requestInput(
        26,
        GPIOEdge::Both,
        GPIOBias::PullUp))
{
    buttonAvailable_ = true;

    lcd_.setBacklight(false);
    backlightOn_ = false;

    Logger::info(
        "TowerService",
        "LCD button initialized on GPIO26");
    }
    else
    {
        Logger::warning(
            "TowerService",
            "Failed to initialize LCD button on GPIO26");
}
	
    return true;
}

void TowerService::update()
{
    scheduler_.update();
	updateBacklightButton();

    const auto now =
        std::chrono::steady_clock::now();

    if (now >= nextDisplayUpdate_)
    {
        updateDisplay();

        nextDisplayUpdate_ =
            now + std::chrono::seconds(1);
    }
}

void TowerService::updateDisplay()
{
    if (!lcd_.available())
    {
        return;
    }

    std::optional<double> roomTemperature;
    std::optional<double> roomHumidity;
    std::optional<double> roomPressure;
    std::optional<double> aquariumTemperature;

    if (roomSensor_ != nullptr)
    {
        const auto& reading =
            roomSensor_->reading();

        roomTemperature =
            findMeasurement(reading, "Temperature");

        roomHumidity =
            findMeasurement(reading, "Humidity");

        roomPressure =
            findMeasurement(reading, "Pressure");
    }

    if (aquariumSensor_ != nullptr &&
        aquariumSensor_->latestReading())
    {
        aquariumTemperature =
            aquariumSensor_
                ->latestReading()
                ->temperatureCelsius;
    }

    const std::string secondLine =
        formatValue(
            roomTemperature,
            1,
            "C",
            "--.-C") +
        " Temp     " +
        formatValue(
            aquariumTemperature,
            1,
            "C",
            "--.-C");

    const std::string thirdLine =
        formatValue(
            roomHumidity,
            1,
            "%",
            "--.-%") +
        " Hum";

    const std::string fourthLine =
        formatValue(
            roomPressure,
            0,
            "",
            "----") +
        "  Press";

    lcd_.show(
        "Room  Tower Aquarium",
        secondLine,
        thirdLine,
        fourthLine);
}

void TowerService::updateBacklightButton()
{
    if (!buttonAvailable_)
    {
        return;
    }

    constexpr unsigned long long releaseDebounceNs =
        75ULL * 1000ULL * 1000ULL;

    constexpr unsigned long long doublePressNs =
        1000ULL * 1000ULL * 1000ULL;

    const auto handlePress =
        [this, doublePressNs](unsigned long long timestampNs)
    {
        const bool isDoublePress =
            waitingForSecondPress_ &&
            timestampNs - firstButtonPressTimestampNs_ <=
                doublePressNs;

        if (isDoublePress)
        {
            waitingForSecondPress_ = false;
            permanentBacklight_ = doublePressTurnsOn_;

            if (permanentBacklight_)
            {
                lcd_.setBacklight(true);
                backlightOn_ = true;

                Logger::info(
                    "TowerService",
                    "LCD backlight locked on");
            }
            else
            {
                lcd_.setBacklight(false);
                backlightOn_ = false;

                Logger::info(
                    "TowerService",
                    "LCD backlight switched off");
            }

            return;
        }

        waitingForSecondPress_ = true;
        firstButtonPressTimestampNs_ = timestampNs;
        doublePressTurnsOn_ = !permanentBacklight_;
        permanentBacklight_ = false;

        lcd_.setBacklight(true);
        backlightOn_ = true;

        backlightOffAt_ =
            std::chrono::steady_clock::now() +
            std::chrono::seconds(30);

        Logger::info(
            "TowerService",
            "LCD backlight enabled for 30 seconds");
    };

    GPIOEvent event{};

    while (gpio_.waitForEdge(26, event, 0))
    {
        const auto eventTime =
            std::chrono::steady_clock::time_point(
                std::chrono::nanoseconds(event.timestampNs));

        if (event.edge == GPIOEdge::Rising)
        {
            buttonReleased_ = true;
            buttonPressArmed_ = true;
            lastButtonEdgeAt_ = eventTime;
            continue;
        }

        const bool releaseWasStable =
            lastButtonEdgeAt_ ==
                std::chrono::steady_clock::time_point{} ||
            eventTime - lastButtonEdgeAt_ >=
                std::chrono::nanoseconds(releaseDebounceNs);

        if (buttonReleased_ &&
            buttonPressArmed_ &&
            releaseWasStable)
        {
            handlePress(event.timestampNs);
        }

        buttonReleased_ = false;
        buttonPressArmed_ = false;
    }

    if (backlightOn_ &&
        !permanentBacklight_ &&
        std::chrono::steady_clock::now() >=
            backlightOffAt_)
    {
        lcd_.setBacklight(false);
        backlightOn_ = false;

        Logger::info(
            "TowerService",
            "LCD backlight disabled");
    }
}

void TowerService::run()
{
    Logger::info(
        "TowerService",
        "Press Ctrl+C to stop");

    while (keepRunning)
    {
        update();

        std::this_thread::sleep_for(
            std::chrono::milliseconds(100));
    }
}

void TowerService::stop()
{
    Logger::info(
        "TowerService",
        "Tower service stopping");
}