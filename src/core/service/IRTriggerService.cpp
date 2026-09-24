#include "core/service/IRTriggerService.h"

#include "core/service/ActionExecutionService.h"
#include "core/service/ExecutionDisplay.h"
#include "devices/ir/ir_code.h"
#include "devices/ir/ir_receiver_array.h"
#include "devices/ir/ir_sender.h"
#include "devices/ir/ir_transmitter.h"
#include "devices/ir/ir_transmitter_database.h"

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <fcntl.h>
#include <linux/lirc.h>
#include <poll.h>
#include <stdexcept>
#include <sys/ioctl.h>
#include <system_error>
#include <unistd.h>

namespace
{
const std::filesystem::path triggerPath =
    std::filesystem::path("data") / "control" / "ir_triggers.json";

constexpr unsigned int towerNecAddress = 0x54;
constexpr std::chrono::milliseconds triggerDebounce{10000};
constexpr std::chrono::seconds teachingDuration{8};
constexpr std::chrono::seconds teachingReceiverGuard{10};

long long steadyMilliseconds()
{
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}

std::vector<unsigned int> necFrame(
    unsigned int address,
    unsigned int command,
    unsigned int repetitions)
{
    std::vector<unsigned int> durations;
    const auto appendFrame = [&]()
    {
        durations.push_back(9000);
        durations.push_back(4500);
        const unsigned int bytes[4] = {
            address & 0xFFU,
            (~address) & 0xFFU,
            command & 0xFFU,
            (~command) & 0xFFU,
        };
        for (const unsigned int byte : bytes)
        {
            for (unsigned int bit = 0; bit < 8; ++bit)
            {
                durations.push_back(562);
                durations.push_back(
                    (byte & (1U << bit)) != 0 ? 1687 : 562);
            }
        }
        durations.push_back(562);
    };

    repetitions = std::max(1U, repetitions);
    for (unsigned int repetition = 0; repetition < repetitions; ++repetition)
    {
        if (repetition > 0)
        {
            durations.push_back(40000);
        }
        appendFrame();
    }
    return durations;
}

bool relativeMatch(
    unsigned int actual,
    unsigned int expected,
    double tolerance)
{
    const double difference =
        std::abs(static_cast<double>(actual) - expected);
    return difference / std::max(1.0, static_cast<double>(expected)) <=
        tolerance;
}

bool decodeNec(
    const std::vector<std::uint32_t>& frame,
    unsigned int& address,
    unsigned int& command)
{
    if (frame.size() != 67 ||
        !relativeMatch(frame[0], 9000, 0.35) ||
        !relativeMatch(frame[1], 4500, 0.35))
    {
        return false;
    }

    unsigned int bytes[4] = {};
    for (unsigned int bitIndex = 0; bitIndex < 32; ++bitIndex)
    {
        const std::size_t pulseIndex = 2 + bitIndex * 2;
        const std::size_t spaceIndex = pulseIndex + 1;
        if (!relativeMatch(frame[pulseIndex], 562, 0.45))
        {
            return false;
        }

        const unsigned int space = frame[spaceIndex];
        unsigned int bit = 0;
        if (relativeMatch(space, 1687, 0.45))
        {
            bit = 1;
        }
        else if (!relativeMatch(space, 562, 0.45))
        {
            return false;
        }
        bytes[bitIndex / 8] |= bit << (bitIndex % 8);
    }

    if (!relativeMatch(frame[66], 562, 0.45) ||
        bytes[1] != (bytes[0] ^ 0xFFU) ||
        bytes[3] != (bytes[2] ^ 0xFFU))
    {
        return false;
    }

    address = bytes[0];
    command = bytes[2];
    return true;
}

void validateAction(const nlohmann::json& action)
{
    if (!action.is_object())
    {
        throw std::runtime_error("Every trigger action must be an object");
    }
    const std::string type = action.value("type", "command");
    if(type=="script") {
        if(action.value("script", "").empty())throw std::runtime_error("Choose a saved script");
    }
    else if(type=="device_power") {
        const auto state=action.value("state", "");
        if(action.value("device", "").empty() || (state!="on" && state!="off" && state!="toggle"))throw std::runtime_error("Invalid device power action");
    }
    else if (type == "rf_preset")
    {
        const int preset = action.value("preset", 0);
        const std::string operation = action.value("action", "");
        if (preset < 1 || preset > 3 ||
            (operation != "on" && operation != "off" &&
             operation != "toggle"))
        {
            throw std::runtime_error(
                "RF preset trigger requires preset 1-3 and on, off, or toggle");
        }
    }
    else if (type == "command")
    {
        if (action.value("device", "").empty() ||
            action.value("command", "").empty())
        {
            throw std::runtime_error(
                "Command trigger requires device and command");
        }
    }
    else if (type == "rf_group")
    {
        const std::string operation = action.value("action", "");
        if (!action.contains("devices") ||
            !action.at("devices").is_array() ||
            action.at("devices").empty() ||
            (operation != "on" && operation != "off" && operation != "toggle"))
        {
            throw std::runtime_error(
                "RF device trigger requires devices and on, off, or toggle");
        }
    }
    else if (type == "voice_path")
    {
        if (!action.contains("path") || !action.at("path").is_array() ||
            action.at("path").empty())
        {
            throw std::runtime_error(
                "Voice trigger requires a command path");
        }
    }
    else
    {
        throw std::runtime_error(
            "Unsupported trigger action type: " + type);
    }
}
}

IRTriggerService::IRTriggerService()
    : document_({{"version", 1}, {"triggers", nlohmann::json::array()}})
{
}

IRTriggerService::~IRTriggerService()
{
    stop();
}

bool IRTriggerService::start(std::string& error)
{
    if (!load(error))
    {
        return false;
    }
    if (running_.exchange(true))
    {
        return true;
    }
    receiverThread_ = std::thread(&IRTriggerService::receiverLoop, this);
    observationThread_ = std::thread(&IRTriggerService::observationLoop, this);
    error.clear();
    return true;
}

void IRTriggerService::stop()
{
    running_ = false;
    if(observationThread_.joinable())observationThread_.join();
    if (receiverThread_.joinable())
    {
        receiverThread_.join();
    }
    std::lock_guard<std::mutex> lock(mutex_);
    receiverStatus_ = "Stopped";
    receiverDevice_.clear();
}

bool IRTriggerService::load(std::string& error)
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (!std::filesystem::exists(triggerPath))
    {
        error.clear();
        return true;
    }
    try
    {
        std::ifstream input(triggerPath);
        input >> document_;
        if (!document_.contains("triggers") ||
            !document_.at("triggers").is_array())
        {
            throw std::runtime_error("triggers must be an array");
        }
        error.clear();
        return true;
    }
    catch (const std::exception& exception)
    {
        error = exception.what();
        return false;
    }
}

bool IRTriggerService::write(std::string& error) const
{
    try
    {
        std::filesystem::create_directories(triggerPath.parent_path());
        const std::filesystem::path temporary =
            triggerPath.string() + ".tmp";
        {
            std::ofstream output(temporary, std::ios::trunc);
            if (!output)
            {
                throw std::runtime_error("Cannot write IR trigger file");
            }
            output << document_.dump(2) << '\n';
        }
        std::error_code filesystemError;
        std::filesystem::rename(temporary, triggerPath, filesystemError);
        if (filesystemError)
        {
            std::filesystem::remove(triggerPath, filesystemError);
            filesystemError.clear();
            std::filesystem::rename(
                temporary,
                triggerPath,
                filesystemError);
        }
        if (filesystemError)
        {
            throw std::runtime_error(filesystemError.message());
        }
        error.clear();
        return true;
    }
    catch (const std::exception& exception)
    {
        error = exception.what();
        return false;
    }
}

nlohmann::json IRTriggerService::list() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    nlohmann::json result = document_;
    result["receiver"] = {
        {"running", running_.load()},
        {"available", running_.load() && !receiverDevice_.empty() &&
            receiverStatus_ == "Listening for Tower IR commands"},
        {"device", receiverDevice_},
        {"status", receiverStatus_},
        {"carrierKhz", 38},
    };
    return result;
}

bool IRTriggerService::save(
    const nlohmann::json& triggers,
    nlohmann::json& result,
    std::string& error)
{
    std::lock_guard<std::mutex> lock(mutex_);
    try
    {
        if (!triggers.is_array())
        {
            throw std::runtime_error("triggers must be an array");
        }

        nlohmann::json normalized = nlohmann::json::array();
        std::vector<unsigned int> usedCommands;
        for (const auto& supplied : triggers)
        {
            if (!supplied.is_object())
            {
                throw std::runtime_error("Every trigger must be an object");
            }
            const unsigned int command = supplied.value("command", 0U);
            if (command == 0)
            {
                continue;
            }
            if (command > 255 || std::find(
                    usedCommands.begin(),
                    usedCommands.end(),
                    command) != usedCommands.end())
            {
                throw std::runtime_error(
                    "Every generated IR command must be unique (1-255)");
            }
            usedCommands.push_back(command);
        }

        std::vector<unsigned int> assignedCommands = usedCommands;
        unsigned int nextCommand = 1;
        for (const auto& supplied : triggers)
        {
            if (!supplied.is_object())
            {
                throw std::runtime_error("Every trigger must be an object");
            }
            nlohmann::json trigger = supplied;
            if (trigger.value("name", "").empty())
            {
                throw std::runtime_error("Trigger name cannot be empty");
            }
            if (!trigger.contains("actions") ||
                !trigger.at("actions").is_array() ||
                trigger.at("actions").empty())
            {
                throw std::runtime_error(
                    "Trigger requires at least one action");
            }
            for (const auto& action : trigger.at("actions"))
            {
                validateAction(action);
            }

            unsigned int command = trigger.value("command", 0U);
            if (command == 0)
            {
                while (std::find(
                           assignedCommands.begin(),
                           assignedCommands.end(),
                           nextCommand) != assignedCommands.end())
                {
                    ++nextCommand;
                }
                if (nextCommand > 255)
                {
                    throw std::runtime_error(
                        "No generated IR command IDs remain (1-255)");
                }
                command = nextCommand++;
                assignedCommands.push_back(command);
            }
            trigger["id"] = trigger.value(
                "id",
                "tower-ir-" + std::to_string(command));
            trigger["enabled"] = trigger.value("enabled", true);
            trigger["protocol"] = "NEC";
            trigger["address"] = towerNecAddress;
            trigger["command"] = command;
            normalized.push_back(std::move(trigger));
        }

        document_ = {{"version", 1}, {"triggers", normalized}};
        if (!write(error))
        {
            return false;
        }
        result = document_;
        return true;
    }
    catch (const std::exception& exception)
    {
        error = exception.what();
        return false;
    }
}

bool IRTriggerService::remove(
    const std::string& id,
    std::string& error)
{
    std::lock_guard<std::mutex> lock(mutex_);
    auto& triggers = document_["triggers"];
    const std::size_t before = triggers.size();
    triggers.erase(
        std::remove_if(
            triggers.begin(),
            triggers.end(),
            [&id](const auto& trigger)
            {
                return trigger.value("id", "") == id;
            }),
        triggers.end());
    if (triggers.size() == before)
    {
        error = "IR trigger not found: " + id;
        return false;
    }
    return write(error);
}

bool IRTriggerService::teach(
    const std::string& id,
    const std::string& transmitterName,
    std::string& error)
{
    nlohmann::json trigger;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        for (const auto& candidate : document_["triggers"])
        {
            if (candidate.value("id", "") == id)
            {
                trigger = candidate;
                break;
            }
        }
    }
    if (trigger.is_null())
    {
        error = "IR trigger not found: " + id;
        return false;
    }

    IRTransmitterDatabase transmitterDatabase;
    IRTransmitter transmitter;
    if (!transmitterDatabase.load(transmitterName, transmitter))
    {
        error = "IR transmitter not found: " + transmitterName;
        return false;
    }

    IRCode code;
    code.protocol = "raw";
    code.carrierKhz = 38;
    code.pulses = necFrame(
        trigger.value("address", towerNecAddress),
        trigger.at("command").get<unsigned int>(),
        4);

    ignoreUntilMilliseconds_ = steadyMilliseconds() +
        std::chrono::duration_cast<std::chrono::milliseconds>(
            teachingReceiverGuard).count();

    const auto teachingEndsAt =
        std::chrono::steady_clock::now() + teachingDuration;
    do
    {
        if (!IRSender().send(code, transmitter, 33, 38))
        {
            error = "Tower could not transmit the SofaBaton teaching code";
            return false;
        }
    }
    while (std::chrono::steady_clock::now() < teachingEndsAt);

    error.clear();
    return true;
}

bool IRTriggerService::executeTrigger(
    const nlohmann::json& trigger,
    std::string& error)
{
    bool ok = false;
    bool displayTopLevel = false;
    {
        ExecutionDisplaySequence displaySequence;
        displayTopLevel = displaySequence.topLevel();
        ok = ActionExecutionService().executeAll(
            trigger.at("actions"),
            error);
    }
    if (displayTopLevel)
    {
        ExecutionDisplay::publishCompletion(
            trigger.value("name", "Remote button"),
            ok);
    }
    return ok;
}

bool IRTriggerService::runNow(
    const std::string& id,
    std::string& error)
{
    nlohmann::json trigger;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        for (const auto& candidate : document_["triggers"])
        {
            if (candidate.value("id", "") == id)
            {
                trigger = candidate;
                break;
            }
        }
    }
    if (trigger.is_null())
    {
        error = "IR trigger not found: " + id;
        return false;
    }
    return executeTrigger(trigger, error);
}

void IRTriggerService::processFrame(
    const std::vector<std::uint32_t>& frame)
{
    if (steadyMilliseconds() < ignoreUntilMilliseconds_.load())
    {
        return;
    }

    // NEC held keys may send short repeat frames without address/command.
    // They extend the quiet interval but must never execute an action.
    if (frame.size() == 3 && relativeMatch(frame[0], 9000, 0.35) &&
        relativeMatch(frame[1], 2250, 0.35) &&
        relativeMatch(frame[2], 562, 0.45))
    {
        std::lock_guard<std::mutex> lock(mutex_);
        const auto previous = lastTriggered_.find(lastReceivedTriggerId_);
        const auto now = std::chrono::steady_clock::now();
        if (previous != lastTriggered_.end() &&
            now - previous->second < triggerDebounce)
        {
            previous->second = now;
        }
        return;
    }

    unsigned int address = 0;
    unsigned int command = 0;
    if (!decodeNec(frame, address, command))
    {
        return;
    }

    nlohmann::json matched;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        lastReceivedTriggerId_.clear();
        for (const auto& trigger : document_["triggers"])
        {
            if (trigger.value("enabled", true) &&
                trigger.value("address", 0U) == address &&
                trigger.value("command", 0U) == command)
            {
                const std::string id = trigger.value("id", "");
                lastReceivedTriggerId_ = id;
                const auto now = std::chrono::steady_clock::now();
                const auto previous = lastTriggered_.find(id);
                if (previous != lastTriggered_.end() &&
                    now - previous->second < triggerDebounce)
                {
                    previous->second = now;
                    return;
                }
                lastTriggered_[id] = now;
                matched = trigger;
                break;
            }
        }
    }

    if (!matched.is_null())
    {
        std::string error;
        executeTrigger(matched, error);
        // Action sequences may block reception for longer than the cooldown.
        // Suppress buffered repeats as the receiver resumes draining input.
        std::lock_guard<std::mutex> lock(mutex_);
        lastTriggered_[matched.value("id", "")] =
            std::chrono::steady_clock::now();
    }
}

void IRTriggerService::receiverLoop()
{
    while (running_)
    {
        std::string device;
        for (const IRReceiverStatus& receiver : IRReceiverArray().discover())
        {
            if (receiver.receiver.nominalCarrierKhz == 38 &&
                receiver.available())
            {
                device = receiver.lircDevice;
                break;
            }
        }

        if (device.empty())
        {
            {
                std::lock_guard<std::mutex> lock(mutex_);
                receiverDevice_.clear();
                receiverStatus_ = "38 kHz IR receiver unavailable";
            }
            for (int count = 0; count < 50 && running_; ++count)
            {
                std::this_thread::sleep_for(
                    std::chrono::milliseconds(100));
            }
            continue;
        }

        const int descriptor = ::open(
            device.c_str(),
            O_RDONLY | O_NONBLOCK);
        if (descriptor < 0)
        {
            {
                std::lock_guard<std::mutex> lock(mutex_);
                receiverDevice_ = device;
                receiverStatus_ = "Could not open receiver";
            }
            std::this_thread::sleep_for(std::chrono::seconds(2));
            continue;
        }

        unsigned int receiveMode = LIRC_MODE_MODE2;
        (void)::ioctl(descriptor, LIRC_SET_REC_MODE, &receiveMode);

        {
            std::lock_guard<std::mutex> lock(mutex_);
            receiverDevice_ = device;
            receiverStatus_ = "Listening for Tower IR commands";
        }

        std::vector<std::uint32_t> frame;
        bool expectPulse = true;
        while (running_)
        {
            pollfd pollDescriptor{};
            pollDescriptor.fd = descriptor;
            pollDescriptor.events = POLLIN;
            const int ready = ::poll(&pollDescriptor, 1, 500);
            if (ready < 0 && errno != EINTR)
            {
                break;
            }
            if (ready <= 0 || (pollDescriptor.revents & POLLIN) == 0)
            {
                continue;
            }

            lirc_t sample = 0;
            const ssize_t received =
                ::read(descriptor, &sample, sizeof(sample));
            if (received != static_cast<ssize_t>(sizeof(sample)))
            {
                if (received < 0 && (errno == EAGAIN || errno == EINTR))
                {
                    continue;
                }
                break;
            }

            const unsigned int mode = sample & LIRC_MODE2_MASK;
            const std::uint32_t duration = sample & LIRC_VALUE_MASK;
            if (mode == LIRC_MODE2_TIMEOUT ||
                (mode == LIRC_MODE2_SPACE && duration >= 10000))
            {
                if (!frame.empty())
                {
                    processFrame(frame);
                    frame.clear();
                }
                expectPulse = true;
                continue;
            }
            if (mode != LIRC_MODE2_PULSE && mode != LIRC_MODE2_SPACE)
            {
                continue;
            }

            const bool pulse = mode == LIRC_MODE2_PULSE;
            if (pulse != expectPulse)
            {
                frame.clear();
                expectPulse = true;
                if (!pulse)
                {
                    continue;
                }
            }
            frame.push_back(duration);
            expectPulse = !expectPulse;
            if (frame.size() > 300)
            {
                frame.clear();
                expectPulse = true;
            }
        }

        ::close(descriptor);
        {
            std::lock_guard<std::mutex> lock(mutex_);
            receiverStatus_ = "Receiver restarting";
        }
    }
}
