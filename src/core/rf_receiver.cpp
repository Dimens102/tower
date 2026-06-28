#include "core/rf_receiver.h"

#include <iostream>

bool RFReceiver::initialize(int gpio)
{
    std::cout << "RF receiver initialized on GPIO " << gpio << "\n";
    return true;
}

void RFReceiver::start()
{
    std::cout << "RF receiver started\n";
}

void RFReceiver::stop()
{
    std::cout << "RF receiver stopped\n";
}
