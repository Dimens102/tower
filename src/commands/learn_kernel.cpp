#include "commands/command_handlers.h"

#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <string>

#include "ir/ir_kernel_receiver.h"

int runLearnKernelCommand()
{
        std::string protocol;

        std::cout << "Protocol to enable: ";
        std::getline(std::cin, protocol);

        if (protocol.empty())
        {
                std::cerr << "Protocol cannot be empty.\n";
                return 1;
        }

        std::string command =
                "ir-keytable -s rc2 -p " + protocol;

        if (std::system(command.c_str()) != 0)
        {
                std::cerr << "Failed to enable protocol: "
                          << protocol
                          << "\n";
                return 1;
        }

        IRKernelReceiver receiver;
        IRDecodedCode code;

        if (!receiver.receive(
                "/dev/input/event0",
                protocol,
                code))
        {
                return 1;
        }

        std::cout << "Protocol: "
                  << code.protocol
                  << "\n";

        std::cout << "Scancode: 0x"
                  << std::hex
                  << code.scancode
                  << std::dec
                  << "\n";

        return 0;
}
