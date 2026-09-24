#include "core/service/ExecutionDisplay.h"

#include <cassert>
#include <vector>

int main()
{
    std::vector<ExecutionDisplayNotification> received;
    ExecutionDisplay::setHandler(
        [&](const ExecutionDisplayNotification& notification)
        {
            received.push_back(notification);
        });

    ExecutionDisplay::publish({"Direct", "Lamp", "On", "OK", true, 5});
    assert(!received.back().liveSequenceItem);

    {
        ExecutionDisplaySequence outer;
        assert(outer.topLevel());
        ExecutionDisplay::publish({"RF command", "Lamp 1", "On", "OK", true, 5});
        assert(received.back().liveSequenceItem);

        ExecutionDisplaySequence nested;
        assert(!nested.topLevel());
        ExecutionDisplay::publish({"IR command", "Denon", "Power", "OK", true, 5});
        assert(received.back().liveSequenceItem);
    }

    ExecutionDisplay::publishCompletion("Preset 1", true);
    assert(!received.back().liveSequenceItem);
    assert(received.back().replaceCurrent);
    assert(received.back().target == "Done");
    assert(received.back().durationMilliseconds == 1500);

    const auto shortCompletion =
        ExecutionDisplay::completionLines("Preset 1", "Done");
    assert(shortCompletion[0].empty());
    assert(shortCompletion[1].find("Preset 1") != std::string::npos);
    assert(shortCompletion[2].find("Done") != std::string::npos);
    assert(shortCompletion[3].empty());

    const auto longCompletion =
        ExecutionDisplay::completionLines("AirCleaningCycleStart", "Done");
    assert(longCompletion[0].find("AirCleaning") != std::string::npos);
    assert(longCompletion[1].find("CycleStart") != std::string::npos);
    assert(longCompletion[2].find("Done") != std::string::npos);
    assert(longCompletion[3].empty());

    ExecutionDisplay::clearHandler();
}
