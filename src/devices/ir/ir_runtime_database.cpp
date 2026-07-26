#include "devices/ir/ir_runtime_database.h"

#include <filesystem>
#include <fstream>
#include <sstream>

std::optional<std::string> IRRuntimeDatabase::getLircDeviceForGpio(int gpio)
{
    namespace fs = std::filesystem;

    const fs::path rcRoot("/sys/class/rc");
    const fs::path lircRoot("/sys/class/lirc");

    if (!fs::exists(rcRoot) || !fs::exists(lircRoot))
    {
        return std::nullopt;
    }

    for (const auto& rcEntry : fs::directory_iterator(rcRoot))
    {
        const fs::path uevent = rcEntry.path() / "device" / "uevent";

        std::ifstream in(uevent);

        if (!in)
        {
            continue;
        }

        std::string line;
        std::string driver;
        std::string ofFullName;

        while (std::getline(in, line))
        {
            if (line.rfind("DRIVER=", 0) == 0)
            {
                driver = line.substr(7);
            }
            else if (line.rfind("OF_FULLNAME=", 0) == 0)
            {
                ofFullName = line.substr(12);
            }
        }

        if (driver != "gpio-ir-tx")
        {
            continue;
        }

        const auto at = ofFullName.find('@');

        if (at == std::string::npos)
        {
            continue;
        }

        std::stringstream ss;
        ss << std::hex << ofFullName.substr(at + 1);

        int detectedGpio = -1;
        ss >> detectedGpio;

        if (detectedGpio != gpio)
        {
            continue;
        }

        std::error_code error;
        const fs::path rcPlatformDevice =
            fs::canonical(rcEntry.path() / "device", error);

        if (error)
        {
            continue;
        }

        for (const auto& lircEntry : fs::directory_iterator(lircRoot))
        {
            error.clear();

            fs::path current =
                fs::canonical(lircEntry.path() / "device", error);

            if (error)
            {
                continue;
            }

            while (!current.empty())
            {
                if (current == rcPlatformDevice)
                {
                    return "/dev/" +
                           lircEntry.path().filename().string();
                }

                const fs::path parent = current.parent_path();

                if (parent == current)
                {
                    break;
                }

                current = parent;
            }
        }

        return std::nullopt;
    }

    return std::nullopt;
}
