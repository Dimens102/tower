#include "devices/ir/ir_database.h"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

bool IRDatabase::save(const std::string& deviceName, const std::string& commandName, const IRCode& code)
{
     std::filesystem::path dir = std::filesystem::path("data") / "ir" / deviceName;
     std::filesystem::create_directories(dir);

     std::filesystem::path file = dir / (commandName + ".ir");

     std::ofstream out(file);

     if (!out)
     {
          std::cerr << "Failed to open IR file for writing: " << file << "\n";
          return false;
     }

     out << "device=" << code.device << "\n";
     out << "command=" << code.command << "\n";
     out << "protocol=" << code.protocol << "\n";
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

     return true;
}

bool IRDatabase::load(const std::string& deviceName, const std::string& commandName, IRCode& code)
{
     std::filesystem::path file =
          std::filesystem::path("data") / "ir" / deviceName / (commandName + ".ir");

     std::ifstream in(file);

     if (!in)
     {
          std::cerr << "Failed to open IR file for reading: " << file << "\n";
          return false;
     }

     code.pulses.clear();

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
