#include "devices/ir/ir_database.h"

#include <cassert>
#include <filesystem>
#include <fstream>

int main()
{
    IRCode saved;
    saved.device = "TestRemote";
    saved.command = "Power";
    saved.description = "Turns the test device on or off";
    saved.protocol = "raw";
    saved.decodedProtocol = "Siemens";
    saved.address = 0x250;
    saved.decodedCommand = 0x0B;
    saved.carrierKhz = 56;
    saved.receiverGpio = 25;
    saved.receiverModel = "TSOP38256";
    saved.sourceCapture = "captures/ir/test";
    saved.pulses = {321, 628, 648};

    const unsigned gpios[] = {17, 18, 27, 22, 23, 25};
    const unsigned carriers[] = {30, 33, 36, 38, 40, 56};
    const char* models[] = {
        "TSOP38230", "TSOP38233", "TSOP34836",
        "TSOP38238", "TSOP38240", "TSOP38256"};
    for (std::size_t index = 0; index < 6; ++index)
    {
        IRAnalysisRow row;
        row.gpio = gpios[index];
        row.receiverModel = models[index];
        row.nominalCarrierKhz = carriers[index];
        row.frameCount = 21;
        row.validFrameCount = index == 5 ? 21 : 0;
        row.result = index == 5 ? "CLEAN" : "FAILED";
        if (index == 5)
        {
            row.decodedProtocol = "Siemens";
            row.address = 0x250;
            row.decodedCommand = 0x0B;
        }
        saved.analysis.push_back(row);
    }

    IRDatabase database;
    assert(database.save(saved.device, saved.command, saved));
    assert(database.path(saved.device, saved.command) ==
        std::filesystem::path("data/ir/devices/TestRemote/Power.ir"));

    IRCode loaded;
    assert(database.load(saved.device, saved.command, loaded));
    assert(loaded.description == saved.description);
    assert(loaded.analysis.size() == 6);
    assert(loaded.analysis[5].gpio == 25);
    assert(loaded.analysis[5].decodedProtocol == "Siemens");
    assert(loaded.analysis[5].address == 0x250);
    assert(loaded.analysis[5].decodedCommand == 0x0B);
    assert(loaded.pulses == saved.pulses);

    std::filesystem::create_directories("data/ir/LegacyRemote");
    std::ofstream legacy("data/ir/LegacyRemote/Power.ir");
    legacy << "device=LegacyRemote\ncommand=Power\nprotocol=raw\npulses=1,2,3\n";
    legacy.close();

    IRCode legacyLoaded;
    assert(database.load("LegacyRemote", "Power", legacyLoaded));
    assert(legacyLoaded.pulses == std::vector<unsigned int>({1, 2, 3}));
    assert(database.path("LegacyRemote", "Power") ==
        std::filesystem::path("data/ir/LegacyRemote/Power.ir"));

    std::filesystem::create_directories("data/ir/remotes/PreviousRemote");
    std::ofstream previous("data/ir/remotes/PreviousRemote/Power.ir");
    previous << "device=PreviousRemote\ncommand=Power\nprotocol=raw\npulses=4,5,6\n";
    previous.close();

    IRCode previousLoaded;
    assert(database.load("PreviousRemote", "Power", previousLoaded));
    assert(previousLoaded.pulses == std::vector<unsigned int>({4, 5, 6}));
    assert(database.path("PreviousRemote", "Power") ==
        std::filesystem::path("data/ir/remotes/PreviousRemote/Power.ir"));

    return 0;
}
