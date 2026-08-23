#include "core/commands/command_handlers.h"

#include "core/service/RFCommandService.h"
#include "core/service/RFProvisioningService.h"

#include <iostream>
#include <string>

namespace
{

std::string prompt(
    const std::string& label,
    const std::string& defaultValue = {})
{
    std::cout << label;
    if (!defaultValue.empty())
    {
        std::cout << " [" << defaultValue << "]";
    }
    std::cout << ": ";

    std::string value;
    std::getline(std::cin, value);

    return value.empty()
        ? defaultValue
        : value;
}

bool promptYesNo(
    const std::string& label,
    bool defaultYes = false)
{
    for (;;)
    {
        std::cout
            << label
            << (defaultYes ? " [Y/n]: " : " [y/N]: ");

        std::string answer;
        std::getline(std::cin, answer);

        if (answer.empty())
        {
            return defaultYes;
        }

        if (answer == "y" ||
            answer == "Y" ||
            answer == "yes" ||
            answer == "YES")
        {
            return true;
        }

        if (answer == "n" ||
            answer == "N" ||
            answer == "no" ||
            answer == "NO")
        {
            return false;
        }
    }
}

bool sendAction(
    const std::string& recordName,
    const std::string& action)
{
    RFCommandService sender;
    std::string error;

    if (!sender.send(recordName, action, error))
    {
        std::cerr
            << "RF " << action << " failed: "
            << error << "\n";
        return false;
    }

    return true;
}

int runPairWizard(const std::string& recordName)
{
    std::cout
        << "\nRF receiver pairing\n"
        << "-------------------\n"
        << "Put the physical receiver into learn mode / power it on.\n"
        << "When you press ENTER, Tower immediately sends the normal ON\n"
        << "packet. The device definition repeats that packet 16 times.\n\n"
        << "Press ENTER when the receiver is ready, or type q to skip: ";

    std::string ready;
    std::getline(std::cin, ready);

    if (ready == "q" || ready == "Q")
    {
        std::cout
            << "Pairing skipped. Device remains unpaired.\n";
        return 0;
    }

    for (;;)
    {
        std::cout << "Sending pairing ON...\n";
        if (!sendAction(recordName, "on"))
        {
            return 1;
        }

        if (!promptYesNo(
                "Did the receiver switch ON?",
                false))
        {
            if (promptYesNo(
                    "Retry the ON pairing transmission?",
                    true))
            {
                continue;
            }

            std::cout
                << "Pairing left unconfirmed. "
                << "Device remains unpaired.\n";
            return 0;
        }

        std::cout
            << "Sending OFF test using the same "
            << "transmitter ID + unit...\n";

        if (!sendAction(recordName, "off"))
        {
            return 1;
        }

        if (!promptYesNo(
                "Did the receiver switch OFF?",
                false))
        {
            if (promptYesNo(
                    "Retry the full pairing test?",
                    true))
            {
                continue;
            }

            std::cout
                << "Pairing left unconfirmed. "
                << "Device remains unpaired.\n";
            return 0;
        }

        RFProvisioningService provisioning;
        std::string error;

        if (!provisioning.setPairingStatus(
                recordName,
                true,
                error))
        {
            std::cerr
                << "Pairing worked, but status update failed: "
                << error << "\n";
            return 1;
        }

        std::cout
            << "Pairing confirmed. "
            << "status=paired has been stored.\n";
        return 0;
    }
}

int runAddWizard()
{
    RFProvisioningService provisioning;
    RFModernDefaults defaults;
    std::string error;

    if (!provisioning.getNextModernDefaults(
            defaults,
            error))
    {
        std::cerr << error << "\n";
        return 1;
    }

    std::cout
        << "Tower RF Power - Add Modern KAKU Device\n"
        << "=======================================\n\n"
        << "Next RF definition : "
        << defaults.recordName << ".rf\n"
        << "Preferred next ID  : "
        << defaults.transmitterId << "\n\n"
        << "NOTE: transmitter IDs are hexadecimal.\n"
        << "Current project IDs run 0x123456 ... 0x123459,\n"
        << "so the next value is 0x12345A.\n\n";

    const std::string deviceName =
        prompt("Device name");

    if (deviceName.empty())
    {
        std::cerr << "Device name is required.\n";
        return 1;
    }

    const std::string description =
        prompt(
            "Description",
            defaults.description);

    const std::string transmitterId =
        prompt(
            "Modern KAKU transmitter ID",
            defaults.transmitterId);

    const std::string unitText =
        prompt(
            "Unit",
            std::to_string(defaults.unit));

    int unit = defaults.unit;
    try
    {
        unit = std::stoi(unitText);
    }
    catch (...)
    {
        std::cerr << "Unit must be a number.\n";
        return 1;
    }

    std::cout
        << "\nCreate:\n"
        << "  " << defaults.recordName << ".rf\n"
        << "  device_name=" << deviceName << "\n"
        << "  description=" << description << "\n"
        << "  transmitter_id=" << transmitterId << "\n"
        << "  unit=" << unit << "\n"
        << "  status=unpaired\n\n";

    if (!promptYesNo("Create this RF device?", true))
    {
        std::cout << "Cancelled.\n";
        return 0;
    }

    RFDevice created;
    if (!provisioning.createModernPowerDevice(
            deviceName,
            description,
            transmitterId,
            unit,
            created,
            error))
    {
        std::cerr << error << "\n";
        return 1;
    }

    std::cout
        << "Created data/rf/power/"
        << created.name
        << ".rf\n";

    if (!promptYesNo(
            "Pair this receiver now?",
            false))
    {
        std::cout
            << "Pairing skipped. "
            << "The RF definition remains status=unpaired.\n";
        return 0;
    }

    return runPairWizard(created.name);
}

void printRfUsage()
{
    std::cout
        << "Usage:\n"
        << "  tower rf add\n"
        << "  tower rf pair <Tower-RF-Power-M2-xxx>\n"
        << "  tower rf next\n";
}

} // namespace

int runRFCommand(int argc, char* argv[])
{
    if (argc < 3)
    {
        printRfUsage();
        return 1;
    }

    const std::string subcommand = argv[2];

    if (subcommand == "add")
    {
        return runAddWizard();
    }

    if (subcommand == "pair")
    {
        if (argc < 4)
        {
            std::cerr
                << "Usage: tower rf pair "
                << "<Tower-RF-Power-M2-xxx>\n";
            return 1;
        }

        return runPairWizard(argv[3]);
    }

    if (subcommand == "next")
    {
        RFProvisioningService provisioning;
        RFModernDefaults defaults;
        std::string error;

        if (!provisioning.getNextModernDefaults(
                defaults,
                error))
        {
            std::cerr << error << "\n";
            return 1;
        }

        std::cout
            << "record=" << defaults.recordName << "\n"
            << "transmitter_id="
            << defaults.transmitterId << "\n"
            << "description="
            << defaults.description << "\n"
            << "unit=" << defaults.unit << "\n"
            << "gpio=" << defaults.gpio << "\n"
            << "pulse=" << defaults.pulse << "\n"
            << "repeat=" << defaults.repeat << "\n";

        return 0;
    }

    printRfUsage();
    return 1;
}
