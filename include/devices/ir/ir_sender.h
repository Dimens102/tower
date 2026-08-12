#pragma once

#include "devices/ir/ir_code.h"
#include "devices/ir/ir_transmitter.h"

class IRSender
{
public:
    bool send(const IRCode& code, const IRTransmitter& transmitter, unsigned int dutyPercent = 0, unsigned int carrierKhz = 0);

private:
    bool sendViaPico(
                 const IRCode& code,
                 const IRTransmitter& transmitter,
                 unsigned int dutyPercent,
        unsigned int carrierKhz);

    bool sendRaw(const IRCode& code,
                 const IRTransmitter& transmitter,
                 const std::string& lircDevice);

    bool sendNEC(const IRCode& code,
                 const IRTransmitter& transmitter,
                 const std::string& lircDevice);
};
