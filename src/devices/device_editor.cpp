#include "devices/device_editor.h"
#include <algorithm>

bool DeviceEditor::setProperty(
    Device& device,
    const std::string& property,
    const std::string& value)
{
    if (property == "name")
    {
        device.name = value;
        return true;
    }

    if (property == "type")
    {
        device.type = value;
        return true;
    }

    if (property == "manufacturer")
    {
        device.manufacturer = value;
        return true;
    }

    if (property == "model")
    {
        device.model = value;
        return true;
    }

    if (property == "location")
    {
        device.location = value;
        return true;
    }

    if (property == "enabled")
    {
        device.enabled =
            (value == "true" ||
             value == "1" ||
             value == "yes");

        return true;
    }

    return false;
}	

bool DeviceEditor::addAlias(
    Device& device,
    const std::string& alias)
{
    if (alias.empty())
        return false;

    auto existing = std::find(
        device.aliases.begin(),
        device.aliases.end(),
        alias);

    if (existing != device.aliases.end())
        return false;

    device.aliases.push_back(alias);
    return true;
}

bool DeviceEditor::removeAlias(
    Device& device,
    const std::string& alias)
{
    auto existing = std::find(
        device.aliases.begin(),
        device.aliases.end(),
        alias);

    if (existing == device.aliases.end())
        return false;

    device.aliases.erase(existing);
    return true;
}
