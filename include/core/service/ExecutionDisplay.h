#pragma once

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
};

class ExecutionDisplay
{
public:
    using Handler =
        std::function<void(const ExecutionDisplayNotification&)>;

    static void setHandler(Handler handler);
    static void clearHandler();
    static void publish(
        const ExecutionDisplayNotification& notification);
};
