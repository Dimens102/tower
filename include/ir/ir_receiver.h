#pragma once

#include "core/gpio.h"
#include "ir/ir_code.h"

class IRReceiver
{
public:
    bool initialize(int gpio);
    bool receive(IRCode& code);
    void shutdown();

private:
    GPIO gpio;
    int gpioPin = -1;
};
