
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <system_error>
#include <vector>
#include "core/commands/command_handlers.h"
#include "core/command.h"
#include "core/gpio.h"
#include "version.h"

namespace
{

bool isProjectRoot(const std::filesystem::path& path)
{
    std::error_code error;

    return
        std::filesystem::is_regular_file(
            path / "CMakeLists.txt",
            error) &&
        std::filesystem::is_directory(
            path / "data",
            error);
}

bool selectProjectRoot()
{
    std::vector<std::filesystem::path> candidates;

    if (const char* configuredRoot = std::getenv("TOWER_ROOT"))
    {
        candidates.emplace_back(configuredRoot);
    }

#ifdef TOWER_PROJECT_ROOT
    candidates.emplace_back(TOWER_PROJECT_ROOT);
#endif

    std::error_code error;
    const auto executable =
        std::filesystem::read_symlink("/proc/self/exe", error);

    if (!error)
    {
        candidates.push_back(
            executable.parent_path().parent_path());
    }

    error.clear();
    candidates.push_back(
        std::filesystem::current_path(error));

    for (const auto& candidate : candidates)
    {
        error.clear();
        const auto normalized =
            std::filesystem::weakly_canonical(candidate, error);

        if (error || !isProjectRoot(normalized))
        {
            continue;
        }

        std::filesystem::current_path(normalized, error);
        return !error;
    }

    return false;
}

} // namespace

void print_usage()

{
    std::cout
        << "Tower Home Automation Engine\n"
        << "Version " << TOWER_VERSION << "\n\n"
        << "Usage:\n"
        << "  tower version\n"
        << "  tower receive\n"
		<< "  tower monitor\n"
		<< "  tower service\n"
        << "  tower send\n"
        << "  tower learn\n"
        << "  tower learn-kernel\n"
        << "  tower replay\n"
        << "  tower config\n"
		<< "  tower sensor\n"
		<< "  tower temperature\n"
        << "  tower device\n"
        << "  tower command\n"
        << "  tower execute <device-id> <command-id>\n";
		
}

int main(int argc, char* argv[])
{
    if (!selectProjectRoot())
    {
        std::cerr
            << "Tower project root could not be found. "
            << "Set TOWER_ROOT to the rf-tower directory.\n";
        return 1;
    }

    if (argc == 1)
    {
        print_usage();
        return 0;
    }

    switch (parseCommand(argv[1]))
    {
        case Command::Version:
            return runVersionCommand();

        case Command::Receive:
            return runReceiveCommand();
			
        case Command::Monitor:
            return runMonitorCommand();
			
        case Command::Service:
            return runServiceCommand();

        case Command::Send:
            return runSendCommand(argc, argv);

        case Command::Learn:
            return runLearnCommand(argc, argv);
        case Command::Replay:
            return runReplayCommand(argc, argv);

        case Command::LearnKernel:
            return runLearnKernelCommand();

        case Command::Config:
            return runConfigCommand();
			
		case Command::Sensor:
            return runSensorCommand();
			
		case Command::Temperature:
		    return runTemperatureCommand(argc, argv);

        case Command::Device:
            return runDeviceCommand(argc, argv);
			
        case Command::LogicalCommand:
            return runLogicalCommand(argc, argv);
			
        case Command::Execute:
            return runExecuteCommand(argc, argv);			

        default:
            std::cerr << "Unknown command\n\n";
            print_usage();
            return 1;
    }

    return 0;
}
