#pragma once

#include "core/event.h"
#include "devices/ir/ir_code.h"

struct IREvent : public Event
{
    IRCode code;

    IREvent()
    {
        type = EventType::None;
    }
};
