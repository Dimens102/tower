#pragma once

#include <string>

#include "ir/ir_transmitter.h"

class IRTransmitterDatabase
{
public:
     bool load(const std::string& name, IRTransmitter& transmitter);
};
