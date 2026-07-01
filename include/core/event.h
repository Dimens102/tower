#pragma once

enum class EventType
{
    None,
    GPIOEdge,
    IRCode
};

struct Event
{
    EventType type = EventType::None;
};
