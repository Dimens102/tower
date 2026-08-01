#include "devices/ir/ir_receiver_array.h"

#include <cassert>
#include <filesystem>
#include <fstream>
#include <string>

namespace fs = std::filesystem;

namespace
{
void addReceiver(
    const fs::path& root,
    int rcNumber,
    const std::string& gpioHex,
    int lircNumber)
{
    const fs::path device = root / "devices" / ("ir-receiver@" + gpioHex);
    const fs::path rc = root / "class" / "rc" / ("rc" + std::to_string(rcNumber));
    fs::create_directories(device);
    fs::create_directories(rc / ("lirc" + std::to_string(lircNumber)));
    fs::create_directory_symlink(device, rc / "device");
}
} // namespace

int main()
{
    const fs::path root = fs::temp_directory_path() / "tower-ir-array-test";
    fs::remove_all(root);

    addReceiver(root, 9, "11", 5); // GPIO17
    addReceiver(root, 2, "12", 4); // GPIO18
    addReceiver(root, 7, "1b", 3); // GPIO27
    addReceiver(root, 1, "16", 2); // GPIO22
    addReceiver(root, 8, "17", 1); // GPIO23
    addReceiver(root, 0, "19", 0); // GPIO25

    IRReceiverArray array;
    const std::vector<IRReceiverStatus> statuses =
        array.discover(root / "class" / "rc");

    assert(statuses.size() == 6);
    assert(statuses[0].receiver.gpio == 17);
    assert(statuses[0].receiver.model == "TSOP38230");
    assert(statuses[0].receiver.nominalCarrierKhz == 30);
    assert(statuses[0].receiver.position == "West");
    assert(statuses[0].lircDevice == "/dev/lirc5");
    assert(statuses[1].lircDevice == "/dev/lirc4");
    assert(statuses[2].lircDevice == "/dev/lirc3");
    assert(statuses[3].lircDevice == "/dev/lirc2");
    assert(statuses[4].lircDevice == "/dev/lirc1");
    assert(statuses[5].lircDevice == "/dev/lirc0");
    assert(array.allAvailable(root / "class" / "rc"));

    fs::remove_all(root / "class" / "rc" / "rc8");
    const std::vector<IRReceiverStatus> incomplete =
        array.discover(root / "class" / "rc");
    assert(!incomplete[4].available());
    assert(!array.allAvailable(root / "class" / "rc"));

    fs::remove_all(root);
    return 0;
}
