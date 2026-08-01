#include "core/commands/command_handlers.h"

#include "devices/ir/ir_array_capture.h"
#include "devices/ir/ir_receiver_array.h"

#include <chrono>
#include <cctype>
#include <ctime>
#include <filesystem>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace
{
std::string safeName(const std::string& value)
{
    std::string result;
    bool separator = false;

    for (const unsigned char character : value)
    {
        if (std::isalnum(character) || character == '.' || character == '_' ||
            character == '-')
        {
            result.push_back(static_cast<char>(character));
            separator = false;
        }
        else if (!result.empty() && !separator)
        {
            result.push_back('-');
            separator = true;
        }
    }

    while (!result.empty() && (result.back() == '.' || result.back() == '-'))
    {
        result.pop_back();
    }

    if (result.empty())
    {
        throw std::invalid_argument("Name cannot be converted to a filename");
    }
    return result;
}

std::string utcTimestamp()
{
    const std::time_t now = std::time(nullptr);
    std::tm utc = {};
    gmtime_r(&now, &utc);
    std::ostringstream output;
    output << std::put_time(&utc, "%Y%m%dT%H%M%SZ");
    return output.str();
}

} // namespace

int runIRCaptureCommand(int argc, char* argv[])
{
    if (argc < 4 || argc > 5)
    {
        std::cerr
            << "Usage: tower ir-capture <device-name> <command-name> [seconds]\n";
        return 1;
    }

    double seconds = 8.0;
    if (argc == 5)
    {
        try
        {
            std::size_t parsed = 0;
            seconds = std::stod(argv[4], &parsed);
            if (parsed != std::string(argv[4]).size() || seconds <= 0.0 ||
                seconds > 300.0)
            {
                throw std::invalid_argument("invalid duration");
            }
        }
        catch (...)
        {
            std::cerr << "Capture duration must be between 0 and 300 seconds.\n";
            return 1;
        }
    }

    const IRReceiverArray array;
    const std::vector<IRReceiverStatus> receivers = array.discover();
    if (!array.allAvailable())
    {
        std::cerr
            << "All six IR receivers must be available. "
            << "Run 'tower ir-receivers' for details.\n";
        return 1;
    }

    std::filesystem::path destination;
    try
    {
        destination =
            std::filesystem::path("captures") / "ir" /
            (utcTimestamp() + "_" + safeName(argv[2]) + "_" + safeName(argv[3]));
    }
    catch (const std::exception& error)
    {
        std::cerr << error.what() << "\n";
        return 1;
    }

    std::cout
        << "IR receiver-array capture\n\n"
        << "Device   : " << argv[2] << "\n"
        << "Command  : " << argv[3] << "\n"
        << "Duration : " << seconds << " seconds\n"
        << "Output   : " << destination.string() << "\n\n"
        << "Recording NOW - press the same button several times.\n";

    std::vector<IRArrayCaptureResult> results;
    try
    {
        results = IRArrayCapture().capture(receivers, destination, seconds);
    }
    catch (const std::exception& error)
    {
        std::cerr << "Capture failed: " << error.what() << "\n";
        return 1;
    }

    std::cout
        << "\nCapture complete\n\n"
        << std::left
        << std::setw(6) << "GPIO"
        << std::setw(12) << "Receiver"
        << std::setw(7) << "kHz"
        << std::setw(10) << "Timings"
        << std::setw(8) << "Pulses"
        << "Result\n"
        << std::setw(6) << "----"
        << std::setw(12) << "---------"
        << std::setw(7) << "---"
        << std::setw(10) << "-------"
        << std::setw(8) << "------"
        << "------\n";

    bool anySignal = false;
    bool anyError = false;
    for (const IRArrayCaptureResult& result : results)
    {
        const bool signal = result.pulseCount > 0;
        const bool error = irCaptureDiagnosticHasError(result.diagnostic);
        anySignal = anySignal || signal;
        anyError = anyError || error;

        std::cout
            << std::setw(6) << result.receiver.receiver.gpio
            << std::setw(12) << result.receiver.receiver.model
            << std::setw(7) << result.receiver.receiver.nominalCarrierKhz
            << std::setw(10) << result.timingCount
            << std::setw(8) << result.pulseCount
            << (signal ? "CAPTURED" : (error ? "ERROR" : "NO-SIGNAL"))
            << "\n";

        if (error)
        {
            std::cerr
                << result.receiver.lircDevice << ": " << result.diagnostic;
            if (result.diagnostic.back() != '\n')
            {
                std::cerr << '\n';
            }
        }
    }

    std::cout << "\nSaved: " << destination.string() << "\n";

    if (anyError)
    {
        return 1;
    }
    if (!anySignal)
    {
        std::cerr << "No IR signal was captured by any receiver.\n";
        return 2;
    }
    return 0;
}
