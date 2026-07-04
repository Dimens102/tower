#include "ir/ir_sender.h"

#include <cstdlib>
#include <iostream>
#include <sstream>

bool IRSender::send(const IRCode& code, const IRTransmitter& transmitter)
{
     if (transmitter.lircDevice.empty())
     {
          std::cerr << "No lirc_device configured for transmitter: "
                    << transmitter.name << "\n";
          return false;
     }

     if (code.protocol == "nec")
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

     std::cerr << "Unsupported IR protocol for lirc sender: "
               << code.protocol << "\n";
     return false;
}
