#include "devices/device_database.h"
#include "devices/device_editor.h"

#include <cassert>
#include <filesystem>
#include <fstream>

int main()
{
    std::filesystem::create_directories("data/devices");
    std::ofstream oldRecord("data/devices/TestRemote.json");
    oldRecord << R"({
  "id": "TestRemote",
  "name": "Test Remote",
  "remoteName": "Original Test Handset",
  "enabled": true,
  "aliases": [],
  "commands": [{
    "id": "Power",
    "name": "Power",
    "transport": "IR",
    "transportDevice": "TestRemote",
    "transportCommand": "Power",
    "transmitter": "Tower-IR-TX-001",
    "enabled": true
  }]
})";
    oldRecord.close();

    DeviceDatabase database;
    Device device;
    assert(database.loadDevice("TestRemote", device));
    assert(device.commands.size() == 1);
    assert(device.remoteName == "Original Test Handset");
    assert(device.commands[0].description.empty());
    assert(device.commands[0].transmitter == "Tower-IR-TX-001");
    assert(device.transmitter == "Tower-IR-TX-001");

    device.commands[0].description = "Turns the receiver on or off";
    assert(DeviceEditor::setProperty(
        device, "transmitter", "Tower-IR-TX-003"));
    assert(device.commands[0].transmitter == "Tower-IR-TX-003");
    assert(database.saveDevice(device));

    Device reloaded;
    assert(database.loadDevice("TestRemote", reloaded));
    assert(reloaded.commands[0].description == "Turns the receiver on or off");
    assert(reloaded.remoteName == "Original Test Handset");
    assert(reloaded.transmitter == "Tower-IR-TX-003");
    assert(reloaded.commands[0].transmitter == "Tower-IR-TX-003");

    return 0;
}
