#include "core/service/ExecutionDisplay.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <mutex>
#include <utility>

namespace
{
std::mutex handlerMutex;
ExecutionDisplay::Handler displayHandler;
thread_local int liveSequenceDepth = 0;

std::string centeredLine(const std::string& value)
{
    constexpr std::size_t width = 20;
    const std::string fitted = value.substr(0, width);
    return std::string((width - fitted.size()) / 2, ' ') + fitted;
}

std::size_t bestTitleSplit(const std::string& value)
{
    const std::size_t maximum = std::min<std::size_t>(20, value.size() - 1);
    const std::size_t minimum = value.size() > 20 ? value.size() - 20 : 1;
    std::size_t best = maximum;
    int bestScore = 100000;
    for (std::size_t index = minimum; index <= maximum; ++index)
    {
        const bool boundary =
            value[index] == ' ' || value[index] == '-' ||
            (std::isupper(static_cast<unsigned char>(value[index])) &&
             std::islower(static_cast<unsigned char>(value[index - 1])));
        const int balance = std::abs(
            static_cast<int>(index) -
            static_cast<int>(value.size() - index));
        const int score = balance + (boundary ? 0 : 100);
        if (score < bestScore)
        {
            best = index;
            bestScore = score;
        }
    }
    return best;
}
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

bool ExecutionDisplay::beginLiveSequence()
{
    const bool topLevel = liveSequenceDepth == 0;
    ++liveSequenceDepth;
    return topLevel;
}

void ExecutionDisplay::endLiveSequence()
{
    if (liveSequenceDepth > 0)
    {
        --liveSequenceDepth;
    }
}

void ExecutionDisplay::publishCompletion(const std::string& title, bool ok)
{
    ExecutionDisplayNotification notification;
    notification.title = title;
    notification.target = ok ? "Done" : "Failed";
    notification.ok = ok;
    notification.durationSeconds = 1;
    notification.durationMilliseconds = 1500;
    notification.replaceCurrent = true;
    publish(notification);
}

std::array<std::string, 4> ExecutionDisplay::completionLines(
    const std::string& title,
    const std::string& status)
{
    std::array<std::string, 4> lines{};
    std::string fittedTitle = title.substr(0, 40);
    if (fittedTitle.size() <= 20)
    {
        lines[1] = centeredLine(fittedTitle);
    }
    else
    {
        const std::size_t split = bestTitleSplit(fittedTitle);
        std::string first = fittedTitle.substr(0, split);
        std::string second = fittedTitle.substr(split);
        while (!first.empty() && (first.back() == ' ' || first.back() == '-'))
        {
            first.pop_back();
        }
        while (!second.empty() && (second.front() == ' ' || second.front() == '-'))
        {
            second.erase(second.begin());
        }
        lines[0] = centeredLine(first);
        lines[1] = centeredLine(second);
    }
    lines[2] = centeredLine(status);
    return lines;
}

void ExecutionDisplay::publish(
    const ExecutionDisplayNotification& notification)
{
    ExecutionDisplayNotification prepared = notification;
    prepared.liveSequenceItem = liveSequenceDepth > 0;
    Handler handler;
    {
        std::lock_guard<std::mutex> lock(handlerMutex);
        handler = displayHandler;
    }

    if (handler)
    {
        handler(prepared);
    }
}

ExecutionDisplaySequence::ExecutionDisplaySequence()
    : topLevel_(ExecutionDisplay::beginLiveSequence())
{
}

ExecutionDisplaySequence::~ExecutionDisplaySequence()
{
    ExecutionDisplay::endLiveSequence();
}
