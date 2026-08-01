#include "devices/ir/ir_database.h"

#include <cassert>
#include <filesystem>

namespace fs = std::filesystem;

int main()
{
    const fs::path original = fs::current_path();
    const fs::path root = fs::temp_directory_path() / "tower-ir-database-test";
    fs::remove_all(root);
    fs::create_directories(root);
    fs::current_path(root);

    IRCode written;
    written.device = "KPN";
    written.command = "Power";
    written.protocol = "raw";
    written.decodedProtocol = "Siemens";
    written.address = 0x250;
    written.decodedCommand = 0x0B;
    written.carrierKhz = 56;
    written.receiverGpio = 25;
    written.receiverModel = "TSOP38256";
    written.sourceCapture = "captures/ir/example";
    written.pulses = {325, 645, 636, 642};

    IRDatabase database;
    assert(!database.exists("KPN", "Power"));
    assert(database.save("KPN", "Power", written));
    assert(database.exists("KPN", "Power"));
    assert(database.path("KPN", "Power") == fs::path("data/ir/KPN/Power.ir"));

    IRCode loaded;
    assert(database.load("KPN", "Power", loaded));
    assert(loaded.device == written.device);
    assert(loaded.command == written.command);
    assert(loaded.protocol == "raw");
    assert(loaded.decodedProtocol == "Siemens");
    assert(loaded.address == 0x250);
    assert(loaded.decodedCommand == 0x0B);
    assert(loaded.carrierKhz == 56);
    assert(loaded.receiverGpio == 25);
    assert(loaded.receiverModel == "TSOP38256");
    assert(loaded.sourceCapture == "captures/ir/example");
    assert(loaded.pulses == written.pulses);

    fs::current_path(original);
    fs::remove_all(root);
    return 0;
}
