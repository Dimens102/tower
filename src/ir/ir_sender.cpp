#include "ir/ir_sender.h"
#include "ir/ir_runtime_database.h"

#include <cstdlib>
#include <fstream>
#include <iostream>
#include <sstream>

bool IRSender::send(const IRCode& code, const IRTransmitter& transmitter)
{
    IRRuntimeDatabase runtimeDatabase;

    auto lircDevice =
        runtimeDatabase.getLircDeviceForGpio(transmitter.gpio);

    if (!lircDevice)
    {
        std::cerr << "No runtime LIRC device found for GPIO "
                  << transmitter.gpio
                  << " (" << transmitter.name << ")\n";

        return false;
    }

    std::cout << "Resolved GPIO "
              << transmitter.gpio
              << " -> "
              << *lircDevice
              << "\n";

    if (code.protocol == "raw")
    {
        return sendRaw(code, transmitter, *lircDevice);
    }

    if (code.protocol == "nec")
    {
        return sendNEC(code, transmitter, *lircDevice);
    }

    std::cerr << "Unsupported IR protocol: "
              << code.protocol << "\n";

    return false;
}

bool IRSender::sendNEC(const IRCode& code,
                       const IRTransmitter& transmitter,
                       const std::string& lircDevice)
{
    std::ostringstream command;

    command << "sudo ir-ctl"
            << " -d " << lircDevice
            << " -S nec:" << code.command;

    std::cout << "Sending NEC on "
              << transmitter.name
              << " via "
              << lircDevice
              << "\n";

    return std::system(command.str().c_str()) == 0;
}

bool IRSender::sendRaw(const IRCode& code,
                       const IRTransmitter& transmitter,
                       const std::string& lircDevice)
{
    const std::string tempFile = "/tmp/tower-ir-send.txt";

    std::ofstream out(tempFile);

    if (!out)
    {
        std::cerr << "Failed to create temporary IR file.\n";
        return false;
    }

    for (size_t i = 0; i < code.pulses.size(); ++i)
    {
        if (i > 0)
        {
            out << " ";
        }

        if ((i % 2) == 0)
        {
            out << "+";
        }
        else
        {
            out << "-";
        }

        out << code.pulses[i];
    }

    out << "\n";
    out.close();

    std::ostringstream command;

    command << "sudo ir-ctl"
            << " -d " << lircDevice
            << " --send=" << tempFile;

    std::cout << "Sending RAW on "
              << transmitter.name
              << " via "
              << lircDevice
              << "\n";

    return std::system(command.str().c_str()) == 0;
}
