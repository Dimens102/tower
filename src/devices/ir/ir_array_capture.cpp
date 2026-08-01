#include "devices/ir/ir_array_capture.h"

#include <chrono>
#include <csignal>
#include <fcntl.h>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <system_error>
#include <thread>

#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

namespace
{
struct RunningCapture
{
    pid_t pid = -1;
    std::filesystem::path rawPath;
    std::filesystem::path errorPath;
};

bool isTimingLine(const std::string& line)
{
    std::istringstream input(line);
    std::string kind;
    unsigned long duration = 0;
    std::string extra;

    if (!(input >> kind >> duration) || (input >> extra))
    {
        return false;
    }

    return kind == "pulse" || kind == "space" || kind == "timeout";
}

std::string readText(const std::filesystem::path& path)
{
    std::ifstream input(path);
    std::ostringstream text;
    text << input.rdbuf();
    return text.str();
}

RunningCapture startCapture(
    const std::string& executable,
    const IRReceiverStatus& receiver,
    const std::filesystem::path& destination)
{
    RunningCapture process;
    const std::string stem =
        "gpio" + std::to_string(receiver.receiver.gpio) + "_" +
        std::to_string(receiver.receiver.nominalCarrierKhz) + "khz";
    process.rawPath = destination / (stem + ".raw");
    process.errorPath = destination / (stem + ".stderr");

    const int output = ::open(
        process.rawPath.c_str(),
        O_WRONLY | O_CREAT | O_TRUNC,
        0644);
    if (output < 0)
    {
        throw std::runtime_error("Could not create " + process.rawPath.string());
    }

    const int error = ::open(
        process.errorPath.c_str(),
        O_WRONLY | O_CREAT | O_TRUNC,
        0644);
    if (error < 0)
    {
        ::close(output);
        throw std::runtime_error("Could not create " + process.errorPath.string());
    }

    process.pid = ::fork();
    if (process.pid == 0)
    {
        ::dup2(output, STDOUT_FILENO);
        ::dup2(error, STDERR_FILENO);
        ::close(output);
        ::close(error);

        ::execlp(
            executable.c_str(),
            executable.c_str(),
            "--driver",
            "default",
            "--device",
            receiver.lircDevice.c_str(),
            static_cast<char*>(nullptr));

        const char message[] = "Could not execute mode2\n";
        ::write(STDERR_FILENO, message, sizeof(message) - 1);
        _exit(127);
    }

    ::close(output);
    ::close(error);

    if (process.pid < 0)
    {
        throw std::runtime_error("Could not start mode2");
    }

    return process;
}

void stopCapture(const RunningCapture& process)
{
    if (process.pid <= 0)
    {
        return;
    }

    int status = 0;
    if (::waitpid(process.pid, &status, WNOHANG) == process.pid)
    {
        return;
    }

    ::kill(process.pid, SIGINT);
    const auto deadline =
        std::chrono::steady_clock::now() + std::chrono::seconds(3);

    while (std::chrono::steady_clock::now() < deadline)
    {
        if (::waitpid(process.pid, &status, WNOHANG) == process.pid)
        {
            return;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }

    ::kill(process.pid, SIGKILL);
    ::waitpid(process.pid, &status, 0);
}

IRArrayCaptureResult finishCapture(
    const IRReceiverStatus& receiver,
    const RunningCapture& process,
    const std::filesystem::path& destination)
{
    IRArrayCaptureResult result;
    result.receiver = receiver;
    result.started = process.pid > 0;
    result.recordingPath = destination /
        ("gpio" + std::to_string(receiver.receiver.gpio) + "_" +
         std::to_string(receiver.receiver.nominalCarrierKhz) + "khz.mode2");
    result.diagnostic = readText(process.errorPath);

    std::ifstream raw(process.rawPath);
    std::ofstream recording(result.recordingPath);
    std::string line;

    while (std::getline(raw, line))
    {
        if (!isTimingLine(line))
        {
            continue;
        }

        recording << line << '\n';
        ++result.timingCount;
        if (line.compare(0, 6, "pulse ") == 0)
        {
            ++result.pulseCount;
        }
    }

    std::error_code error;
    std::filesystem::remove(process.rawPath, error);
    error.clear();
    std::filesystem::remove(process.errorPath, error);
    return result;
}
} // namespace

bool irCaptureDiagnosticHasError(const std::string& diagnostic)
{
    std::istringstream lines(diagnostic);
    std::string line;
    while (std::getline(lines, line))
    {
        if (line.empty() || line.rfind("Using driver ", 0) == 0 ||
            line.rfind("Trying device: ", 0) == 0 ||
            line.rfind("Using device: ", 0) == 0)
        {
            continue;
        }
        return true;
    }
    return false;
}

IRArrayCapture::IRArrayCapture(std::string mode2Executable)
    : mode2Executable_(std::move(mode2Executable))
{
}

std::vector<IRArrayCaptureResult> IRArrayCapture::capture(
    const std::vector<IRReceiverStatus>& receivers,
    const std::filesystem::path& destination,
    double seconds) const
{
    if (seconds <= 0.0)
    {
        throw std::invalid_argument("Capture duration must be greater than zero");
    }

    for (const IRReceiverStatus& receiver : receivers)
    {
        if (!receiver.available())
        {
            throw std::runtime_error(
                "No LIRC device for GPIO" +
                std::to_string(receiver.receiver.gpio));
        }
    }

    std::error_code error;
    std::filesystem::create_directories(destination, error);
    if (error)
    {
        throw std::runtime_error(
            "Could not create capture directory: " + error.message());
    }

    std::vector<RunningCapture> processes;
    processes.reserve(receivers.size());

    try
    {
        for (const IRReceiverStatus& receiver : receivers)
        {
            processes.push_back(
                startCapture(mode2Executable_, receiver, destination));
        }
    }
    catch (...)
    {
        for (const RunningCapture& process : processes)
        {
            stopCapture(process);
        }
        throw;
    }

    const auto duration = std::chrono::duration<double>(seconds);
    std::this_thread::sleep_for(duration);

    for (const RunningCapture& process : processes)
    {
        stopCapture(process);
    }

    std::vector<IRArrayCaptureResult> results;
    results.reserve(receivers.size());
    for (std::size_t index = 0; index < receivers.size(); ++index)
    {
        results.push_back(
            finishCapture(receivers[index], processes[index], destination));
    }
    return results;
}
