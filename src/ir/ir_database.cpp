#include "ir/ir_database.h"

#include <filesystem>
#include <fstream>
#include <iostream>

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
        if (i > 0) out << ",";
        out << code.pulses[i];
    }

    out << "\n";
    return true;
}

bool IRDatabase::load(const std::string& deviceName, const std::string& commandName, IRCode& code)
{
    std::cerr << "IR load not implemented yet: " << deviceName << " " << commandName << "\n";
    return false;
}
