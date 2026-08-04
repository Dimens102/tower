#include "core/service/TowerService.h"

#include "core/logging/Logger.h"
#include "devices/remote/TemperatureSensor.h"
#include "devices/remote/controllers/pico_controller.h"
#include "version.h"
#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>

#include <algorithm>
#include <chrono>
#include <csignal>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iterator>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <thread>

namespace
{

volatile std::sig_atomic_t keepRunning = 1;
constexpr std::chrono::seconds bootPhaseDuration{5};

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

std::string readPiModel()
{
    std::ifstream input(
        "/proc/device-tree/model",
        std::ios::binary);

    if (!input)
    {
        return "Raspberry Pi";
    }

    std::string model(
        (std::istreambuf_iterator<char>(input)),
        std::istreambuf_iterator<char>());

    model.erase(
        std::remove(
            model.begin(),
            model.end(),
            '\0'),
        model.end());

    if (model.empty())
    {
        return "Raspberry Pi";
    }

    return "Raspberry PI 3 A+";
}

std::string readCpuTemperature()
{
    std::ifstream input(
        "/sys/class/thermal/thermal_zone0/temp");

    long millidegrees = 0;

    if (!(input >> millidegrees))
    {
        return "[cpu] temperature --";
    }

    std::ostringstream output;

    output
        << "[cpu] "
        << std::fixed
        << std::setprecision(1)
        << static_cast<double>(millidegrees) / 1000.0
        << "C";

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

    apiServer_.setSensorProvider(
        [this]()
        {
            return sensorSnapshots();
        });
}

bool TowerService::start()
{
    serviceLockFd_ =
        ::open(
            "/tmp/rf-tower-service.lock",
            O_CREAT | O_RDWR,
            0644);

    if (serviceLockFd_ < 0)
    {
        Logger::warning(
            "TowerService",
            "Failed to open service lock file");

        return false;
    }

    if (::flock(
            serviceLockFd_,
            LOCK_EX | LOCK_NB) != 0)
    {
        ::close(serviceLockFd_);
        serviceLockFd_ = -1;

        Logger::warning(
            "TowerService",
            "Tower service is already running; refusing to start another instance");

        return false;
    }
	
	keepRunning = 1;

    std::signal(SIGINT, handleSignal);
    std::signal(SIGTERM, handleSignal);

    Logger::info(
        "TowerService",
        "Tower service starting");

    const char* apiToken = std::getenv("TOWER_API_TOKEN");
    if (!apiServer_.start(8080, apiToken == nullptr ? "" : apiToken))
    {
        Logger::warning(
            "TowerService",
            "PC bridge API did not start");
    }

    const bool lcdAvailable =
        lcd_.initialize();

    if (lcdAvailable)
    {
        lcd_.setBacklight(true);
        backlightOn_ = true;

        showBootStatus(
            "[lcd] 0x27 OK",
            "[tower] starting");

        Logger::info(
            "TowerService",
            "LCD1602 initialized at address 0x27");

        std::this_thread::sleep_for(
            bootPhaseDuration);

        showBootStatus(
            readPiModel(),
            readCpuTemperature());

        std::this_thread::sleep_for(
            bootPhaseDuration);

        showBootStatus(
            "[sensor] checking...",
            "[svc] scheduler...");

        std::this_thread::sleep_for(
            bootPhaseDuration);
    }
    else
    {
        Logger::info(
            "TowerService",
            "LCD1602 initialization failed");
    }

    bool devicesReady = false;
    {
        std::lock_guard<std::mutex> lock(sensorMutex_);
        devicesReady = scheduler_.initialize();
    }

    if (!devicesReady)
    {
        Logger::warning(
            "TowerService",
            "One or more managed devices failed to initialize");
    }

    if (lcdAvailable)
    {
        showBootStatus(
            devicesReady
                ? "[sensor] devices OK"
                : "[sensor] device WARN",
            "[svc] scheduler OK");

        std::this_thread::sleep_for(
            bootPhaseDuration);
    }

    if (lcdAvailable)
    {
        showBootStatus(
            "[pico] checking...",
            "192.168.2.30");

        std::this_thread::sleep_for(
            bootPhaseDuration);
    }

    tower::remote::controllers::PicoController pico;
    const bool picoAvailable =
        pico.initialize();

    if (picoAvailable)
    {
        Logger::info(
            "TowerService",
            "Tower Pico connected at " +
                pico.host());
    }
    else
    {
        Logger::warning(
            "TowerService",
            "Tower Pico unavailable at " +
                pico.host());
    }

    if (lcdAvailable)
    {
        showBootStatus(
            picoAvailable
                ? "[pico] connected"
                : "[pico] unavailable",
            pico.host());

        std::this_thread::sleep_for(
            bootPhaseDuration);
    }

    if (lcdAvailable)
    {
        showBootStatus(
            "[gpio] 26 checking",
            "[bias] pull-up");

        std::this_thread::sleep_for(
            bootPhaseDuration);
    }

    if (gpio_.openChip("/dev/gpiochip0") &&
        gpio_.requestInput(
            26,
            GPIOEdge::Both,
            GPIOBias::PullUp))
    {
        buttonAvailable_ = true;

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

    if (lcdAvailable)
    {
        showBootStatus(
            buttonAvailable_
                ? "[gpio] 26 IN OK"
                : "[gpio] 26 WARN",
            "[bias] pull-up");

        std::this_thread::sleep_for(
            bootPhaseDuration);

        lcd_.show(
            std::string("Tower v") +
                TOWER_VERSION +
                " BOOTED",
            "All systems ready",
            "",
            "");

        std::this_thread::sleep_for(
            bootPhaseDuration);

        lcd_.show(
            "",
            std::string("Tower v") +
                TOWER_VERSION,
            "",
            " Created by Dimens");

        bootScreenActive_ = true;
        bootScreenEndsAt_ =
            std::chrono::steady_clock::now() +
            std::chrono::seconds(20);
    }

    return true;
}

void TowerService::update()
{
    {
        std::lock_guard<std::mutex> lock(sensorMutex_);
        scheduler_.update();
    }

    const auto now =
        std::chrono::steady_clock::now();

    if (bootScreenActive_)
    {
        if (now < bootScreenEndsAt_)
        {
            return;
        }

        bootScreenActive_ = false;

        if (buttonAvailable_)
        {
            GPIOEvent ignoredEvent{};

            while (gpio_.waitForEdge(
                26,
                ignoredEvent,
                0))
            {
            }

            buttonReleased_ = true;
            buttonPressArmed_ = true;
            lastButtonEdgeAt_ = {};
        }

        updateDisplay();

        nextDisplayUpdate_ =
            now + std::chrono::seconds(1);

        if (buttonAvailable_)
        {
            lcd_.setBacklight(false);
            backlightOn_ = false;

            Logger::info(
                "TowerService",
                "Boot screen finished; LCD backlight disabled");
        }

        return;
    }

    updateBacklightButton();

    if (now >= nextDisplayUpdate_)
    {
        updateDisplay();

        nextDisplayUpdate_ =
            now + std::chrono::seconds(1);
    }
}

void TowerService::showBootStatus(
    const std::string& status,
    const std::string& detail)
{
    if (!lcd_.available())
    {
        return;
    }

    lcd_.show(
        std::string("Tower v") +
            TOWER_VERSION +
            " BOOT",
        status,
        detail,
        ">> initializing...");
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

    std::lock_guard<std::mutex> lock(sensorMutex_);

    if (roomSensor_ != nullptr)
    {
        const auto& reading = roomSensor_->reading();

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

std::vector<TowerApiSensorSnapshot> TowerService::sensorSnapshots()
{
    std::lock_guard<std::mutex> lock(sensorMutex_);
    std::vector<TowerApiSensorSnapshot> snapshots;

    TowerApiSensorSnapshot room;
    room.id = "room-environment";
    room.name = "Room Environment";

    if (roomSensor_ != nullptr)
    {
        const auto& reading = roomSensor_->reading();
        room.available = roomSensor_->available() && reading.valid;

        if (room.available)
        {
            room.ageSeconds = std::chrono::duration_cast<std::chrono::seconds>(
                std::chrono::steady_clock::now() - reading.timestamp).count();

            for (const auto& measurement : reading.measurements)
            {
                room.measurements.push_back({
                    measurement.name,
                    measurement.unit,
                    measurement.value});
            }
        }
    }
    snapshots.push_back(std::move(room));

    TowerApiSensorSnapshot aquarium;
    aquarium.id = "aquarium-temperature";
    aquarium.name = "Aquarium";

    if (aquariumSensor_ != nullptr && aquariumSensor_->latestReading())
    {
        const auto& reading = *aquariumSensor_->latestReading();
        aquarium.available = true;
        aquarium.ageSeconds = std::chrono::duration_cast<std::chrono::seconds>(
            std::chrono::system_clock::now() - reading.timestamp).count();

        const std::time_t timestamp =
            std::chrono::system_clock::to_time_t(reading.timestamp);
        std::tm utc{};
        gmtime_r(&timestamp, &utc);
        std::ostringstream formattedTimestamp;
        formattedTimestamp << std::put_time(&utc, "%Y-%m-%dT%H:%M:%SZ");
        aquarium.timestampUtc = formattedTimestamp.str();

        aquarium.measurements.push_back({
            "Temperature",
            "C",
            reading.temperatureCelsius});
    }
    snapshots.push_back(std::move(aquarium));

    return snapshots;
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
        [this, doublePressNs](
            unsigned long long timestampNs)
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
                std::chrono::nanoseconds(
                    event.timestampNs));

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
                std::chrono::nanoseconds(
                    releaseDebounceNs);

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
    apiServer_.stop();
    Logger::info(
        "TowerService",
        "Tower service stopping");
}
