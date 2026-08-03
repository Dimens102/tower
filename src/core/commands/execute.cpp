#include <iostream>

#include "core/commands/command_handlers.h"
#include "core/service/CommandExecutor.h"
#include "devices/device_database.h"

int runExecuteCommand(int argc, char* argv[])
{
    if (argc < 4)
    {
        std::cerr
            << "Usage: tower execute <device-id> <command-id>\n";

        return 1;
    }

    const std::string deviceId = argv[2];
    const std::string commandId = argv[3];

    DeviceDatabase database;
    Device device;

    if (!database.loadDevice(deviceId, device))
    {
        std::cerr << "Device not found.\n";
        return 1;
    }

    if (!device.enabled)
    {
        std::cerr << "Device is disabled.\n";
        return 1;
    }

    const DeviceCommand* selectedCommand = nullptr;

    for (const DeviceCommand& command : device.commands)
    {
        if (command.id == commandId)
        {
            selectedCommand = &command;
            break;
        }
    }

    if (selectedCommand == nullptr)
    {
        std::cerr << "Command not found.\n";
        return 1;
    }

    if (!selectedCommand->enabled)
    {
        std::cerr << "Command is disabled.\n";
        return 1;
    }

    std::cout
        << "Device:             " << device.id << "\n"
        << "Command:            " << selectedCommand->id << "\n\n"
        << "Transport:          "
        << (selectedCommand->transport == TransportType::IR ? "IR" : "RF") << "\n"
        << "Transport device:   " << selectedCommand->transportDevice << "\n"
        << "Transport command:  " << selectedCommand->transportCommand << "\n"
        << "Transmitter:        " << selectedCommand->transmitter << "\n"
        << "Enabled:            "
        << (selectedCommand->enabled ? "Yes" : "No") << "\n\n";

    CommandExecutor executor;
    const CommandExecutionResult execution =
        executor.execute(*selectedCommand);

    if (!execution.succeeded())
    {
        std::cerr << execution.message << "\n";
        return 1;
    }

    std::cout << execution.message << "\n";

    return 0;
}
