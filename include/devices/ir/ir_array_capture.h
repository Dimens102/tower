#pragma once

#include "devices/ir/ir_receiver_array.h"

#include <filesystem>
#include <string>
#include <vector>

struct IRArrayCaptureResult
{
    IRReceiverStatus receiver;
    std::filesystem::path recordingPath;
    std::size_t timingCount = 0;
    std::size_t pulseCount = 0;
    std::string diagnostic;
    bool started = false;
};

bool irCaptureDiagnosticHasError(const std::string& diagnostic);

class IRArrayCapture
{
public:
    explicit IRArrayCapture(std::string mode2Executable = "mode2");

    std::vector<IRArrayCaptureResult> capture(
        const std::vector<IRReceiverStatus>& receivers,
        const std::filesystem::path& destination,
        double seconds) const;

private:
    std::string mode2Executable_;
};
