#pragma once

#include "core/event.h"
#include "core/gpio.h"

struct GPIOEventData : public Event
{
    int line = -1;
    GPIOEdge edge = GPIOEdge::None;
    unsigned long long timestampNs = 0;

    GPIOEventData()
    {
        type = EventType::GPIOEdge;
    }
};
