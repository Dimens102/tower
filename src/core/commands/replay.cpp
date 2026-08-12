#include "core/commands/command_handlers.h"

#include <chrono>
#include <iostream>
#include <string>
#include <thread>

#include "devices/device.h"
#include "devices/device_database.h"
#include "devices/ir/ir_code.h"
#include "devices/ir/ir_database.h"
#include "devices/ir/ir_sender.h"
#include "devices/ir/ir_transmitter.h"
#include "devices/ir/ir_transmitter_database.h"

int runReplayCommand(int argc, char* argv[])
{
     if (argc < 5)
     {
          std::cerr
              << "Usage: tower replay <device-name> <command-name> <transmitter-name> "
              << "[--repeat <count>] [--delay-ms <milliseconds>] [--carrier-khz <kHz>] [--duty <percent>]\n";
          return 1;
     }

     std::string deviceName = argv[2];
     std::string commandName = argv[3];
     std::string transmitterName = argv[4];
     unsigned int repeatCount = 1;
     unsigned int repeatDelayMs = 0;
     unsigned int carrierOverrideKhz = 0;
     unsigned int dutyPercent = 0;

     for (int index = 5; index < argc; ++index)
     {
          const std::string option = argv[index];

          auto readUnsigned = [&](const char* optionName, unsigned int& value) -> bool
          {
               if (index + 1 >= argc)
               {
                    std::cerr << "Missing value for " << optionName << "\n";
                    return false;
               }

               try
               {
                    const std::string text = argv[++index];
                    std::size_t consumed = 0;
                    const unsigned long parsed = std::stoul(text, &consumed, 10);
                    if (consumed != text.size())
                    {
                         throw std::invalid_argument("trailing characters");
                    }
                    value = static_cast<unsigned int>(parsed);
               }
               catch (...)
               {
                    std::cerr << "Invalid value for " << optionName << "\n";
                    return false;
               }

               return true;
          };

          if (option == "--repeat")
          {
               if (!readUnsigned("--repeat", repeatCount) || repeatCount < 1)
               {
                    std::cerr << "--repeat must be at least 1\n";
                    return 1;
               }
          }
          else if (option == "--delay-ms")
          {
               if (!readUnsigned("--delay-ms", repeatDelayMs))
               {
                    return 1;
               }
          }
          else if (option == "--carrier-khz")
          {
               if (!readUnsigned("--carrier-khz", carrierOverrideKhz) ||
                   carrierOverrideKhz < 20 || carrierOverrideKhz > 60)
               {
                    std::cerr << "--carrier-khz must be between 20 and 60\n";
                    return 1;
               }
          }
          else if (option == "--duty")
          {
               if (!readUnsigned("--duty", dutyPercent) ||
                   dutyPercent < 10 || dutyPercent > 60)
               {
                    std::cerr << "--duty must be between 10 and 60 percent\n";
                    return 1;
               }
          }
          else
          {
               std::cerr << "Unknown replay option: " << option << "\n";
               return 1;
          }
     }

     IRDatabase irDatabase;
     IRCode code;

     if (!irDatabase.load(deviceName, commandName, code))
     {
          return 1;
     }

     Device device;
     DeviceDatabase deviceDatabase;
     if (deviceDatabase.deviceExists(deviceName))
          deviceDatabase.loadDevice(deviceName, device);

     const unsigned int effectiveCarrierKhz = carrierOverrideKhz > 0
          ? carrierOverrideKhz
          : (device.irProfile.carrierKhz > 0 ? device.irProfile.carrierKhz : code.carrierKhz);
     unsigned int storedDutyPercent = device.irProfile.dutyPercent;
     const auto transmitterDuty = device.irProfile.transmitterDutyPercent.find(transmitterName);
     if (transmitterDuty != device.irProfile.transmitterDutyPercent.end())
          storedDutyPercent = transmitterDuty->second;

     const unsigned int effectiveDutyPercent = dutyPercent > 0
          ? dutyPercent
          : storedDutyPercent;

     if (carrierOverrideKhz > 0)
          std::cout << "Carrier override: " << code.carrierKhz << " -> "
                    << carrierOverrideKhz << " kHz\n";

     IRTransmitterDatabase transmitterDatabase;
     IRTransmitter transmitter;

     if (!transmitterDatabase.load(transmitterName, transmitter))
     {
          std::cerr << "Failed to load IR transmitter: " << transmitterName << "\n";
          return 1;
     }

     IRSender sender;

     std::cout
         << "Replay pattern: "
         << repeatCount
         << (repeatCount == 1 ? " frame" : " frames");

     if (repeatCount > 1)
     {
          std::cout << ", " << repeatDelayMs << " ms inter-frame delay";
     }

     if (effectiveDutyPercent > 0)
     {
          std::cout << ", " << effectiveDutyPercent << "% carrier duty";
          if (dutyPercent > 0)
               std::cout << " CLI override";
          else if (transmitterDuty != device.irProfile.transmitterDutyPercent.end())
               std::cout << " transmitter override";
          else
               std::cout << " stored profile";
     }

     std::cout << "\n";

     for (unsigned int transmission = 0; transmission < repeatCount; ++transmission)
     {
          if (!sender.send(code, transmitter, effectiveDutyPercent, effectiveCarrierKhz))
          {
               return 1;
          }

          if (transmission + 1 < repeatCount && repeatDelayMs > 0)
          {
               std::this_thread::sleep_for(
                   std::chrono::milliseconds(repeatDelayMs));
          }
     }

     std::cout << "IR replay complete.\n";
     return 0;
}
