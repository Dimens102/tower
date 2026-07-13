#include "ir/ir_kernel_receiver.h"

#include <fcntl.h>
#include <linux/input.h>
#include <unistd.h>

#include <cerrno>
#include <cstring>
#include <iostream>

bool IRKernelReceiver::receive(
        const std::string& inputDevice,
        const std::string& protocol,
        IRDecodedCode& code)
{
        int fd = open(inputDevice.c_str(), O_RDONLY);

        if (fd < 0)
        {
                std::cerr << "Failed to open input device "
                          << inputDevice
                          << ": "
                          << std::strerror(errno)
                          << "\n";
                return false;
        }

        std::cout << "Waiting for decoded IR command...\n";

        input_event event{};

        while (true)
        {
                ssize_t bytesRead = read(fd, &event, sizeof(event));

                if (bytesRead != sizeof(event))
                {
                        std::cerr << "Failed to read IR input event\n";
                        close(fd);
                        return false;
                }

                if (event.type == EV_MSC &&
                    event.code == MSC_SCAN)
                {
                        code.protocol = protocol;
                        code.scancode =
                                static_cast<unsigned int>(event.value);

                        close(fd);
                        return true;
                }
        }
}
