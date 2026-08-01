#include "devices/ir/ir_array_capture.h"

#include <cassert>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>

#include <sys/stat.h>

namespace fs = std::filesystem;

int main()
{
    const fs::path root = fs::temp_directory_path() / "tower-ir-capture-test";
    fs::remove_all(root);
    fs::create_directories(root);

    const fs::path fakeMode2 = root / "fake-mode2";
    {
        std::ofstream script(fakeMode2);
        script
            << "#!/bin/sh\n"
            << "trap 'exit 0' INT TERM\n"
            << "printf 'Using driver default on device /dev/lirc-test\\n"
               "Trying device: /dev/lirc-test\\n"
               "Using device: /dev/lirc-test\\n' >&2\n"
            << "printf 'Using fake driver\\npulse 9000\\nspace 4500\\n"
               "timeout 125000\\ninvalid text\\n'\n"
            << "while :; do :; done\n";
    }
    ::chmod(fakeMode2.c_str(), 0755);

    const IRReceiverStatus receiver = {
        {22, "TSOP38238", 38, "South"},
        "/dev/lirc-test",
    };

    const IRArrayCapture capture(fakeMode2.string());
    const std::vector<IRArrayCaptureResult> results =
        capture.capture({receiver}, root / "output", 0.05);

    assert(results.size() == 1);
    assert(results[0].started);
    assert(results[0].timingCount == 3);
    assert(results[0].pulseCount == 1);
    assert(!results[0].diagnostic.empty());
    assert(!irCaptureDiagnosticHasError(results[0].diagnostic));
    assert(irCaptureDiagnosticHasError("Could not open /dev/lirc-test\n"));

    std::ifstream recording(results[0].recordingPath);
    const std::string text(
        (std::istreambuf_iterator<char>(recording)),
        std::istreambuf_iterator<char>());
    assert(text == "pulse 9000\nspace 4500\ntimeout 125000\n");

    fs::remove_all(root);
    return 0;
}
