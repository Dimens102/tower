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
     return std::filesystem::path("data") / "ir" / "devices" / deviceName /
          (commandName + ".ir");
}

std::filesystem::path remoteCommandPath(
    const std::string& deviceName,
    const std::string& commandName)
{
     return std::filesystem::path("data") / "ir" / "remotes" / deviceName /
          (commandName + ".ir");
}

std::filesystem::path legacyCommandPath(
    const std::string& deviceName,
    const std::string& commandName)
{
     return std::filesystem::path("data") / "ir" / deviceName /
          (commandName + ".ir");
}

std::filesystem::path existingCommandPath(
    const std::string& deviceName,
    const std::string& commandName)
{
     const std::filesystem::path current = commandPath(deviceName, commandName);
     if (std::filesystem::is_regular_file(current)) return current;
     const std::filesystem::path remote = remoteCommandPath(deviceName, commandName);
     if (std::filesystem::is_regular_file(remote)) return remote;
     return legacyCommandPath(deviceName, commandName);
}
}

bool IRDatabase::save(const std::string& deviceName, const std::string& commandName, const IRCode& code)
{
     std::filesystem::path dir =
          std::filesystem::path("data") / "ir" / "devices" / deviceName;
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
     out << "description=" << code.description << "\n";
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
     if (!code.analysis.empty())
     {
          out << "analysis_header=GPIO|Receiver|kHz|Frames|Valid|Result|Decode\n";
          for (const IRAnalysisRow& row : code.analysis)
          {
               out << "analysis=" << row.gpio << "|" << row.receiverModel << "|"
                   << row.nominalCarrierKhz << "|" << row.frameCount << "|"
                   << row.validFrameCount << "|" << row.result << "|";
               if (row.decodedProtocol.empty())
               {
                    out << "-";
               }
               else
               {
                    out << row.decodedProtocol << " 0x" << std::uppercase << std::hex
                        << row.address << "/0x" << std::setw(2) << std::setfill('0')
                        << row.decodedCommand << std::dec << std::setfill(' ');
               }
               out << "\n";
          }
     }
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
     std::filesystem::path file = existingCommandPath(deviceName, commandName);

     std::ifstream in(file);

     if (!in)
     {
          std::cerr << "Failed to open IR file for reading: " << file << "\n";
          return false;
     }

     code.pulses.clear();
     code.description.clear();
     code.decodedProtocol.clear();
     code.address = 0;
     code.decodedCommand = 0;
     code.carrierKhz = 0;
     code.receiverGpio = 0;
     code.receiverModel.clear();
     code.sourceCapture.clear();
     code.analysis.clear();

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
          else if (key == "description") code.description = value;
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
          else if (key == "analysis")
          {
               std::vector<std::string> fields;
               std::size_t start = 0;
               while (start <= value.size())
               {
                    const std::size_t separator = value.find('|', start);
                    fields.push_back(value.substr(start, separator - start));
                    if (separator == std::string::npos) break;
                    start = separator + 1;
               }

               if (fields.size() == 7)
               {
                    IRAnalysisRow row;
                    row.gpio = static_cast<unsigned>(std::stoul(fields[0]));
                    row.receiverModel = fields[1];
                    row.nominalCarrierKhz = static_cast<unsigned>(std::stoul(fields[2]));
                    row.frameCount = static_cast<std::size_t>(std::stoul(fields[3]));
                    row.validFrameCount = static_cast<std::size_t>(std::stoul(fields[4]));
                    row.result = fields[5];

                    if (fields[6] != "-")
                    {
                         const std::size_t addressStart = fields[6].find(" 0x");
                         const std::size_t commandStart = fields[6].find("/0x", addressStart);
                         if (addressStart != std::string::npos && commandStart != std::string::npos)
                         {
                              row.decodedProtocol = fields[6].substr(0, addressStart);
                              row.address = static_cast<unsigned>(std::stoul(
                                   fields[6].substr(addressStart + 1, commandStart - addressStart - 1),
                                   nullptr, 0));
                              row.decodedCommand = static_cast<unsigned>(std::stoul(
                                   fields[6].substr(commandStart + 1), nullptr, 0));
                         }
                    }
                    code.analysis.push_back(row);
               }
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

bool IRDatabase::exists(
    const std::string& deviceName,
    const std::string& commandName) const
{
     return std::filesystem::is_regular_file(commandPath(deviceName, commandName)) ||
          std::filesystem::is_regular_file(remoteCommandPath(deviceName, commandName)) ||
          std::filesystem::is_regular_file(legacyCommandPath(deviceName, commandName));
}

std::filesystem::path IRDatabase::path(
    const std::string& deviceName,
    const std::string& commandName) const
{
     const std::filesystem::path current = commandPath(deviceName, commandName);
     if (std::filesystem::is_regular_file(current)) return current;

     const std::filesystem::path remote = remoteCommandPath(deviceName, commandName);
     if (std::filesystem::is_regular_file(remote)) return remote;

     const std::filesystem::path legacy = legacyCommandPath(deviceName, commandName);
     if (std::filesystem::is_regular_file(legacy)) return legacy;

     return current;
}
