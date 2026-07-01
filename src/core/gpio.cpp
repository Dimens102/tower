#include "core/gpio.h"

#include <gpiod.h>

#include <iostream>

GPIO::GPIO()
    : chip(nullptr)
{
}

GPIO::~GPIO()
{
    closeChip();
}

bool GPIO::openChip(const std::string& chipPath)
{
    closeChip();

    chip = gpiod_chip_open(chipPath.c_str());

    if (chip == nullptr)
    {
        std::cerr << "Failed to open GPIO chip: " << chipPath << "\n";
        return false;
    }

    return true;
}

void GPIO::closeChip()
{
    for (auto& entry : requests)
    {
        if (entry.second.handle != nullptr)
        {
            gpiod_line_request_release(entry.second.handle);
        }
    }

    requests.clear();

    if (chip != nullptr)
    {
        gpiod_chip_close(chip);
        chip = nullptr;
    }
}

bool GPIO::requestInput(int line, GPIOEdge edge)
{
    if (chip == nullptr)
    {
        std::cerr << "GPIO chip is not open\n";
        return false;
    }

    if (requests.count(line) != 0)
    {
        std::cerr << "GPIO line already requested: " << line << "\n";
        return false;
    }

    gpiod_line_settings* settings = gpiod_line_settings_new();
    gpiod_line_config* lineConfig = gpiod_line_config_new();
    gpiod_request_config* requestConfig = gpiod_request_config_new();

    if (!settings || !lineConfig || !requestConfig)
    {
        std::cerr << "Failed to allocate GPIO request objects\n";
        if (settings) gpiod_line_settings_free(settings);
        if (lineConfig) gpiod_line_config_free(lineConfig);
        if (requestConfig) gpiod_request_config_free(requestConfig);
        return false;
    }

    gpiod_line_settings_set_direction(settings, GPIOD_LINE_DIRECTION_INPUT);

    switch (edge)
    {
        case GPIOEdge::Rising:
            gpiod_line_settings_set_edge_detection(settings, GPIOD_LINE_EDGE_RISING);
            break;
        case GPIOEdge::Falling:
            gpiod_line_settings_set_edge_detection(settings, GPIOD_LINE_EDGE_FALLING);
            break;
        case GPIOEdge::Both:
            gpiod_line_settings_set_edge_detection(settings, GPIOD_LINE_EDGE_BOTH);
            break;
        case GPIOEdge::None:
        default:
            gpiod_line_settings_set_edge_detection(settings, GPIOD_LINE_EDGE_NONE);
            break;
    }

    unsigned int offset = static_cast<unsigned int>(line);

    if (gpiod_line_config_add_line_settings(lineConfig, &offset, 1, settings) < 0)
    {
        std::cerr << "Failed to configure GPIO input line: " << line << "\n";
        gpiod_line_settings_free(settings);
        gpiod_line_config_free(lineConfig);
        gpiod_request_config_free(requestConfig);
        return false;
    }

    gpiod_request_config_set_consumer(requestConfig, "tower");

    gpiod_line_request* request = gpiod_chip_request_lines(chip, requestConfig, lineConfig);

    gpiod_line_settings_free(settings);
    gpiod_line_config_free(lineConfig);
    gpiod_request_config_free(requestConfig);

    if (request == nullptr)
    {
        std::cerr << "Failed to request GPIO input line: " << line << "\n";
        return false;
    }

    requests[line] = GPIORequest{request, edge, false};
    return true;
}

bool GPIO::requestOutput(int line, bool initialValue)
{
    if (chip == nullptr)
    {
        std::cerr << "GPIO chip is not open\n";
        return false;
    }

    if (requests.count(line) != 0)
    {
        std::cerr << "GPIO line already requested: " << line << "\n";
        return false;
    }

    gpiod_line_settings* settings = gpiod_line_settings_new();
    gpiod_line_config* lineConfig = gpiod_line_config_new();
    gpiod_request_config* requestConfig = gpiod_request_config_new();

    if (!settings || !lineConfig || !requestConfig)
    {
        std::cerr << "Failed to allocate GPIO output request objects\n";
        if (settings) gpiod_line_settings_free(settings);
        if (lineConfig) gpiod_line_config_free(lineConfig);
        if (requestConfig) gpiod_request_config_free(requestConfig);
        return false;
    }

    gpiod_line_settings_set_direction(settings, GPIOD_LINE_DIRECTION_OUTPUT);
    gpiod_line_settings_set_output_value(
        settings,
        initialValue ? GPIOD_LINE_VALUE_ACTIVE : GPIOD_LINE_VALUE_INACTIVE
    );

    unsigned int offset = static_cast<unsigned int>(line);

    if (gpiod_line_config_add_line_settings(lineConfig, &offset, 1, settings) < 0)
    {
        std::cerr << "Failed to configure GPIO output line: " << line << "\n";
        gpiod_line_settings_free(settings);
        gpiod_line_config_free(lineConfig);
        gpiod_request_config_free(requestConfig);
        return false;
    }

    gpiod_request_config_set_consumer(requestConfig, "tower");

    gpiod_line_request* request = gpiod_chip_request_lines(chip, requestConfig, lineConfig);

    gpiod_line_settings_free(settings);
    gpiod_line_config_free(lineConfig);
    gpiod_request_config_free(requestConfig);

    if (request == nullptr)
    {
        std::cerr << "Failed to request GPIO output line: " << line << "\n";
        return false;
    }

    requests[line] = GPIORequest{request, GPIOEdge::None, true};
    return true;
}

bool GPIO::read(int line) const
{
    auto it = requests.find(line);

    if (it == requests.end() || it->second.handle == nullptr)
    {
        std::cerr << "GPIO line not requested: " << line << "\n";
        return false;
    }

    gpiod_line_value value =
        gpiod_line_request_get_value(it->second.handle, static_cast<unsigned int>(line));

    if (value == GPIOD_LINE_VALUE_ERROR)
    {
        std::cerr << "Failed to read GPIO line: " << line << "\n";
        return false;
    }

    return value == GPIOD_LINE_VALUE_ACTIVE;
}

bool GPIO::waitForEdge(int line, GPIOEvent& event, int timeoutMs)
{
    auto it = requests.find(line);

    if (it == requests.end() || it->second.handle == nullptr)
    {
        std::cerr << "GPIO line not requested: " << line << "\n";
        return false;
    }

    long long timeoutNs = static_cast<long long>(timeoutMs) * 1000000LL;

    int waitResult = gpiod_line_request_wait_edge_events(it->second.handle, timeoutNs);

    if (waitResult <= 0)
    {
        return false;
    }

    gpiod_edge_event_buffer* buffer = gpiod_edge_event_buffer_new(1);

    if (buffer == nullptr)
    {
        std::cerr << "Failed to allocate GPIO edge event buffer\n";
        return false;
    }

    int readResult = gpiod_line_request_read_edge_events(it->second.handle, buffer, 1);

    if (readResult <= 0)
    {
        gpiod_edge_event_buffer_free(buffer);
        return false;
    }

    gpiod_edge_event* rawEvent = gpiod_edge_event_buffer_get_event(buffer, 0);

    if (rawEvent == nullptr)
    {
        gpiod_edge_event_buffer_free(buffer);
        return false;
    }

    event.line = static_cast<int>(gpiod_edge_event_get_line_offset(rawEvent));
    event.timestampNs = gpiod_edge_event_get_timestamp_ns(rawEvent);

    auto type = gpiod_edge_event_get_event_type(rawEvent);
    event.edge = (type == GPIOD_EDGE_EVENT_RISING_EDGE)
        ? GPIOEdge::Rising
        : GPIOEdge::Falling;

    gpiod_edge_event_buffer_free(buffer);
    return true;
}

bool GPIO::write(int line, bool value)
{
    auto it = requests.find(line);

    if (it == requests.end() || it->second.handle == nullptr)
    {
        std::cerr << "GPIO line not requested: " << line << "\n";
        return false;
    }

    if (!it->second.isOutput)
    {
        std::cerr << "GPIO line is not configured as output: " << line << "\n";
        return false;
    }

    int result = gpiod_line_request_set_value(
        it->second.handle,
        static_cast<unsigned int>(line),
        value ? GPIOD_LINE_VALUE_ACTIVE : GPIOD_LINE_VALUE_INACTIVE
    );

    if (result < 0)
    {
        std::cerr << "Failed to write GPIO line: " << line << "\n";
        return false;
    }

    return true;
}
