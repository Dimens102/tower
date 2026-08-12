#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include "devices/controllers/controller.h"

namespace tower::remote::controllers
{

class PicoController : public tower::controllers::Controller
{
public:
    explicit PicoController(
        std::string host = "192.168.2.30",
        std::uint16_t port = 42101);

    bool initialize() override;
    bool update() override;

    bool available() const override;
    const std::string& name() const override;

    bool sendIrRaw(
        std::size_t output,
        unsigned int carrierKhz,
        const std::vector<unsigned int>& durations,
        unsigned int dutyPercent = 0);

    const std::string& host() const;
    const std::string& lastResponse() const;

private:
    bool transact(
        const std::string& command,
        std::string& response);
    bool connectSocket(int& socketFd) const;
    bool writeAll(int socketFd, const std::string& data) const;
    bool readLine(int socketFd, std::string& line) const;

    std::string m_name = "Tower Pico";
    std::string m_host;
    std::string m_lastResponse;
    std::uint16_t m_port;
    bool m_available = false;
};

} // namespace tower::remote::controllers
