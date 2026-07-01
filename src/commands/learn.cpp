#include "commands/command_handlers.h"

#include <iostream>

#include "ir/ir_code.h"
#include "ir/ir_database.h"
#include "ir/ir_receiver.h"

int runLearnCommand()
{
    IRReceiver receiver;

    if (!receiver.initialize(23))
    {
        return 1;
    }

    IRCode code;

    if (!receiver.receive(code))
    {
        receiver.shutdown();
        return 1;
    }

    receiver.shutdown();

    code.device = "test_device";
    code.command = "test_command";

    IRDatabase database;

    if (!database.save(code.device, code.command, code))
    {
        return 1;
    }

    std::cout << "IR code captured and saved.\n";

    return 0;
}
