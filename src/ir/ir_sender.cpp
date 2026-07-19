#include "ir/ir_sender.h"

#include <cstdlib>
#include <iostream>
#include <sstream>
#include <fstream>

bool IRSender::send(const IRCode& code, const IRTransmitter& transmitter)
{
    if (transmitter.lircDevice.empty())
    {
        std::cerr << "No lirc_device configured for transmitter: "
                  << transmitter.name << "\n";
        return false;
    }

    if (code.protocol == "raw")
    {
        return sendRaw(code, transmitter);
    }

    if (code.protocol == "nec")
    {
        return sendNEC(code, transmitter);
    }

    std::cerr << "Unsupported IR protocol: "
              << code.protocol << "\n";

    return false;
}

bool IRSender::sendNEC(const IRCode& code, const IRTransmitter& transmitter)
{
    std::ostringstream command;

    command << "sudo ir-ctl"
            << " -d " << transmitter.lircDevice
            << " -S nec:" << code.command;

    std::cout << "Sending NEC on "
              << transmitter.name
              << " via "
              << transmitter.lircDevice
              << "\n";

    return std::system(command.str().c_str()) == 0;
}

bool IRSender::sendRaw(const IRCode& code, const IRTransmitter& transmitter)
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
            << " -d " << transmitter.lircDevice
            << " --send=" << tempFile;

    std::cout << "Sending RAW on "
              << transmitter.name
              << " via "
              << transmitter.lircDevice
              << "\n";

    return std::system(command.str().c_str()) == 0;
}