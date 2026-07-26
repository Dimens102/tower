#include "core/commands/command_handlers.h"

#include <iostream>
#include <string>

#include "devices/ir/ir_code.h"
#include "devices/ir/ir_database.h"
#include "devices/ir/ir_receiver.h"

int runLearnCommand(int argc, char* argv[])
{
     if (argc < 4)
     {
          std::cerr << "Usage: tower learn <device-name> <command-name>\n";
          return 1;
     }

     std::string deviceName = argv[2];
     std::string commandName = argv[3];

     IRReceiver receiver;

     if (!receiver.initialize(18))
     {
          return 1;
     }

     IRCode code;

     if (!receiver.receive(code))
     {
          receiver.shutdown();
          return 1;
     }

     receiver.shutdown();

     code.device = deviceName;
     code.command = commandName;

     IRDatabase database;

     if (!database.save(code.device, code.command, code))
     {
          return 1;
     }

     std::cout << "IR code captured and saved.\n";

     return 0;
}
