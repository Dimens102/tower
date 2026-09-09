#include "devices/ir/ir_sender.h"
#include "devices/ir/ir_runtime_database.h"
#include "devices/remote/controllers/pico_controller.h"

#include <algorithm>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <sstream>

bool IRSender::send(const IRCode& code, const IRTransmitter& transmitter, unsigned int dutyPercent, unsigned int carrierKhz)
{
    if (transmitter.controller == "tower-pico")
    {
        return sendViaPico(code, transmitter, dutyPercent, carrierKhz);
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

bool IRSender::sendSynchronized(
    const IRCode& code,
    const std::vector<IRTransmitter>& transmitters,
    unsigned int dutyPercent,
    unsigned int carrierOverrideKhz)
{
    constexpr unsigned int defaultCarrierKhz = 38;

    if (code.protocol != "raw" || transmitters.size() < 2)
    {
        std::cerr
            << "Synchronized Pico IR transmission requires raw pulse data "
            << "and at least two transmitters.\n";
        return false;
    }

    std::vector<std::size_t> outputs;
    for (const IRTransmitter& transmitter : transmitters)
    {
        if (transmitter.controller != "tower-pico" ||
            transmitter.output < 1 ||
            transmitter.output > 6)
        {
            std::cerr
                << "Synchronized IR output requires Tower Pico outputs 1 "
                << "through 6; invalid transmitter: "
                << transmitter.name << ".\n";
            return false;
        }

        const std::size_t output =
            static_cast<std::size_t>(transmitter.output);
        if (std::find(outputs.begin(), outputs.end(), output) == outputs.end())
        {
            outputs.push_back(output);
        }
    }

    if (outputs.size() < 2)
    {
        std::cerr
            << "Synchronized IR output resolved to fewer than two unique "
            << "Pico outputs.\n";
        return false;
    }

    const unsigned int carrierKhz = carrierOverrideKhz > 0
        ? carrierOverrideKhz
        : (code.carrierKhz == 0 ? defaultCarrierKhz : code.carrierKhz);

    tower::remote::controllers::PicoController pico;
    if (!pico.initialize())
    {
        std::cerr
            << "Tower Pico did not respond at "
            << pico.host() << ":42101.\n";
        return false;
    }

    std::cout
        << "Broadcasting one synchronized RAW frame via Tower Pico "
        << pico.host() << " on outputs ";
    for (std::size_t index = 0; index < outputs.size(); ++index)
    {
        if (index > 0)
        {
            std::cout << ",";
        }
        std::cout << outputs[index];
    }
    std::cout << " at " << carrierKhz << " kHz";
    if (dutyPercent > 0)
    {
        std::cout << " at " << dutyPercent << "% duty";
    }
    std::cout << "\n";

    if (!pico.sendIrRawSynchronized(
            outputs,
            carrierKhz,
            code.pulses,
            dutyPercent))
    {
        std::cerr
            << "Tower Pico rejected or did not confirm the synchronized IR "
            << "command";
        if (!pico.lastResponse().empty())
        {
            std::cerr << ": " << pico.lastResponse();
        }
        std::cerr << "\n";
        return false;
    }

    return true;
}

bool IRSender::sendViaPico(
    const IRCode& code,
    const IRTransmitter& transmitter,
    unsigned int dutyPercent,
    unsigned int carrierOverrideKhz)
{
    constexpr unsigned int defaultCarrierKhz = 38;

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
    const unsigned int carrierKhz = carrierOverrideKhz > 0
        ? carrierOverrideKhz
        : (code.carrierKhz == 0 ? defaultCarrierKhz : code.carrierKhz);

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
        << " at "
        << carrierKhz
        << " kHz";

    if (dutyPercent > 0)
    {
        std::cout << " at " << dutyPercent << "% duty";
    }

    std::cout << "\n";

    if (!pico.sendIrRaw(
            static_cast<std::size_t>(transmitter.output),
            carrierKhz,
            code.pulses,
            dutyPercent))
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
