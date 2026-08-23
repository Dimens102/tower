#include "core/network/TowerApiServer.h"

#include "core/service/CommandExecutor.h"
#include "core/service/IRLearningService.h"
#include "core/service/IRCalibrationService.h"
#include "core/service/RFCommandService.h"
#include "core/service/RFProvisioningService.h"
#include "devices/device.h"
#include "devices/device_database.h"
#include "devices/rf/rf_database.h"
#include "nlohmann/json.hpp"
#include "version.h"

#include <arpa/inet.h>
#include <cerrno>
#include <cstring>
#include <iostream>
#include <filesystem>
#include <chrono>
#include <ctime>
#include <iomanip>
#include <mutex>
#include <netinet/in.h>
#include <sstream>
#include <sys/socket.h>
#include <unistd.h>
#include <utility>
#include <vector>


namespace
{
std::mutex commandMutex;

std::string transportName(TransportType transport)
{
    return transport == TransportType::RF ? "RF" : "IR";
}

std::string executionStatusName(CommandExecutionStatus status)
{
    switch (status)
    {
        case CommandExecutionStatus::Success: return "success";
        case CommandExecutionStatus::DeviceNotFound: return "device_not_found";
        case CommandExecutionStatus::DeviceLoadFailed: return "device_load_failed";
        case CommandExecutionStatus::DeviceDisabled: return "device_disabled";
        case CommandExecutionStatus::CommandNotFound: return "command_not_found";
        case CommandExecutionStatus::CommandDisabled: return "command_disabled";
        case CommandExecutionStatus::InvalidMapping: return "invalid_mapping";
        case CommandExecutionStatus::TransportDataNotFound: return "transport_data_not_found";
        case CommandExecutionStatus::TransportDataInvalid: return "transport_data_invalid";
        case CommandExecutionStatus::TransmissionFailed: return "transmission_failed";
    }
    return "unknown";
}

void sendResponse(
    int fd,
    int status,
    const std::string& statusText,
    const nlohmann::json& body)
{
    const std::string payload = body.dump();
    std::ostringstream response;
    response << "HTTP/1.1 " << status << ' ' << statusText << "\r\n"
             << "Content-Type: application/json\r\n"
             << "Content-Length: " << payload.size() << "\r\n"
             << "Connection: close\r\n"
             << "Access-Control-Allow-Origin: *\r\n\r\n"
             << payload;
    const std::string bytes = response.str();
    ::send(fd, bytes.data(), bytes.size(), MSG_NOSIGNAL);
}

std::string headerValue(const std::string& request, const std::string& name)
{
    const std::string marker = "\r\n" + name + ": ";
    const auto start = request.find(marker);
    if (start == std::string::npos)
    {
        return {};
    }
    const auto valueStart = start + marker.size();
    const auto end = request.find("\r\n", valueStart);
    return request.substr(valueStart, end - valueStart);
}
}

TowerApiServer::TowerApiServer() = default;

TowerApiServer::~TowerApiServer()
{
    stop();
}

void TowerApiServer::setSensorProvider(
    std::function<std::vector<TowerApiSensorSnapshot>()> provider)
{
    sensorProvider_ = std::move(provider);
}

bool TowerApiServer::start(std::uint16_t port, const std::string& token)
{
    if (token.empty())
    {
        std::cerr << "Tower API disabled: TOWER_API_TOKEN is not set\n";
        return false;
    }

    listenFd_ = ::socket(AF_INET, SOCK_STREAM, 0);
    if (listenFd_ < 0)
    {
        return false;
    }

    int reuse = 1;
    ::setsockopt(listenFd_, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    address.sin_port = htons(port);

    if (::bind(listenFd_, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0 ||
        ::listen(listenFd_, 8) != 0)
    {
        ::close(listenFd_);
        listenFd_ = -1;
        return false;
    }

    token_ = token;
    running_ = true;
    thread_ = std::thread(&TowerApiServer::run, this);
    std::cout << "Tower API listening on port " << port << "\n";
    return true;
}

void TowerApiServer::stop()
{
    running_ = false;
    if (listenFd_ >= 0)
    {
        ::shutdown(listenFd_, SHUT_RDWR);
        ::close(listenFd_);
        listenFd_ = -1;
    }
    if (thread_.joinable())
    {
        thread_.join();
    }
}

void TowerApiServer::run()
{
    while (running_)
    {
        const int client = ::accept(listenFd_, nullptr, nullptr);
        if (client < 0)
        {
            if (running_ && errno != EINTR)
            {
                std::cerr << "Tower API accept failed: " << std::strerror(errno) << "\n";
            }
            continue;
        }
        handleClient(client);
        ::close(client);
    }
}

void TowerApiServer::handleClient(int clientFd)
{
    std::string request;
    char buffer[4096];
    ssize_t count = 0;

    do
    {
        count = ::recv(clientFd, buffer, sizeof(buffer), 0);
        if (count > 0)
        {
            request.append(buffer, static_cast<std::size_t>(count));
        }
    }
    while (count > 0 && request.find("\r\n\r\n") == std::string::npos);

    const auto headersEnd = request.find("\r\n\r\n");
    const std::string contentLengthText = headerValue(request, "Content-Length");
    if (headersEnd != std::string::npos && !contentLengthText.empty())
    {
        const std::size_t expectedSize =
            headersEnd + 4 + static_cast<std::size_t>(std::stoul(contentLengthText));
        while (request.size() < expectedSize)
        {
            count = ::recv(clientFd, buffer, sizeof(buffer), 0);
            if (count <= 0)
            {
                break;
            }
            request.append(buffer, static_cast<std::size_t>(count));
        }
    }

    const auto lineEnd = request.find("\r\n");
    if (lineEnd == std::string::npos)
    {
        sendResponse(clientFd, 400, "Bad Request", {{"error", "Invalid request"}});
        return;
    }

    std::istringstream requestLine(request.substr(0, lineEnd));
    std::string method;
    std::string path;
    std::string protocol;
    requestLine >> method >> path >> protocol;

    if (path == "/api/v1/status" && method == "GET")
    {
        sendResponse(clientFd, 200, "OK", {{"service", "tower"}, {"status", "ok"}, {"version", TOWER_VERSION}});
        return;
    }

    const std::string authorization = headerValue(request, "Authorization");
    if (authorization != "Bearer " + token_)
    {
        sendResponse(clientFd, 401, "Unauthorized", {{"error", "Invalid token"}});
        return;
    }

    if (path == "/api/v1/rf/modern/next" && method == "GET")
    {
        RFProvisioningService provisioning;
        RFModernDefaults defaults;
        std::string error;

        if (!provisioning.getNextModernDefaults(defaults, error))
        {
            sendResponse(
                clientFd,
                500,
                "Internal Server Error",
                {{"ok", false}, {"error", error}});
            return;
        }

        sendResponse(
            clientFd,
            200,
            "OK",
            {
                {"ok", true},
                {"recordId", defaults.recordName},
                {"fileName", defaults.recordName + ".rf"},
                {"suggestedTransmitterId", defaults.transmitterId},
                {"description", defaults.description},
                {"unit", defaults.unit},
                {"gpio", defaults.gpio},
                {"pulseUs", defaults.pulse},
                {"repeat", defaults.repeat}
            });
        return;
    }

    if (path == "/api/v1/rf/devices" && method == "GET")
    {
        nlohmann::json result = nlohmann::json::array();
        RFDatabase database;
        for (const RFDevice& device : database.listPowerDevices())
        {
            result.push_back({
                {"id", device.name},
                {"name", device.deviceName.empty() ? device.name : device.deviceName},
                {"status", device.status},
                {"actions", {"on", "off"}},
                {"protocol", device.protocol},
                {"description", device.description},
                {"house", device.house},
                {"unit", device.unit},
                {"gpio", device.gpio},
                {"pulseUs", device.pulse},
                {"repeat", device.repeat},
                {"onCode", device.onCode},
                {"offCode", device.offCode},
                {"transmitterId", device.transmitterId}
            });
        }
        sendResponse(clientFd, 200, "OK", {{"devices", result}});
        return;
    }

    if (path == "/api/v1/ir/calibration/prepare" && method == "POST")
    {
        const auto headerEnd = request.find("\r\n\r\n");
        const std::string body =
            headerEnd == std::string::npos
                ? std::string{}
                : request.substr(headerEnd + 4);

        try
        {
            const auto json =
                nlohmann::json::parse(body);

            const std::string device =
                json.at("device").get<std::string>();

            IRCalibrationService calibration;
            IRCalibrationPreparation preparation;
            std::string error;

            if (!calibration.prepare(
                    device,
                    preparation,
                    error))
            {
                sendResponse(
                    clientFd,
                    400,
                    "Bad Request",
                    {
                        {"ok", false},
                        {"error", error}
                    });
                return;
            }

            nlohmann::json commands =
                nlohmann::json::array();

            for (const IRCalibrationCommandInfo& command :
                 preparation.commands)
            {
                commands.push_back({
                    {"id", command.id},
                    {"description", command.description},
                    {"carrierKhz", command.carrierKhz}
                });
            }

            sendResponse(
                clientFd,
                200,
                "OK",
                {
                    {"ok", true},
                    {"device", device},
                    {"commands", commands},
                    {"suggestedCommand", preparation.suggestedCommand},
                    {"transmitter", preparation.transmitter},
                    {"dutyCandidates", preparation.dutyCandidates},
                    {"batchSize", preparation.batchSize},
                    {"confirmThreshold", preparation.confirmThreshold},
                    {"alreadyCalibrated", preparation.alreadyCalibrated},
                    {"existingCarrierKhz", preparation.existingCarrierKhz},
                    {"existingDutyPercent", preparation.existingDutyPercent},
                    {"existingCommand", preparation.existingCommand}
                });
        }
        catch (const std::exception& exception)
        {
            sendResponse(
                clientFd,
                400,
                "Bad Request",
                {
                    {"ok", false},
                    {"error", exception.what()}
                });
        }

        return;
    }

    if (path == "/api/v1/ir/calibration/batch" && method == "POST")
    {
        const auto headerEnd = request.find("\r\n\r\n");
        const std::string body =
            headerEnd == std::string::npos
                ? std::string{}
                : request.substr(headerEnd + 4);

        try
        {
            const auto json =
                nlohmann::json::parse(body);

            const std::string device =
                json.at("device").get<std::string>();
            const std::string command =
                json.at("command").get<std::string>();
            const unsigned int carrierKhz =
                json.at("carrierKhz").get<unsigned int>();
            const unsigned int dutyPercent =
                json.at("dutyPercent").get<unsigned int>();
            const unsigned int count =
                json.value("count", 10U);
            const unsigned int preDelaySeconds =
                json.value("preDelaySeconds", 5U);
            const unsigned int intervalMilliseconds =
                json.value("intervalMilliseconds", 1000U);

            IRCalibrationService calibration;
            std::string error;

            std::lock_guard<std::mutex> lock(commandMutex);

            if (!calibration.sendBatch(
                    device,
                    command,
                    carrierKhz,
                    dutyPercent,
                    count,
                    preDelaySeconds,
                    intervalMilliseconds,
                    error))
            {
                sendResponse(
                    clientFd,
                    400,
                    "Bad Request",
                    {
                        {"ok", false},
                        {"error", error}
                    });
                return;
            }

            sendResponse(
                clientFd,
                200,
                "OK",
                {
                    {"ok", true},
                    {"device", device},
                    {"command", command},
                    {"carrierKhz", carrierKhz},
                    {"dutyPercent", dutyPercent},
                    {"count", count},
                    {"message", "Calibration batch sent"}
                });
        }
        catch (const std::exception& exception)
        {
            sendResponse(
                clientFd,
                400,
                "Bad Request",
                {
                    {"ok", false},
                    {"error", exception.what()}
                });
        }

        return;
    }

    if (path == "/api/v1/ir/calibration/save" && method == "POST")
    {
        const auto headerEnd = request.find("\r\n\r\n");
        const std::string body =
            headerEnd == std::string::npos
                ? std::string{}
                : request.substr(headerEnd + 4);

        try
        {
            const auto json =
                nlohmann::json::parse(body);

            const std::string device =
                json.at("device").get<std::string>();
            const std::string command =
                json.at("command").get<std::string>();
            const unsigned int carrierKhz =
                json.at("carrierKhz").get<unsigned int>();
            const unsigned int dutyPercent =
                json.at("dutyPercent").get<unsigned int>();

            IRCalibrationService calibration;
            std::string error;

            std::lock_guard<std::mutex> lock(commandMutex);

            if (!calibration.saveProfile(
                    device,
                    command,
                    carrierKhz,
                    dutyPercent,
                    error))
            {
                sendResponse(
                    clientFd,
                    400,
                    "Bad Request",
                    {
                        {"ok", false},
                        {"error", error}
                    });
                return;
            }

            sendResponse(
                clientFd,
                200,
                "OK",
                {
                    {"ok", true},
                    {"device", device},
                    {"command", command},
                    {"carrierKhz", carrierKhz},
                    {"dutyPercent", dutyPercent},
                    {"transmitter", "Tower-IR-TX-001"},
                    {"message", "IR calibration profile saved"}
                });
        }
        catch (const std::exception& exception)
        {
            sendResponse(
                clientFd,
                400,
                "Bad Request",
                {
                    {"ok", false},
                    {"error", exception.what()}
                });
        }

        return;
    }

    if (path == "/api/v1/ir/devices/create" && method == "POST")
    {
        const auto headerEnd = request.find("\r\n\r\n");
        const std::string body =
            headerEnd == std::string::npos
                ? std::string{}
                : request.substr(headerEnd + 4);

        try
        {
            const auto json = nlohmann::json::parse(body);

            const std::string manufacturer =
                json.value("manufacturer", "");
            const std::string remoteName =
                json.value("remoteName", "");
            const std::string deviceName =
                json.at("deviceName").get<std::string>();
            const std::string location =
                json.value("location", "");
            const std::string transmitter =
                json.value(
                    "transmitter",
                    "Tower-IR-TX-001");

            IRLearningService learning;
            Device created;
            std::string error;

            std::lock_guard<std::mutex> lock(commandMutex);

            if (!learning.createDevice(
                    manufacturer,
                    remoteName,
                    deviceName,
                    location,
                    transmitter,
                    created,
                    error))
            {
                sendResponse(
                    clientFd,
                    400,
                    "Bad Request",
                    {
                        {"ok", false},
                        {"error", error}
                    });
                return;
            }

            sendResponse(
                clientFd,
                200,
                "OK",
                {
                    {"ok", true},
                    {"deviceId", created.id},
                    {"deviceName", created.name},
                    {"manufacturer", created.manufacturer},
                    {"remoteName", created.remoteName},
                    {"location", created.location},
                    {"transmitter", created.transmitter},
                    {"message", "IR device profile created"}
                });
        }
        catch (const std::exception& exception)
        {
            sendResponse(
                clientFd,
                400,
                "Bad Request",
                {
                    {"ok", false},
                    {"error", exception.what()}
                });
        }

        return;
    }

    if (path == "/api/v1/ir/learn/capture" && method == "POST")
    {
        const auto headerEnd = request.find("\r\n\r\n");
        const std::string body =
            headerEnd == std::string::npos
                ? std::string{}
                : request.substr(headerEnd + 4);

        try
        {
            const auto json = nlohmann::json::parse(body);

            const std::string device =
                json.at("device").get<std::string>();
            const std::string command =
                json.at("command").get<std::string>();
            const std::string description =
                json.value("description", "");
            const double seconds =
                json.value("seconds", 8.0);
            const bool force =
                json.value("force", false);

            IRLearningService learning;
            IRLearnResult result;
            std::string error;

            std::lock_guard<std::mutex> lock(commandMutex);

            if (!learning.captureAndAnalyze(
                    device,
                    command,
                    description,
                    seconds,
                    force,
                    result,
                    error))
            {
                sendResponse(
                    clientFd,
                    result.failureCode == 2 ? 422 : 400,
                    result.failureCode == 2
                        ? "Unprocessable Entity"
                        : "Bad Request",
                    {
                        {"ok", false},
                        {"error", error},
                        {"captureId", result.captureId},
                        {"capturePath", result.capturePath},
                        {"failureCode", result.failureCode}
                    });
                return;
            }

            nlohmann::json receivers =
                nlohmann::json::array();

            for (const IRReceiverCaptureStat& stat :
                 result.receiverStats)
            {
                receivers.push_back({
                    {"gpio", stat.gpio},
                    {"receiver", stat.receiverModel},
                    {"carrierKhz", stat.nominalCarrierKhz},
                    {"timings", stat.timingCount},
                    {"pulses", stat.pulseCount},
                    {"frames", stat.frameCount},
                    {"valid", stat.validFrameCount},
                    {"result", stat.result}
                });
            }

            nlohmann::json analysis =
                nlohmann::json::array();

            for (const IRAnalysisRow& row :
                 result.code.analysis)
            {
                analysis.push_back({
                    {"gpio", row.gpio},
                    {"receiver", row.receiverModel},
                    {"carrierKhz", row.nominalCarrierKhz},
                    {"frames", row.frameCount},
                    {"valid", row.validFrameCount},
                    {"result", row.result},
                    {"protocol", row.decodedProtocol},
                    {"address", row.address},
                    {"command", row.decodedCommand}
                });
            }

            sendResponse(
                clientFd,
                200,
                "OK",
                {
                    {"ok", true},
                    {"captureId", result.captureId},
                    {"capturePath", result.capturePath},
                    {"device", result.deviceName},
                    {"commandName", result.commandName},
                    {"description", result.description},
                    {"protocol", result.code.decodedProtocol},
                    {"address", result.code.address},
                    {"decodedCommand", result.code.decodedCommand},
                    {"carrierKhz", result.code.carrierKhz},
                    {"receiverGpio", result.code.receiverGpio},
                    {"receiverModel", result.code.receiverModel},
                    {"initialFrames", result.code.captureInitialFrames},
                    {"repeatFrames", result.code.captureRepeatFrames},
                    {"rawTimings", result.code.pulses.size()},
                    {"rawFallback", result.rawFallback},
                    {"stablePartialDecode", result.stablePartialDecode},
                    {"note", result.note},
                    {"duplicates", result.duplicates},
                    {"receivers", receivers},
                    {"analysis", analysis}
                });
        }
        catch (const std::exception& exception)
        {
            sendResponse(
                clientFd,
                400,
                "Bad Request",
                {
                    {"ok", false},
                    {"error", exception.what()}
                });
        }

        return;
    }

    if (path == "/api/v1/ir/learn/save" && method == "POST")
    {
        const auto headerEnd = request.find("\r\n\r\n");
        const std::string body =
            headerEnd == std::string::npos
                ? std::string{}
                : request.substr(headerEnd + 4);

        try
        {
            const auto json = nlohmann::json::parse(body);

            const std::string captureId =
                json.at("captureId").get<std::string>();
            const std::string device =
                json.at("device").get<std::string>();
            const std::string command =
                json.at("command").get<std::string>();
            const std::string description =
                json.value("description", "");
            const bool force =
                json.value("force", false);
            const bool acceptDuplicate =
                json.value("acceptDuplicate", false);

            IRLearningService learning;
            IRLearnResult result;
            std::string error;

            std::lock_guard<std::mutex> lock(commandMutex);

            if (!learning.analyzeExistingCapture(
                    captureId,
                    device,
                    command,
                    description,
                    result,
                    error))
            {
                sendResponse(
                    clientFd,
                    result.failureCode == 2 ? 422 : 400,
                    result.failureCode == 2
                        ? "Unprocessable Entity"
                        : "Bad Request",
                    {
                        {"ok", false},
                        {"error", error},
                        {"captureId", captureId}
                    });
                return;
            }

            if (!result.duplicates.empty() &&
                !acceptDuplicate)
            {
                sendResponse(
                    clientFd,
                    409,
                    "Conflict",
                    {
                        {"ok", false},
                        {"error", "Duplicate IR signal"},
                        {"duplicates", result.duplicates}
                    });
                return;
            }

            if (!learning.saveResult(
                    result,
                    force,
                    acceptDuplicate,
                    error))
            {
                sendResponse(
                    clientFd,
                    400,
                    "Bad Request",
                    {
                        {"ok", false},
                        {"error", error}
                    });
                return;
            }

            sendResponse(
                clientFd,
                200,
                "OK",
                {
                    {"ok", true},
                    {"device", device},
                    {"command", command},
                    {"protocol", result.code.decodedProtocol},
                    {"carrierKhz", result.code.carrierKhz},
                    {"receiverGpio", result.code.receiverGpio},
                    {"receiverModel", result.code.receiverModel},
                    {"message", "IR command saved"}
                });
        }
        catch (const std::exception& exception)
        {
            sendResponse(
                clientFd,
                400,
                "Bad Request",
                {
                    {"ok", false},
                    {"error", exception.what()}
                });
        }

        return;
    }

    if (path == "/api/v1/system/time" && method == "GET")
    {
        const auto now =
            std::chrono::system_clock::now();

        const std::time_t nowTime =
            std::chrono::system_clock::to_time_t(now);

        std::tm local = {};
        localtime_r(&nowTime, &local);

        std::ostringstream localTime;
        localTime << std::put_time(
            &local,
            "%H:%M:%S"
        );

        std::ostringstream localDate;
        localDate << std::put_time(
            &local,
            "%Y-%m-%d"
        );

        std::ostringstream timezone;
        timezone << std::put_time(
            &local,
            "%Z"
        );

        sendResponse(
            clientFd,
            200,
            "OK",
            {
                {"ok", true},
                {"localTime", localTime.str()},
                {"localDate", localDate.str()},
                {"timezone", timezone.str()}
            });
        return;
    }

    if (path == "/api/v1/devices" && method == "GET")
    {
        nlohmann::json devices = nlohmann::json::array();
        DeviceDatabase database;

        for (const std::string& deviceId : database.listDevices())
        {
            Device device;
            if (!database.loadDevice(deviceId, device))
            {
                continue;
            }

            nlohmann::json commands = nlohmann::json::array();
            for (const DeviceCommand& command : device.commands)
            {
                commands.push_back({
                    {"id", command.id},
                    {"name", command.name.empty() ? command.id : command.name},
                    {"description", command.description},
                    {"transport", transportName(command.transport)},
                    {"enabled", command.enabled}
                });
            }

            devices.push_back({
                {"id", device.id},
                {"name", device.name.empty() ? device.id : device.name},
                {"manufacturer", device.manufacturer},
                {"model", device.model},
                {"remoteName", device.remoteName},
                {"location", device.location},
                {"transmitter", device.transmitter},
                {"enabled", device.enabled},
                {"commands", commands}
            });
        }

        sendResponse(clientFd, 200, "OK", {{"devices", devices}});
        return;
    }

    if (path == "/api/v1/devices/rename" && method == "POST")
    {
        const auto headerEnd =
            request.find("\r\n\r\n");

        const std::string body =
            headerEnd == std::string::npos
                ? std::string{}
                : request.substr(headerEnd + 4);

        try
        {
            const auto json =
                nlohmann::json::parse(body);

            const std::string deviceId =
                json.at("device").get<std::string>();

            const std::string newName =
                json.at("name").get<std::string>();

            if (deviceId.empty() ||
                deviceId.find("..") != std::string::npos ||
                deviceId.find('/') != std::string::npos ||
                deviceId.find('\\') != std::string::npos)
            {
                sendResponse(
                    clientFd,
                    400,
                    "Bad Request",
                    {
                        {"ok", false},
                        {"error", "Invalid device id"}
                    });
                return;
            }

            if (newName.empty() ||
                newName.size() > 120)
            {
                sendResponse(
                    clientFd,
                    400,
                    "Bad Request",
                    {
                        {"ok", false},
                        {"error", "Device name must contain 1 to 120 characters"}
                    });
                return;
            }

            std::lock_guard<std::mutex> lock(
                commandMutex
            );

            DeviceDatabase database;
            Device device;

            if (!database.loadDevice(
                    deviceId,
                    device))
            {
                sendResponse(
                    clientFd,
                    404,
                    "Not Found",
                    {
                        {"ok", false},
                        {"error", "Device not found: " + deviceId}
                    });
                return;
            }

            device.name = newName;

            if (!database.saveDevice(device))
            {
                sendResponse(
                    clientFd,
                    500,
                    "Internal Server Error",
                    {
                        {"ok", false},
                        {"error", "Failed to save renamed device"}
                    });
                return;
            }

            sendResponse(
                clientFd,
                200,
                "OK",
                {
                    {"ok", true},
                    {"device", deviceId},
                    {"name", newName},
                    {"message", "IR device renamed"}
                });
        }
        catch (const std::exception& exception)
        {
            sendResponse(
                clientFd,
                400,
                "Bad Request",
                {
                    {"ok", false},
                    {"error", exception.what()}
                });
        }

        return;
    }

    if (path == "/api/v1/ir/commands/delete" && method == "POST")
    {
        const auto headerEnd = request.find("\r\n\r\n");
        const std::string body =
            headerEnd == std::string::npos
                ? std::string{}
                : request.substr(headerEnd + 4);

        try
        {
            const auto json = nlohmann::json::parse(body);
            const std::string deviceId =
                json.at("device").get<std::string>();
            const std::string commandId =
                json.at("command").get<std::string>();

            const auto invalidName = [](const std::string& value)
            {
                return value.empty() ||
                    value == "." ||
                    value == ".." ||
                    value.find('/') != std::string::npos ||
                    value.find('\\') != std::string::npos;
            };

            if (invalidName(deviceId) || invalidName(commandId))
            {
                sendResponse(
                    clientFd,
                    400,
                    "Bad Request",
                    {
                        {"ok", false},
                        {"error", "Invalid device or command id"}
                    });
                return;
            }

            std::lock_guard<std::mutex> lock(commandMutex);
            DeviceDatabase database;
            Device device;

            if (!database.loadDevice(deviceId, device))
            {
                sendResponse(
                    clientFd,
                    404,
                    "Not Found",
                    {
                        {"ok", false},
                        {"error", "Device not found: " + deviceId}
                    });
                return;
            }

            std::size_t irCommandCount = 0;
            for (const DeviceCommand& candidate : device.commands)
            {
                if (candidate.transport == TransportType::IR)
                {
                    ++irCommandCount;
                }
            }

            if (irCommandCount <= 1)
            {
                sendResponse(
                    clientFd,
                    409,
                    "Conflict",
                    {
                        {"ok", false},
                        {"error", "The last IR command cannot be removed. Delete the remote instead."}
                    });
                return;
            }

            auto selected = device.commands.end();
            for (auto it = device.commands.begin();
                 it != device.commands.end();
                 ++it)
            {
                if (it->id == commandId &&
                    it->transport == TransportType::IR)
                {
                    selected = it;
                    break;
                }
            }

            if (selected == device.commands.end())
            {
                sendResponse(
                    clientFd,
                    404,
                    "Not Found",
                    {
                        {"ok", false},
                        {"error", "IR command not found: " + commandId}
                    });
                return;
            }

            const Device originalDevice = device;
            const std::string transportDevice =
                selected->transportDevice.empty()
                    ? deviceId
                    : selected->transportDevice;
            const std::string transportCommand =
                selected->transportCommand.empty()
                    ? selected->id
                    : selected->transportCommand;

            if (invalidName(transportDevice) ||
                invalidName(transportCommand))
            {
                sendResponse(
                    clientFd,
                    400,
                    "Bad Request",
                    {
                        {"ok", false},
                        {"error", "Invalid IR transport mapping"}
                    });
                return;
            }

            device.commands.erase(selected);

            if (!database.saveDevice(device))
            {
                sendResponse(
                    clientFd,
                    500,
                    "Internal Server Error",
                    {
                        {"ok", false},
                        {"error", "Failed to remove command from device profile"}
                    });
                return;
            }

            bool shared = false;
            for (const std::string& otherId : database.listDevices())
            {
                Device other;
                if (!database.loadDevice(otherId, other))
                {
                    continue;
                }

                for (const DeviceCommand& otherCommand : other.commands)
                {
                    const std::string otherTransportDevice =
                        otherCommand.transportDevice.empty()
                            ? other.id
                            : otherCommand.transportDevice;
                    const std::string otherTransportCommand =
                        otherCommand.transportCommand.empty()
                            ? otherCommand.id
                            : otherCommand.transportCommand;

                    if (otherCommand.transport == TransportType::IR &&
                        otherTransportDevice == transportDevice &&
                        otherTransportCommand == transportCommand)
                    {
                        shared = true;
                        break;
                    }
                }

                if (shared)
                {
                    break;
                }
            }

            bool removedIrData = false;
            if (!shared)
            {
                const std::filesystem::path irPath =
                    std::filesystem::path("data") /
                    "ir" /
                    "devices" /
                    transportDevice /
                    (transportCommand + ".ir");

                const std::filesystem::path backupPath =
                    irPath.string() + ".tower-learn-backup";

                std::error_code existsError;
                const bool irExists =
                    std::filesystem::exists(irPath, existsError);

                if (existsError)
                {
                    database.saveDevice(originalDevice);

                    sendResponse(
                        clientFd,
                        500,
                        "Internal Server Error",
                        {
                            {"ok", false},
                            {"error", "Could not inspect IR recording: " + existsError.message()}
                        });
                    return;
                }

                if (irExists)
                {
                    std::error_code removeError;
                    std::filesystem::remove(irPath, removeError);

                    if (removeError)
                    {
                        database.saveDevice(originalDevice);

                        sendResponse(
                            clientFd,
                            500,
                            "Internal Server Error",
                            {
                                {"ok", false},
                                {"error", "Could not remove IR recording: " + removeError.message()}
                            });
                        return;
                    }

                    removedIrData = true;
                }

                // A replacement backup is only safety history. Remove it on a
                // best-effort basis; failure must not restore a logical command
                // whose active .ir recording has already been deleted.
                std::error_code backupExistsError;
                if (std::filesystem::exists(
                        backupPath,
                        backupExistsError) &&
                    !backupExistsError)
                {
                    std::error_code backupRemoveError;
                    std::filesystem::remove(
                        backupPath,
                        backupRemoveError);
                }
            }

            sendResponse(
                clientFd,
                200,
                "OK",
                {
                    {"ok", true},
                    {"device", deviceId},
                    {"command", commandId},
                    {"removedIrData", removedIrData},
                    {"preservedSharedIrData", shared},
                    {"message", "Deleted IR command: " + commandId}
                });
        }
        catch (const std::exception& exception)
        {
            sendResponse(
                clientFd,
                400,
                "Bad Request",
                {
                    {"ok", false},
                    {"error", exception.what()}
                });
        }

        return;
    }

    if (path == "/api/v1/devices/delete" && method == "POST")
    {
        const auto headerEnd = request.find("\r\n\r\n");
        const std::string body = headerEnd == std::string::npos
            ? std::string{}
            : request.substr(headerEnd + 4);

        try
        {
            const auto json = nlohmann::json::parse(body);
            const std::string deviceId =
                json.at("device").get<std::string>();

            if (deviceId.empty() ||
                deviceId.find("..") != std::string::npos ||
                deviceId.find('/') != std::string::npos ||
                deviceId.find('\\') != std::string::npos)
            {
                sendResponse(
                    clientFd,
                    400,
                    "Bad Request",
                    {{"ok", false}, {"error", "Invalid device id"}});
                return;
            }

            std::lock_guard<std::mutex> lock(commandMutex);
            DeviceDatabase database;

            if (!database.deviceExists(deviceId))
            {
                sendResponse(
                    clientFd,
                    404,
                    "Not Found",
                    {
                        {"ok", false},
                        {"error", "Device not found: " + deviceId}
                    });
                return;
            }

            Device device;
            if (!database.loadDevice(deviceId, device))
            {
                sendResponse(
                    clientFd,
                    500,
                    "Internal Server Error",
                    {
                        {"ok", false},
                        {"error", "Failed to load device before deletion"}
                    });
                return;
            }

            std::vector<std::string> transportDevices;
            for (const DeviceCommand& command : device.commands)
            {
                if (command.transport != TransportType::IR ||
                    command.transportDevice.empty())
                {
                    continue;
                }

                bool alreadyPresent = false;
                for (const std::string& existing : transportDevices)
                {
                    if (existing == command.transportDevice)
                    {
                        alreadyPresent = true;
                        break;
                    }
                }
                if (!alreadyPresent)
                {
                    transportDevices.push_back(command.transportDevice);
                }
            }

            if (!database.deleteDevice(deviceId))
            {
                sendResponse(
                    clientFd,
                    500,
                    "Internal Server Error",
                    {
                        {"ok", false},
                        {"error", "Failed to delete device profile"}
                    });
                return;
            }

            nlohmann::json removedIrData = nlohmann::json::array();
            nlohmann::json preservedIrData = nlohmann::json::array();

            for (const std::string& transportDevice : transportDevices)
            {
                bool shared = false;

                for (const std::string& otherId : database.listDevices())
                {
                    Device other;
                    if (!database.loadDevice(otherId, other))
                    {
                        continue;
                    }

                    for (const DeviceCommand& otherCommand : other.commands)
                    {
                        if (otherCommand.transport == TransportType::IR &&
                            otherCommand.transportDevice == transportDevice)
                        {
                            shared = true;
                            break;
                        }
                    }
                    if (shared)
                    {
                        break;
                    }
                }

                if (shared)
                {
                    preservedIrData.push_back(transportDevice);
                    continue;
                }

                std::error_code error;
                const std::filesystem::path directory =
                    std::filesystem::path("data") /
                    "ir" /
                    "devices" /
                    transportDevice;

                if (std::filesystem::exists(directory))
                {
                    std::filesystem::remove_all(directory, error);
                }

                if (error)
                {
                    preservedIrData.push_back(transportDevice);
                }
                else
                {
                    removedIrData.push_back(transportDevice);
                }
            }

            const std::string displayName =
                device.name.empty() ? deviceId : device.name;

            sendResponse(
                clientFd,
                200,
                "OK",
                {
                    {"ok", true},
                    {"device", deviceId},
                    {"name", displayName},
                    {"removedIrData", removedIrData},
                    {"preservedSharedIrData", preservedIrData},
                    {"message", "Deleted device: " + displayName}
                });
        }
        catch (const std::exception& exception)
        {
            sendResponse(
                clientFd,
                400,
                "Bad Request",
                {{"ok", false}, {"error", exception.what()}});
        }
        return;
    }

    if (path == "/api/v1/sensors" && method == "GET")
    {
        nlohmann::json sensors = nlohmann::json::array();
        if (sensorProvider_)
        {
            for (const TowerApiSensorSnapshot& sensor : sensorProvider_())
            {
                nlohmann::json measurements = nlohmann::json::array();
                for (const TowerApiSensorMeasurement& measurement : sensor.measurements)
                {
                    measurements.push_back({
                        {"name", measurement.name},
                        {"unit", measurement.unit},
                        {"value", measurement.value}
                    });
                }

                sensors.push_back({
                    {"id", sensor.id},
                    {"name", sensor.name},
                    {"available", sensor.available},
                    {"timestampUtc", sensor.timestampUtc},
                    {"ageSeconds", sensor.ageSeconds},
                    {"measurements", measurements}
                });
            }
        }
        sendResponse(clientFd, 200, "OK", {{"sensors", sensors}});
        return;
    }

    if (path == "/api/v1/execute" && method == "POST")
    {
        const auto headerEnd = request.find("\r\n\r\n");
        const std::string body = headerEnd == std::string::npos ? std::string{} : request.substr(headerEnd + 4);
        try
        {
            const auto json = nlohmann::json::parse(body);
            const std::string device = json.at("device").get<std::string>();
            const std::string command = json.at("command").get<std::string>();

            std::vector<std::string> transmitters;
            if (json.contains("transmitter") &&
                !json.at("transmitter").is_null())
            {
                transmitters.push_back(
                    json.at("transmitter").get<std::string>());
            }
            if (json.contains("transmitters") &&
                json.at("transmitters").is_array())
            {
                for (const auto& entry : json.at("transmitters"))
                {
                    transmitters.push_back(entry.get<std::string>());
                }
            }

            std::lock_guard<std::mutex> lock(commandMutex);
            CommandExecutor executor;
            const CommandExecutionResult execution = transmitters.empty()
                ? executor.execute(device, command)
                : executor.execute(device, command, transmitters);

            nlohmann::json response = {
                {"ok", execution.succeeded()},
                {"device", device},
                {"command", command},
                {"transport", transportName(execution.transport)},
                {"status", executionStatusName(execution.status)},
                {"message", execution.message}
            };
            if (!transmitters.empty())
            {
                response["transmitters"] = transmitters;
            }

            sendResponse(
                clientFd,
                execution.succeeded() ? 200 : 400,
                execution.succeeded() ? "OK" : "Bad Request",
                response);
        }
        catch (const std::exception& exception)
        {
            sendResponse(clientFd, 400, "Bad Request", {{"ok", false}, {"error", exception.what()}});
        }
        return;
    }

    if (path == "/api/v1/rf/create" && method == "POST")
    {
        const auto headerEnd = request.find("\r\n\r\n");
        const std::string body =
            headerEnd == std::string::npos
                ? std::string{}
                : request.substr(headerEnd + 4);

        try
        {
            const auto json = nlohmann::json::parse(body);

            RFProvisioningService provisioning;
            RFModernDefaults defaults;
            std::string error;

            if (!provisioning.getNextModernDefaults(defaults, error))
            {
                sendResponse(
                    clientFd,
                    500,
                    "Internal Server Error",
                    {{"ok", false}, {"error", error}});
                return;
            }

            const std::string deviceName =
                json.at("deviceName").get<std::string>();
            const std::string description =
                json.value("description", defaults.description);
            const std::string transmitterId =
                json.value("transmitterId", defaults.transmitterId);
            const int unit =
                json.value("unit", defaults.unit);

            RFDevice created;
            std::lock_guard<std::mutex> lock(commandMutex);

            if (!provisioning.createModernPowerDevice(
                    deviceName,
                    description,
                    transmitterId,
                    unit,
                    created,
                    error))
            {
                sendResponse(
                    clientFd,
                    400,
                    "Bad Request",
                    {{"ok", false}, {"error", error}});
                return;
            }

            sendResponse(
                clientFd,
                200,
                "OK",
                {
                    {"ok", true},
                    {"recordId", created.name},
                    {"fileName", created.name + ".rf"},
                    {"deviceName", created.deviceName},
                    {"description", created.description},
                    {"transmitterId", created.transmitterId},
                    {"unit", created.unit},
                    {"gpio", created.gpio},
                    {"pulseUs", created.pulse},
                    {"repeat", created.repeat},
                    {"status", created.status}
                });
        }
        catch (const std::exception& exception)
        {
            sendResponse(
                clientFd,
                400,
                "Bad Request",
                {{"ok", false}, {"error", exception.what()}});
        }

        return;
    }

    if (path == "/api/v1/rf/pair/start" && method == "POST")
    {
        const auto headerEnd = request.find("\r\n\r\n");
        const std::string body =
            headerEnd == std::string::npos
                ? std::string{}
                : request.substr(headerEnd + 4);

        try
        {
            const auto json = nlohmann::json::parse(body);
            const std::string device =
                json.at("device").get<std::string>();

            RFDatabase database;
            RFDevice definition;

            if (!database.loadPowerDevice(device, definition))
            {
                sendResponse(
                    clientFd,
                    404,
                    "Not Found",
                    {
                        {"ok", false},
                        {"error", "RF power device not found"},
                        {"device", device}
                    });
                return;
            }

            if (definition.protocol != "kaku_ac")
            {
                sendResponse(
                    clientFd,
                    400,
                    "Bad Request",
                    {
                        {"ok", false},
                        {"error", "Pair wizard only supports modern KAKU"},
                        {"device", device}
                    });
                return;
            }

            std::string error;
            std::lock_guard<std::mutex> lock(commandMutex);
            RFCommandService rfService;

            if (!rfService.send(device, "on", error))
            {
                sendResponse(
                    clientFd,
                    400,
                    "Bad Request",
                    {
                        {"ok", false},
                        {"error", error},
                        {"device", device}
                    });
                return;
            }

            sendResponse(
                clientFd,
                200,
                "OK",
                {
                    {"ok", true},
                    {"device", device},
                    {"action", "on"},
                    {"repeat", definition.repeat},
                    {"message", "Pairing ON transmission sent"}
                });
        }
        catch (const std::exception& exception)
        {
            sendResponse(
                clientFd,
                400,
                "Bad Request",
                {{"ok", false}, {"error", exception.what()}});
        }

        return;
    }

    if (path == "/api/v1/rf/pair/status" && method == "POST")
    {
        const auto headerEnd = request.find("\r\n\r\n");
        const std::string body =
            headerEnd == std::string::npos
                ? std::string{}
                : request.substr(headerEnd + 4);

        try
        {
            const auto json = nlohmann::json::parse(body);
            const std::string device =
                json.at("device").get<std::string>();
            const bool paired =
                json.at("paired").get<bool>();

            RFProvisioningService provisioning;
            std::string error;
            std::lock_guard<std::mutex> lock(commandMutex);

            if (!provisioning.setPairingStatus(
                    device,
                    paired,
                    error))
            {
                sendResponse(
                    clientFd,
                    400,
                    "Bad Request",
                    {
                        {"ok", false},
                        {"error", error},
                        {"device", device}
                    });
                return;
            }

            sendResponse(
                clientFd,
                200,
                "OK",
                {
                    {"ok", true},
                    {"device", device},
                    {"status", paired ? "paired" : "unpaired"},
                    {"message", paired
                        ? "RF device marked paired"
                        : "RF device marked unpaired"}
                });
        }
        catch (const std::exception& exception)
        {
            sendResponse(
                clientFd,
                400,
                "Bad Request",
                {{"ok", false}, {"error", exception.what()}});
        }

        return;
    }

    if (path == "/api/v1/rf/send" && method == "POST")
    {
        const auto headerEnd = request.find("\r\n\r\n");
        const std::string body = headerEnd == std::string::npos ? std::string{} : request.substr(headerEnd + 4);
        try
        {
            const auto json = nlohmann::json::parse(body);
            const std::string device = json.at("device").get<std::string>();
            const std::string action = json.at("action").get<std::string>();
            std::string error;
            std::lock_guard<std::mutex> lock(commandMutex);
            RFCommandService rfService;
            if (!rfService.send(device, action, error))
            {
                sendResponse(
                    clientFd,
                    400,
                    "Bad Request",
                    {
                        {"ok", false},
                        {"transport", "RF"},
                        {"status", "transmission_failed"},
                        {"device", device},
                        {"action", action},
                        {"message", error},
                        {"error", error}
                    });
                return;
            }
            sendResponse(
                clientFd,
                200,
                "OK",
                {
                    {"ok", true},
                    {"transport", "RF"},
                    {"status", "success"},
                    {"device", device},
                    {"action", action}
                });
        }
        catch (const std::exception& exception)
        {
            sendResponse(clientFd, 400, "Bad Request", {{"ok", false}, {"error", exception.what()}});
        }
        return;
    }

    if (path == "/api/v1/rf/rename" && method == "POST")
    {
        const auto headerEnd = request.find("\r\n\r\n");
        const std::string body =
            headerEnd == std::string::npos
                ? std::string{}
                : request.substr(headerEnd + 4);

        try
        {
            const auto json =
                nlohmann::json::parse(body);

            const std::string deviceId =
                json.at("device").get<std::string>();

            const std::string newName =
                json.at("name").get<std::string>();

            if (deviceId.empty() ||
                deviceId.find("..") != std::string::npos ||
                deviceId.find('/') != std::string::npos ||
                deviceId.find('\\') != std::string::npos)
            {
                sendResponse(
                    clientFd,
                    400,
                    "Bad Request",
                    {
                        {"ok", false},
                        {"error", "Invalid RF device id"}
                    });
                return;
            }

            if (newName.empty() ||
                newName.size() > 120 ||
                newName.find('\r') != std::string::npos ||
                newName.find('\n') != std::string::npos)
            {
                sendResponse(
                    clientFd,
                    400,
                    "Bad Request",
                    {
                        {"ok", false},
                        {"error", "RF device name must contain 1 to 120 characters"}
                    });
                return;
            }

            std::lock_guard<std::mutex> lock(
                commandMutex
            );

            RFDatabase database;
            RFDevice device;

            if (!database.loadPowerDevice(
                    deviceId,
                    device))
            {
                sendResponse(
                    clientFd,
                    404,
                    "Not Found",
                    {
                        {"ok", false},
                        {"error", "RF power device not found"},
                        {"device", deviceId}
                    });
                return;
            }

            // Keep device.name unchanged: it is the immutable .rf record ID.
            // Only device.deviceName is the user-facing display name.
            device.deviceName = newName;

            if (!database.savePowerDevice(
                    device,
                    true))
            {
                sendResponse(
                    clientFd,
                    500,
                    "Internal Server Error",
                    {
                        {"ok", false},
                        {"error", "Failed to save renamed RF power device"},
                        {"device", deviceId}
                    });
                return;
            }

            sendResponse(
                clientFd,
                200,
                "OK",
                {
                    {"ok", true},
                    {"device", deviceId},
                    {"name", newName},
                    {"message", "RF power device renamed"}
                });
        }
        catch (const std::exception& exception)
        {
            sendResponse(
                clientFd,
                400,
                "Bad Request",
                {
                    {"ok", false},
                    {"error", exception.what()}
                });
        }

        return;
    }

    if (path == "/api/v1/rf/delete" && method == "POST")
    {
        const auto headerEnd = request.find("\r\n\r\n");
        const std::string body =
            headerEnd == std::string::npos
                ? std::string{}
                : request.substr(headerEnd + 4);

        try
        {
            const auto json = nlohmann::json::parse(body);
            const std::string deviceId =
                json.at("device").get<std::string>();

            RFDatabase database;
            RFDevice existing;

            if (!database.loadPowerDevice(deviceId, existing))
            {
                sendResponse(
                    clientFd,
                    404,
                    "Not Found",
                    {
                        {"ok", false},
                        {"error", "RF power device not found"},
                        {"device", deviceId}
                    });
                return;
            }

            if (!database.deletePowerDevice(deviceId))
            {
                sendResponse(
                    clientFd,
                    500,
                    "Internal Server Error",
                    {
                        {"ok", false},
                        {"error", "Failed to delete RF power device"},
                        {"device", deviceId}
                    });
                return;
            }

            sendResponse(
                clientFd,
                200,
                "OK",
                {
                    {"ok", true},
                    {"device", deviceId},
                    {"message", "RF power device deleted"}
                });
        }
        catch (const std::exception& exception)
        {
            sendResponse(
                clientFd,
                400,
                "Bad Request",
                {
                    {"ok", false},
                    {"error", exception.what()}
                });
        }

        return;
    }

    if (path == "/api/v1/rf/group" && method == "POST")
    {
        const auto headerEnd = request.find("\r\n\r\n");
        const std::string body =
            headerEnd == std::string::npos
                ? std::string{}
                : request.substr(headerEnd + 4);

        try
        {
            const auto json = nlohmann::json::parse(body);
            const std::string action = json.at("action").get<std::string>();

            if (action != "on" && action != "off")
            {
                sendResponse(
                    clientFd,
                    400,
                    "Bad Request",
                    {
                        {"ok", false},
                        {"error", "Action must be on or off"}
                    });
                return;
            }

            if (!json.contains("devices") ||
                !json.at("devices").is_array() ||
                json.at("devices").empty())
            {
                sendResponse(
                    clientFd,
                    400,
                    "Bad Request",
                    {
                        {"ok", false},
                        {"error", "devices must be a non-empty array"}
                    });
                return;
            }

            nlohmann::json results = nlohmann::json::array();
            bool allSucceeded = true;
            RFCommandService rfService;
            std::lock_guard<std::mutex> lock(commandMutex);

            for (const auto& entry : json.at("devices"))
            {
                const std::string device = entry.get<std::string>();

                std::string error;
                const bool succeeded =
                    rfService.send(device, action, error);

                allSucceeded = allSucceeded && succeeded;

                results.push_back({
                    {"device", device},
                    {"ok", succeeded},
                    {"error", error}
                });
            }

            sendResponse(
                clientFd,
                allSucceeded ? 200 : 500,
                allSucceeded ? "OK" : "Internal Server Error",
                {
                    {"ok", allSucceeded},
                    {"action", action},
                    {"results", results}
                });
        }
        catch (const std::exception& exception)
        {
            sendResponse(
                clientFd,
                400,
                "Bad Request",
                {
                    {"ok", false},
                    {"error", exception.what()}
                });
        }
        return;
    }

    if (path == "/api/v1/rf/all" && method == "POST")
    {
        const auto headerEnd = request.find("\r\n\r\n");
        const std::string body = headerEnd == std::string::npos ? std::string{} : request.substr(headerEnd + 4);
        try
        {
            const auto json = nlohmann::json::parse(body);
            const std::string action = json.at("action").get<std::string>();
            if (action != "on" && action != "off")
            {
                sendResponse(clientFd, 400, "Bad Request", {{"ok", false}, {"error", "Action must be on or off"}});
                return;
            }

            nlohmann::json results = nlohmann::json::array();
            bool allSucceeded = true;
            RFDatabase database;
            RFCommandService rfService;
            std::lock_guard<std::mutex> lock(commandMutex);

            for (const RFDevice& device : database.listPowerDevices())
            {
                std::string error;
                const bool succeeded = rfService.send(device.name, action, error);
                allSucceeded = allSucceeded && succeeded;
                results.push_back({
                    {"device", device.name},
                    {"name", device.deviceName.empty() ? device.name : device.deviceName},
                    {"ok", succeeded},
                    {"error", error}
                });
            }

            sendResponse(
                clientFd,
                allSucceeded ? 200 : 500,
                allSucceeded ? "OK" : "Internal Server Error",
                {{"ok", allSucceeded}, {"action", action}, {"results", results}});
        }
        catch (const std::exception& exception)
        {
            sendResponse(clientFd, 400, "Bad Request", {{"ok", false}, {"error", exception.what()}});
        }
        return;
    }

    sendResponse(clientFd, 404, "Not Found", {{"error", "Endpoint not found"}});
}
