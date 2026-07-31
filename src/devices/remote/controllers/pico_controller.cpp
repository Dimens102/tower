#include "devices/remote/controllers/pico_controller.h"

#include <arpa/inet.h>
#include <cerrno>
#include <chrono>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <sstream>
#include <sys/socket.h>
#include <unistd.h>
#include <utility>

namespace tower::remote::controllers
{

namespace
{

constexpr std::size_t firstIrOutput = 1;
constexpr std::size_t lastIrOutput = 6;
constexpr unsigned int maximumDurationMicroseconds = 100000;
constexpr int connectTimeoutMilliseconds = 2500;
constexpr int responseTimeoutMilliseconds = 5000;

bool waitFor(
    int socketFd,
    short events,
    int timeoutMilliseconds)
{
    pollfd descriptor{};
    descriptor.fd = socketFd;
    descriptor.events = events;

    while (true)
    {
        const int result =
            poll(&descriptor, 1, timeoutMilliseconds);

        if (result > 0)
        {
            return
                (descriptor.revents & events) != 0 &&
                (descriptor.revents &
                    (POLLERR | POLLHUP | POLLNVAL)) == 0;
        }

        if (result == 0)
        {
            return false;
        }

        if (errno != EINTR)
        {
            return false;
        }
    }
}

} // namespace

PicoController::PicoController(
    std::string host,
    std::uint16_t port)
    : m_host(std::move(host)),
      m_port(port)
{
}

bool PicoController::initialize()
{
    std::string response;
    m_available =
        transact("PING", response) &&
        response == "PONG";

    return m_available;
}

bool PicoController::update()
{
    return initialize();
}

bool PicoController::available() const
{
    return m_available;
}

const std::string& PicoController::name() const
{
    return m_name;
}

bool PicoController::sendIrRaw(
    std::size_t output,
    const std::vector<unsigned int>& durations)
{
    if (!m_available ||
        output < firstIrOutput ||
        output > lastIrOutput ||
        durations.empty())
    {
        return false;
    }

    std::ostringstream command;
    command << "SEND " << output << " ";

    for (std::size_t index = 0;
         index < durations.size();
         ++index)
    {
        const unsigned int duration = durations[index];

        if (duration == 0 ||
            duration > maximumDurationMicroseconds)
        {
            return false;
        }

        if (index > 0)
        {
            command << ",";
        }

        command << duration;
    }

    std::string response;
    const std::string expected =
        "OK SEND " + std::to_string(output);

    return transact(command.str(), response) &&
        response == expected;
}

const std::string& PicoController::host() const
{
    return m_host;
}

const std::string& PicoController::lastResponse() const
{
    return m_lastResponse;
}

bool PicoController::transact(
    const std::string& command,
    std::string& response)
{
    response.clear();
    m_lastResponse.clear();

    int socketFd = -1;

    if (!connectSocket(socketFd))
    {
        m_available = false;
        return false;
    }

    const bool success =
        writeAll(socketFd, command + "\n") &&
        readLine(socketFd, response);

    close(socketFd);

    if (!success)
    {
        m_available = false;
        return false;
    }

    m_lastResponse = response;
    return true;
}

bool PicoController::connectSocket(int& socketFd) const
{
    socketFd = socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC, 0);

    if (socketFd < 0)
    {
        return false;
    }

    const int originalFlags = fcntl(socketFd, F_GETFL, 0);

    if (originalFlags < 0 ||
        fcntl(socketFd, F_SETFL, originalFlags | O_NONBLOCK) != 0)
    {
        close(socketFd);
        socketFd = -1;
        return false;
    }

    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_port = htons(m_port);

    if (inet_pton(
            AF_INET,
            m_host.c_str(),
            &address.sin_addr) != 1)
    {
        close(socketFd);
        socketFd = -1;
        return false;
    }

    const int result = connect(
        socketFd,
        reinterpret_cast<sockaddr*>(&address),
        sizeof(address));

    if (result != 0)
    {
        if (errno != EINPROGRESS ||
            !waitFor(
                socketFd,
                POLLOUT,
                connectTimeoutMilliseconds))
        {
            close(socketFd);
            socketFd = -1;
            return false;
        }

        int socketError = 0;
        socklen_t errorLength = sizeof(socketError);

        if (getsockopt(
                socketFd,
                SOL_SOCKET,
                SO_ERROR,
                &socketError,
                &errorLength) != 0 ||
            socketError != 0)
        {
            close(socketFd);
            socketFd = -1;
            return false;
        }
    }

    return true;
}

bool PicoController::writeAll(
    int socketFd,
    const std::string& data) const
{
    std::size_t written = 0;

    while (written < data.size())
    {
        const ssize_t result = send(
            socketFd,
            data.data() + written,
            data.size() - written,
            MSG_NOSIGNAL);

        if (result > 0)
        {
            written += static_cast<std::size_t>(result);
            continue;
        }

        if (result < 0 &&
            errno != EAGAIN &&
            errno != EWOULDBLOCK &&
            errno != EINTR)
        {
            return false;
        }

        if (!waitFor(
                socketFd,
                POLLOUT,
                responseTimeoutMilliseconds))
        {
            return false;
        }
    }

    return true;
}

bool PicoController::readLine(
    int socketFd,
    std::string& line) const
{
    line.clear();

    const auto deadline =
        std::chrono::steady_clock::now() +
        std::chrono::milliseconds(
            responseTimeoutMilliseconds);

    while (std::chrono::steady_clock::now() < deadline)
    {
        const auto remaining =
            std::chrono::duration_cast<std::chrono::milliseconds>(
                deadline - std::chrono::steady_clock::now());

        if (!waitFor(
                socketFd,
                POLLIN,
                static_cast<int>(remaining.count())))
        {
            return false;
        }

        char value = '\0';
        const ssize_t received =
            recv(socketFd, &value, 1, 0);

        if (received == 0)
        {
            return false;
        }

        if (received < 0)
        {
            if (errno == EINTR ||
                errno == EAGAIN ||
                errno == EWOULDBLOCK)
            {
                continue;
            }

            return false;
        }

        if (value == '\n')
        {
            return true;
        }

        if (value != '\r')
        {
            line.push_back(value);
        }

        if (line.size() > 1024)
        {
            return false;
        }
    }

    return false;
}

} // namespace tower::remote::controllers
