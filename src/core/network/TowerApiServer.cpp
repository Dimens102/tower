#include "core/network/TowerApiServer.h"

#include "devices/rf/rf_database.h"
#include "nlohmann/json.hpp"
#include "version.h"

#include <arpa/inet.h>
#include <cerrno>
#include <cstring>
#include <iostream>
#include <limits.h>
#include <mutex>
#include <netinet/in.h>
#include <spawn.h>
#include <sstream>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

extern char** environ;

namespace
{
std::mutex rfMutex;

bool runTowerSendCommand(
    const std::string& device,
    const std::string& action,
    std::string& error)
{
    if (action != "on" && action != "off")
    {
        error = "Action must be on or off";
        return false;
    }

    RFDatabase database;
    bool knownDevice = false;
    for (const RFDevice& definition : database.listPowerDevices())
    {
        if (definition.name == device)
        {
            knownDevice = true;
            break;
        }
    }
    if (!knownDevice)
    {
        error = "RF device not found";
        return false;
    }

    char executable[PATH_MAX + 1]{};
    const ssize_t length =
        ::readlink("/proc/self/exe", executable, PATH_MAX);
    if (length <= 0)
    {
        error = "Could not resolve Tower executable";
        return false;
    }
    executable[length] = '\0';

    char* arguments[] = {
        executable,
        const_cast<char*>("send"),
        const_cast<char*>(device.c_str()),
        const_cast<char*>(action.c_str()),
        nullptr
    };

    pid_t child = -1;
    const int spawnResult =
        ::posix_spawn(
            &child,
            executable,
            nullptr,
            nullptr,
            arguments,
            environ);
    if (spawnResult != 0)
    {
        error = "Could not start tower send: " +
            std::string(std::strerror(spawnResult));
        return false;
    }

    int status = 0;
    while (::waitpid(child, &status, 0) < 0)
    {
        if (errno == EINTR)
        {
            continue;
        }
        error = "Could not wait for tower send";
        return false;
    }

    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0)
    {
        error = "tower send failed";
        return false;
    }

    error.clear();
    return true;
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
                {"actions", {"on", "off"}}
            });
        }
        sendResponse(clientFd, 200, "OK", {{"devices", result}});
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
            std::lock_guard<std::mutex> lock(rfMutex);
            if (!runTowerSendCommand(device, action, error))
            {
                sendResponse(clientFd, 400, "Bad Request", {{"ok", false}, {"error", error}});
                return;
            }
            sendResponse(clientFd, 200, "OK", {{"ok", true}, {"device", device}, {"action", action}});
        }
        catch (const std::exception& exception)
        {
            sendResponse(clientFd, 400, "Bad Request", {{"ok", false}, {"error", exception.what()}});
        }
        return;
    }

    sendResponse(clientFd, 404, "Not Found", {{"error", "Endpoint not found"}});
}
