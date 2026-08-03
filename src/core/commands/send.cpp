#include "core/commands/command_handlers.h"

#include <iostream>
#include <string>

#include "core/service/RFCommandService.h"

int runSendCommand(int argc, char* argv[])
{
     if (argc < 4)
     {
          std::cerr << "Usage: tower send <device-name> <on|off>\n";
          return 1;
     }

     std::string deviceName = argv[2];
     std::string action = argv[3];

     RFCommandService service;
     std::string error;
     if (!service.send(deviceName, action, error))
     {
          std::cerr << error << "\n";
          return 1;
     }

     std::cout << "RF send complete.\n";
     return 0;
}
