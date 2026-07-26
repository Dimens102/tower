#pragma once

#include <string>

struct IRDecodedCode
{
        std::string protocol;
        unsigned int scancode = 0;
};

class IRKernelReceiver
{
public:
        bool receive(
                const std::string& inputDevice,
                const std::string& protocol,
                IRDecodedCode& code);
};
