#include "core/service/ExecutionDisplay.h"

#include <mutex>
#include <utility>

namespace
{
std::mutex handlerMutex;
ExecutionDisplay::Handler displayHandler;
}

void ExecutionDisplay::setHandler(Handler handler)
{
    std::lock_guard<std::mutex> lock(handlerMutex);
    displayHandler = std::move(handler);
}

void ExecutionDisplay::clearHandler()
{
    std::lock_guard<std::mutex> lock(handlerMutex);
    displayHandler = {};
}

void ExecutionDisplay::publish(
    const ExecutionDisplayNotification& notification)
{
    Handler handler;
    {
        std::lock_guard<std::mutex> lock(handlerMutex);
        handler = displayHandler;
    }

    if (handler)
    {
        handler(notification);
    }
}
