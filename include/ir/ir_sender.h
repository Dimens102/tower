#pragma once

#include "ir/ir_code.h"
#include "ir/ir_transmitter.h"

class IRSender
{
public:
    bool send(const IRCode& code, const IRTransmitter& transmitter);
};
