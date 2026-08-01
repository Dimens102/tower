#include "devices/ir/ir_analyzer.h"

#include "devices/ir/ir_receiver_array.h"

#include <algorithm>
#include <cmath>
#include <fstream>
#include <map>
#include <numeric>
#include <optional>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <tuple>
#include <utility>

namespace
{
constexpr unsigned FrameGapUs = 10000;

struct Event
{
    bool pulse = false;
    unsigned duration = 0;
};

using Frame = std::vector<Event>;

double error(unsigned actual, unsigned expected)
{
    return std::abs(static_cast<double>(actual) - expected) / expected;
}

double mean(const std::vector<double>& values)
{
    return values.empty()
        ? 1.0
        : std::accumulate(values.begin(), values.end(), 0.0) / values.size();
}

std::pair<std::vector<Event>, std::vector<Frame>> parse(
    const std::filesystem::path& path)
{
    std::ifstream input(path);
    if (!input)
    {
        throw std::runtime_error("Could not open " + path.string());
    }

    std::vector<Event> events;
    std::vector<Frame> frames;
    Frame current;
    std::string line;
    std::size_t lineNumber = 0;

    while (std::getline(input, line))
    {
        ++lineNumber;
        if (line.empty() || line[0] == '#')
        {
            continue;
        }

        std::istringstream fields(line);
        std::string kind;
        unsigned duration = 0;
        std::string extra;
        if (!(fields >> kind >> duration) || (fields >> extra) ||
            (kind != "pulse" && kind != "space" && kind != "timeout"))
        {
            throw std::runtime_error(
                path.string() + ":" + std::to_string(lineNumber) +
                ": invalid mode2 line");
        }

        if (kind == "timeout" || (kind == "space" && duration >= FrameGapUs))
        {
            if (!current.empty())
            {
                frames.push_back(std::move(current));
                current.clear();
            }
            continue;
        }

        const Event event{kind == "pulse", duration};
        events.push_back(event);
        current.push_back(event);
    }

    if (!current.empty())
    {
        frames.push_back(std::move(current));
    }
    return {events, frames};
}

std::optional<IRDecode> decodeManchester(const Frame& frame)
{
    std::vector<unsigned> shortDurations;
    for (const Event& event : frame)
    {
        if (event.duration >= 180 && event.duration <= 450)
        {
            shortDurations.push_back(event.duration);
        }
    }
    if (shortDurations.size() < 4)
    {
        return std::nullopt;
    }
    std::sort(shortDurations.begin(), shortDurations.end());
    const double base = shortDurations[shortDurations.size() / 2];

    std::vector<bool> levels;
    std::vector<double> errors;
    for (const Event& event : frame)
    {
        const unsigned units = static_cast<unsigned>(std::lround(event.duration / base));
        if (units < 1 || units > 2)
        {
            return std::nullopt;
        }
        const double relative =
            std::abs(event.duration - units * base) / (units * base);
        if (relative > 0.55)
        {
            return std::nullopt;
        }
        errors.push_back(relative);
        levels.insert(levels.end(), units, event.pulse);
    }

    if (levels.size() != 46 && levels.size() != 36)
    {
        return std::nullopt;
    }

    std::vector<bool> bits;
    for (std::size_t index = 0; index < levels.size(); index += 2)
    {
        if (levels[index] == levels[index + 1])
        {
            return std::nullopt;
        }
        bits.push_back(levels[index] && !levels[index + 1]);
    }
    if (!bits.front())
    {
        return std::nullopt;
    }

    const bool siemens = bits.size() == 23;
    const std::size_t addressBits = siemens ? 11 : 9;
    const std::size_t commandBits = siemens ? 10 : 7;
    unsigned address = 0;
    unsigned rawCommand = 0;
    for (std::size_t index = 0; index < addressBits; ++index)
    {
        address = (address << 1) | bits[1 + index];
    }
    for (std::size_t index = 0; index < commandBits; ++index)
    {
        rawCommand = (rawCommand << 1) | bits[1 + addressBits + index];
    }
    const bool inverse = bits.back();
    const bool preceding = bits[bits.size() - 2];
    if (inverse == preceding)
    {
        return std::nullopt;
    }

    return IRDecode{
        siemens ? "Siemens" : "Ruwido",
        address,
        siemens ? (rawCommand & 0x7F) : rawCommand,
        rawCommand,
        siemens && (rawCommand & 0x80),
        mean(errors),
    };
}

std::optional<IRDecode> decodeNec(const Frame& frame)
{
    if (frame.size() != 67)
    {
        return std::nullopt;
    }
    for (std::size_t index = 0; index < frame.size(); ++index)
    {
        if (frame[index].pulse != (index % 2 == 0))
        {
            return std::nullopt;
        }
    }
    if (error(frame[0].duration, 9000) > 0.30 ||
        error(frame[1].duration, 4500) > 0.30)
    {
        return std::nullopt;
    }

    std::vector<unsigned> bits;
    std::vector<double> errors = {
        error(frame[0].duration, 9000), error(frame[1].duration, 4500)};
    for (std::size_t index = 2; index < 66; index += 2)
    {
        const unsigned bit = frame[index + 1].duration >= 1125;
        const unsigned expectedSpace = bit ? 1687 : 562;
        if (error(frame[index].duration, 562) > 0.45 ||
            error(frame[index + 1].duration, expectedSpace) > 0.45)
        {
            return std::nullopt;
        }
        bits.push_back(bit);
        errors.push_back(error(frame[index].duration, 562));
        errors.push_back(error(frame[index + 1].duration, expectedSpace));
    }
    if (error(frame[66].duration, 562) > 0.45)
    {
        return std::nullopt;
    }
    errors.push_back(error(frame[66].duration, 562));

    unsigned bytes[4] = {};
    for (unsigned byte = 0; byte < 4; ++byte)
    {
        for (unsigned bit = 0; bit < 8; ++bit)
        {
            bytes[byte] |= bits[byte * 8 + bit] << bit;
        }
    }
    if (bytes[3] != (bytes[2] ^ 0xFFU))
    {
        return std::nullopt;
    }
    const bool standard = bytes[1] == (bytes[0] ^ 0xFFU);
    return IRDecode{
        standard ? "NEC" : "NECx",
        standard ? bytes[0] : bytes[0] | (bytes[1] << 8),
        bytes[2],
        bytes[2],
        false,
        mean(errors),
    };
}

std::optional<IRDecode> decodeNecRepeat(
    const Frame& frame,
    const std::optional<IRDecode>& previous)
{
    if (!previous || (previous->protocol != "NEC" && previous->protocol != "NECx") ||
        frame.size() != 3 || !frame[0].pulse || frame[1].pulse || !frame[2].pulse)
    {
        return std::nullopt;
    }
    const unsigned expected[] = {9000, 2250, 562};
    std::vector<double> errors;
    for (std::size_t index = 0; index < 3; ++index)
    {
        const double relative = error(frame[index].duration, expected[index]);
        if (relative > 0.35)
        {
            return std::nullopt;
        }
        errors.push_back(relative);
    }
    IRDecode decoded = *previous;
    decoded.repeat = true;
    decoded.timingError = mean(errors);
    return decoded;
}

std::optional<IRDecode> decodeSony(const Frame& frame)
{
    if (frame.size() != 25 || !frame[0].pulse || error(frame[0].duration, 2400) > 0.30)
    {
        return std::nullopt;
    }
    std::vector<unsigned> bits;
    std::vector<double> errors = {error(frame[0].duration, 2400)};
    for (std::size_t index = 1; index < 25; index += 2)
    {
        if (frame[index].pulse || !frame[index + 1].pulse)
        {
            return std::nullopt;
        }
        const unsigned bit = frame[index + 1].duration >= 900;
        const unsigned expectedPulse = bit ? 1200 : 600;
        if (error(frame[index].duration, 600) > 0.40 ||
            error(frame[index + 1].duration, expectedPulse) > 0.40)
        {
            return std::nullopt;
        }
        bits.push_back(bit);
        errors.push_back(error(frame[index].duration, 600));
        errors.push_back(error(frame[index + 1].duration, expectedPulse));
    }
    unsigned command = 0;
    unsigned address = 0;
    for (unsigned bit = 0; bit < 7; ++bit) command |= bits[bit] << bit;
    for (unsigned bit = 0; bit < 5; ++bit) address |= bits[7 + bit] << bit;
    return IRDecode{"Sony SIRC-12", address, command, command, false, mean(errors)};
}

std::optional<IRDecode> decodeKaseikyo(const Frame& frame)
{
    constexpr unsigned unit = 432;
    if (frame.size() != 99)
    {
        return std::nullopt;
    }
    for (std::size_t index = 0; index < frame.size(); ++index)
    {
        if (frame[index].pulse != (index % 2 == 0)) return std::nullopt;
    }
    if (error(frame[0].duration, 8 * unit) > 0.30 ||
        error(frame[1].duration, 4 * unit) > 0.30)
    {
        return std::nullopt;
    }

    std::vector<unsigned> bits;
    std::vector<double> errors = {
        error(frame[0].duration, 8 * unit), error(frame[1].duration, 4 * unit)};
    for (std::size_t index = 2; index < 98; index += 2)
    {
        const unsigned bit = frame[index + 1].duration >= 2 * unit;
        const unsigned expectedSpace = (bit ? 3 : 1) * unit;
        if (error(frame[index].duration, unit) > 0.45 ||
            error(frame[index + 1].duration, expectedSpace) > 0.45)
        {
            return std::nullopt;
        }
        bits.push_back(bit);
        errors.push_back(error(frame[index].duration, unit));
        errors.push_back(error(frame[index + 1].duration, expectedSpace));
    }
    if (error(frame[98].duration, unit) > 0.45) return std::nullopt;
    errors.push_back(error(frame[98].duration, unit));

    unsigned bytes[6] = {};
    for (unsigned byte = 0; byte < 6; ++byte)
        for (unsigned bit = 0; bit < 8; ++bit)
            bytes[byte] |= bits[byte * 8 + bit] << bit;

    const unsigned manufacturer = bytes[0] | (bytes[1] << 8);
    const unsigned parity =
        (bytes[0] ^ (bytes[0] >> 4) ^ bytes[1] ^ (bytes[1] >> 4)) & 0x0F;
    if ((bytes[2] & 0x0F) != parity || bytes[5] != (bytes[2] ^ bytes[3] ^ bytes[4]))
    {
        return std::nullopt;
    }
    static const std::map<unsigned, std::string> variants = {
        {0x3254, "Kaseikyo-Denon"}, {0x4004, "Kaseikyo-Panasonic"},
        {0x0103, "Kaseikyo-JVC"}, {0x5AAA, "Kaseikyo-Sharp"},
        {0xCB23, "Kaseikyo-Mitsubishi"},
    };
    const auto variant = variants.find(manufacturer);
    return IRDecode{
        variant == variants.end() ? "Kaseikyo" : variant->second,
        bytes[3], bytes[4], bytes[4], false, mean(errors)};
}

std::optional<IRDecode> decodeFrame(const Frame& frame)
{
    if (auto decoded = decodeManchester(frame)) return decoded;
    if (auto decoded = decodeNec(frame)) return decoded;
    if (auto decoded = decodeSony(frame)) return decoded;
    return decodeKaseikyo(frame);
}

int expectedCarrier(const std::string& protocol)
{
    if (protocol == "Siemens") return 56;
    if (protocol == "Ruwido") return 36;
    if (protocol == "NEC" || protocol == "NECx") return 38;
    if (protocol == "Sony SIRC-12") return 40;
    if (protocol.compare(0, 8, "Kaseikyo") == 0) return 37;
    return 0;
}

auto rank(const IRReceiverAnalysis& item)
{
    const IRFileAnalysis& analysis = item.analysis;
    const double ratio = analysis.frameCount
        ? static_cast<double>(analysis.decodedCount) / analysis.frameCount
        : 0.0;
    const int expected = expectedCarrier(analysis.protocol);
    const int carrierFit = expected
        ? -std::abs(static_cast<int>(item.nominalCarrierKhz) - expected)
        : -99;
    return std::make_tuple(
        analysis.decodedCount, ratio, carrierFit, -analysis.meanTimingError);
}
} // namespace

std::string IRFileAnalysis::result() const
{
    if (eventCount == 0) return "NO-SIGNAL";
    if (decodedCount == 0) return "FAILED";
    if (decodedCount == frameCount && consistency == 1.0) return "CLEAN";
    return "PARTIAL";
}

IRFileAnalysis IRAnalyzer::analyzeFile(const std::filesystem::path& path) const
{
    const auto parsed = parse(path);
    const std::vector<Event>& events = parsed.first;
    const std::vector<Frame>& frames = parsed.second;
    std::vector<IRDecode> decodes;
    std::optional<IRDecode> previous;
    for (const Frame& frame : frames)
    {
        std::optional<IRDecode> decoded = decodeFrame(frame);
        if (!decoded) decoded = decodeNecRepeat(frame, previous);
        if (decoded)
        {
            decodes.push_back(*decoded);
            previous = decoded;
        }
    }

    IRFileAnalysis analysis;
    analysis.path = path;
    analysis.eventCount = events.size();
    analysis.frameCount = frames.size();
    analysis.decodedCount = decodes.size();
    if (decodes.empty()) return analysis;

    using Identity = std::tuple<std::string, unsigned, unsigned>;
    std::map<Identity, std::size_t> counts;
    for (const IRDecode& decoded : decodes)
        ++counts[{decoded.protocol, decoded.address, decoded.command}];
    const auto winner = std::max_element(
        counts.begin(), counts.end(),
        [](const auto& left, const auto& right) { return left.second < right.second; });
    analysis.protocol = std::get<0>(winner->first);
    analysis.address = std::get<1>(winner->first);
    analysis.command = std::get<2>(winner->first);
    analysis.consistency = static_cast<double>(winner->second) / decodes.size();

    std::vector<double> timingErrors;
    for (const IRDecode& decoded : decodes)
    {
        if (decoded.protocol == analysis.protocol && decoded.address == analysis.address &&
            decoded.command == analysis.command)
        {
            timingErrors.push_back(decoded.timingError);
            decoded.repeat ? ++analysis.repeatFrames : ++analysis.initialFrames;
        }
    }
    analysis.meanTimingError = mean(timingErrors);
    return analysis;
}

std::vector<IRReceiverAnalysis> IRAnalyzer::analyzeDirectory(
    const std::filesystem::path& directory) const
{
    if (!std::filesystem::is_directory(directory))
        throw std::runtime_error("Capture directory does not exist: " + directory.string());

    std::map<unsigned, IRReceiverDefinition> definitions;
    for (const IRReceiverDefinition& receiver : IRReceiverArray::definitions())
        definitions.emplace(static_cast<unsigned>(receiver.gpio), receiver);

    const std::regex namePattern(R"(^gpio([0-9]+)_([0-9]+)khz\.mode2$)");
    std::vector<IRReceiverAnalysis> analyses;
    for (const auto& entry : std::filesystem::directory_iterator(directory))
    {
        std::smatch match;
        const std::string name = entry.path().filename().string();
        if (!entry.is_regular_file() || !std::regex_match(name, match, namePattern)) continue;
        const unsigned gpio = std::stoul(match[1].str());
        const unsigned khz = std::stoul(match[2].str());
        const auto definition = definitions.find(gpio);
        analyses.push_back({
            gpio,
            definition == definitions.end() ? "Unknown" : definition->second.model,
            khz,
            analyzeFile(entry.path()),
        });
    }
    std::sort(analyses.begin(), analyses.end(), [](const auto& left, const auto& right) {
        return left.nominalCarrierKhz < right.nominalCarrierKhz;
    });
    if (analyses.empty())
        throw std::runtime_error("No receiver recordings found in " + directory.string());
    return analyses;
}

std::size_t IRAnalyzer::best(const std::vector<IRReceiverAnalysis>& analyses) const
{
    if (analyses.empty()) throw std::invalid_argument("No analyses to rank");
    return static_cast<std::size_t>(std::distance(
        analyses.begin(),
        std::max_element(analyses.begin(), analyses.end(), [](const auto& left, const auto& right) {
            return rank(left) < rank(right);
        })));
}

IRRepresentativeFrame IRAnalyzer::representativeFrame(
    const IRFileAnalysis& analysis) const
{
    if (analysis.protocol.empty() || analysis.decodedCount == 0)
        throw std::invalid_argument("Analysis has no stable decode");

    const auto parsed = parse(analysis.path);
    std::optional<IRRepresentativeFrame> bestFrame;
    for (const Frame& frame : parsed.second)
    {
        const std::optional<IRDecode> decoded = decodeFrame(frame);
        if (!decoded || decoded->repeat || decoded->protocol != analysis.protocol ||
            decoded->address != analysis.address || decoded->command != analysis.command)
        {
            continue;
        }

        IRRepresentativeFrame candidate;
        candidate.decode = *decoded;
        candidate.durations.reserve(frame.size());
        for (const Event& event : frame)
        {
            candidate.durations.push_back(event.duration);
        }
        if (!bestFrame || candidate.decode.timingError < bestFrame->decode.timingError)
            bestFrame = std::move(candidate);
    }

    if (!bestFrame)
        throw std::runtime_error("No validated initial frame found in " + analysis.path.string());
    return *bestFrame;
}

unsigned int IRAnalyzer::carrierKhz(const std::string& protocol) const
{
    return static_cast<unsigned int>(std::max(0, expectedCarrier(protocol)));
}
