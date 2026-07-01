#pragma once

#include "core/event.h"
#include "ir/ir_code.h"

struct IREvent : public Event
{
    IRCode code;

    IREvent()
    {
        type = EventType::None;
    }
};
