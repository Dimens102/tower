#include "devices/ir/ir_database.h"

#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <string>
#include <system_error>

namespace
{
std::filesystem::path commandPath(
    const std::string& deviceName,
    const std::string& commandName)
{
     return std::filesystem::path("data") / "ir" / deviceName /
          (commandName + ".ir");
}
}

bool IRDatabase::save(const std::string& deviceName, const std::string& commandName, const IRCode& code)
{
     std::filesystem::path dir = std::filesystem::path("data") / "ir" / deviceName;
     std::filesystem::create_directories(dir);

     std::filesystem::path file = commandPath(deviceName, commandName);
     std::filesystem::path temporary = file;
     temporary += ".tmp";

     std::ofstream out(temporary);

     if (!out)
     {
          std::cerr << "Failed to open IR file for writing: " << temporary << "\n";
          return false;
     }

     out << "device=" << code.device << "\n";
     out << "command=" << code.command << "\n";
     out << "protocol=" << code.protocol << "\n";
     if (!code.decodedProtocol.empty())
     {
          out << "decoded_protocol=" << code.decodedProtocol << "\n";
          out << "address=0x" << std::uppercase << std::hex << code.address << "\n";
          out << "decoded_command=0x" << std::setw(2) << std::setfill('0')
              << code.decodedCommand << std::dec << std::setfill(' ') << "\n";
     }
     if (code.carrierKhz > 0) out << "carrier_khz=" << code.carrierKhz << "\n";
     if (code.receiverGpio > 0) out << "receiver_gpio=" << code.receiverGpio << "\n";
     if (!code.receiverModel.empty()) out << "receiver_model=" << code.receiverModel << "\n";
     if (!code.sourceCapture.empty()) out << "source_capture=" << code.sourceCapture << "\n";
     out << "pulses=";

     for (size_t i = 0; i < code.pulses.size(); ++i)
     {
          if (i > 0)
          {
               out << ",";
          }

          out << code.pulses[i];
     }

     out << "\n";

     out.close();
     if (!out)
     {
          std::filesystem::remove(temporary);
          std::cerr << "Failed while writing IR file: " << temporary << "\n";
          return false;
     }

     std::error_code error;
     std::filesystem::rename(temporary, file, error);
     if (error)
     {
          std::filesystem::remove(temporary);
          std::cerr << "Failed to install IR file: " << error.message() << "\n";
          return false;
     }

     return true;
}

bool IRDatabase::load(const std::string& deviceName, const std::string& commandName, IRCode& code)
{
     std::filesystem::path file = commandPath(deviceName, commandName);

     std::ifstream in(file);

     if (!in)
     {
          std::cerr << "Failed to open IR file for reading: " << file << "\n";
          return false;
     }

     code.pulses.clear();
     code.decodedProtocol.clear();
     code.address = 0;
     code.decodedCommand = 0;
     code.carrierKhz = 0;
     code.receiverGpio = 0;
     code.receiverModel.clear();
     code.sourceCapture.clear();

     std::string line;

     while (std::getline(in, line))
     {
          std::size_t pos = line.find('=');

          if (pos == std::string::npos)
          {
               continue;
          }

          std::string key = line.substr(0, pos);
          std::string value = line.substr(pos + 1);

          if (key == "device")
          {
               code.device = value;
          }
          else if (key == "command")
          {
               code.command = value;
          }
          else if (key == "protocol")
          {
               code.protocol = value;
          }
          else if (key == "decoded_protocol") code.decodedProtocol = value;
          else if (key == "address") code.address = static_cast<unsigned>(std::stoul(value, nullptr, 0));
          else if (key == "decoded_command") code.decodedCommand = static_cast<unsigned>(std::stoul(value, nullptr, 0));
          else if (key == "carrier_khz") code.carrierKhz = static_cast<unsigned>(std::stoul(value));
          else if (key == "receiver_gpio") code.receiverGpio = static_cast<unsigned>(std::stoul(value));
          else if (key == "receiver_model") code.receiverModel = value;
          else if (key == "source_capture") code.sourceCapture = value;
          else if (key == "pulses")
          {
               std::size_t start = 0;

               while (start < value.size())
               {
                    std::size_t comma = value.find(',', start);

                    std::string part = value.substr(start, comma - start);

                    if (!part.empty())
                    {
                         code.pulses.push_back(
                              static_cast<unsigned int>(std::stoul(part)));
                    }

                    if (comma == std::string::npos)
                    {
                         break;
                    }

                    start = comma + 1;
               }
          }
     }

     return true;
}

bool IRDatabase::exists(
    const std::string& deviceName,
    const std::string& commandName) const
{
     return std::filesystem::is_regular_file(commandPath(deviceName, commandName));
}

std::filesystem::path IRDatabase::path(
    const std::string& deviceName,
    const std::string& commandName) const
{
     return commandPath(deviceName, commandName);
}
