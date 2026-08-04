#include "core/commands/command_handlers.h"
#include "core/commands/ir_learning.h"
#include "devices/device_database.h"

#include <cassert>
#include <string>

namespace
{
unsigned int calls = 0;
}

int learnIRCommand(
    const std::string& deviceName,
    const std::string& commandName,
    const std::string& description,
    double seconds,
    bool force)
{
    if (deviceName != "Non-Recorder Media Box" || commandName != "Power" ||
        description != "Toggle power" || seconds != 8.0 || force)
        return 1;

    ++calls;
    return 0;
}

int main()
{
    const int result = runLearnWizard();
    if (result != 0 || calls != 1) return 1;

    Device saved;
    DeviceDatabase database;
    assert(database.loadDevice("Non-Recorder Media Box", saved));
    assert(saved.name == "Non-Recorder Media Box");
    assert(saved.manufacturer == "KPN");
    assert(saved.remoteName == "Generic Non-Bluetooth KPN Remote");
    assert(saved.location == "Living Room");
    assert(saved.transmitter == "Tower-IR-TX-001");
    return 0;
}
