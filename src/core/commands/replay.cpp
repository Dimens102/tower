#include "core/commands/command_handlers.h"

#include <iostream>
#include <string>

#include "devices/ir/ir_code.h"
#include "devices/ir/ir_database.h"
#include "devices/ir/ir_sender.h"
#include "devices/ir/ir_transmitter.h"
#include "devices/ir/ir_transmitter_database.h"

int runReplayCommand(int argc, char* argv[])
{
     if (argc < 5)
     {
          std::cerr << "Usage: tower replay <device-name> <command-name> <transmitter-name>\n";
          return 1;
     }

     std::string deviceName = argv[2];
     std::string commandName = argv[3];
     std::string transmitterName = argv[4];

     IRDatabase irDatabase;
     IRCode code;

     if (!irDatabase.load(deviceName, commandName, code))
     {
          return 1;
     }

     IRTransmitterDatabase transmitterDatabase;
     IRTransmitter transmitter;

     if (!transmitterDatabase.load(transmitterName, transmitter))
     {
          std::cerr << "Failed to load IR transmitter: " << transmitterName << "\n";
          return 1;
     }

     IRSender sender;

     if (!sender.send(code, transmitter))
     {
          return 1;
     }

     std::cout << "IR replay complete.\n";
     return 0;
}
