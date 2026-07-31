#include "devices/ir/ir_sender.h"
#include "devices/ir/ir_runtime_database.h"
#include "devices/remote/controllers/pico_controller.h"

#include <cstdlib>
#include <fstream>
#include <iostream>
#include <sstream>

bool IRSender::send(const IRCode& code, const IRTransmitter& transmitter)
{
    if (transmitter.controller == "tower-pico")
    {
        return sendViaPico(code, transmitter);
    }

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

bool IRSender::sendViaPico(
    const IRCode& code,
    const IRTransmitter& transmitter)
{
    if (code.protocol != "raw")
    {
        std::cerr
            << "Pico IR transmission currently requires raw pulse data.\n";
        return false;
    }

    if (transmitter.output < 1 || transmitter.output > 6)
    {
        std::cerr
            << "Invalid Pico output "
            << transmitter.output
            << " for "
            << transmitter.name
            << ". Expected 1 through 6.\n";
        return false;
    }

    tower::remote::controllers::PicoController pico;

    if (!pico.initialize())
    {
        std::cerr
            << "Tower Pico did not respond at "
            << pico.host()
            << ":42101.\n";
        return false;
    }

    std::cout
        << "Sending RAW on "
        << transmitter.name
        << " via Tower Pico "
        << pico.host()
        << " output "
        << transmitter.output
        << "\n";

    if (!pico.sendIrRaw(
            static_cast<std::size_t>(transmitter.output),
            code.pulses))
    {
        std::cerr
            << "Tower Pico rejected or did not confirm the IR command";

        if (!pico.lastResponse().empty())
        {
            std::cerr << ": " << pico.lastResponse();
        }

        std::cerr << "\n";
        return false;
    }

    return true;
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
