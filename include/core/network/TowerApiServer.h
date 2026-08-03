#pragma once

#include <atomic>
#include <cstdint>
#include <string>
#include <thread>

class TowerApiServer
{
public:
    TowerApiServer();
    ~TowerApiServer();

    bool start(std::uint16_t port, const std::string& token);
    void stop();

private:
    void run();
    void handleClient(int clientFd);

    std::atomic<bool> running_{false};
    int listenFd_ = -1;
    std::string token_;
    std::thread thread_;
};
