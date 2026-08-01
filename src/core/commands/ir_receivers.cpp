#include "core/commands/command_handlers.h"

#include "devices/ir/ir_receiver_array.h"

#include <iomanip>
#include <iostream>
#include <vector>

int runIRReceiversCommand()
{
    const IRReceiverArray array;
    const std::vector<IRReceiverStatus> receivers = array.discover();

    std::cout
        << "IR receiver array\n\n"
        << std::left
        << std::setw(6) << "GPIO"
        << std::setw(12) << "Receiver"
        << std::setw(7) << "kHz"
        << std::setw(10) << "Position"
        << "Device\n"
        << std::setw(6) << "----"
        << std::setw(12) << "---------"
        << std::setw(7) << "---"
        << std::setw(10) << "--------"
        << "------\n";

    bool allAvailable = true;

    for (const IRReceiverStatus& status : receivers)
    {
        std::cout
            << std::setw(6) << status.receiver.gpio
            << std::setw(12) << status.receiver.model
            << std::setw(7) << status.receiver.nominalCarrierKhz
            << std::setw(10) << status.receiver.position
            << (status.available() ? status.lircDevice : "MISSING")
            << "\n";

        allAvailable = allAvailable && status.available();
    }

    std::cout << "\n";

    if (!allAvailable)
    {
        std::cerr << "One or more IR receivers could not be resolved.\n";
        return 1;
    }

    std::cout << "All 6 IR receivers are available.\n";
    return 0;
}
