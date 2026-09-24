#pragma once

#include <array>
#include <functional>
#include <string>

struct ExecutionDisplayNotification
{
    std::string title;
    std::string target;
    std::string command;
    std::string result;
    bool ok = true;
    int durationSeconds = 5;
    int durationMilliseconds = 0;
    int repetitions = 1;
    bool liveSequenceItem = false;
    bool replaceCurrent = false;
};

class ExecutionDisplay
{
public:
    using Handler =
        std::function<void(const ExecutionDisplayNotification&)>;

    static void setHandler(Handler handler);
    static void clearHandler();
    // Returns true only for the outermost sequence on this execution thread.
    static bool beginLiveSequence();
    static void endLiveSequence();
    static void publishCompletion(const std::string& title, bool ok);
    // Formats a sequence summary for the four-line Tower LCD. A one-line
    // title uses row 2; a two-line title uses rows 1-2. Status always uses
    // row 3 so completion messages remain visually stable.
    static std::array<std::string, 4> completionLines(
        const std::string& title,
        const std::string& status);
    static void publish(
        const ExecutionDisplayNotification& notification);
};

class ExecutionDisplaySequence
{
public:
    ExecutionDisplaySequence();
    ~ExecutionDisplaySequence();
    ExecutionDisplaySequence(const ExecutionDisplaySequence&) = delete;
    ExecutionDisplaySequence& operator=(const ExecutionDisplaySequence&) = delete;
    bool topLevel() const { return topLevel_; }

private:
    bool topLevel_ = false;
};
