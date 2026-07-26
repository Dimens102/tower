#include "core/commands/command_handlers.h"

#include <iostream>
#include <string>

#include "devices/rf/rf_database.h"
#include "devices/rf/rf_sender.h"

int runSendCommand(int argc, char* argv[])
{
     if (argc < 4)
     {
          std::cerr << "Usage: tower send <device-name> <on|off>\n";
          return 1;
     }

     std::string deviceName = argv[2];
     std::string action = argv[3];

     bool turnOn;

     if (action == "on")
     {
          turnOn = true;
     }
     else if (action == "off")
     {
          turnOn = false;
     }
     else
     {
          std::cerr << "Action must be: on or off\n";
          return 1;
     }

     RFDatabase database;
     RFDevice device;

     if (!database.loadPowerDevice(deviceName, device))
     {
          return 1;
     }

     RFSender sender;

     if (!sender.send(device, turnOn))
     {
          return 1;
     }

     std::cout << "RF send complete.\n";
     return 0;
}
