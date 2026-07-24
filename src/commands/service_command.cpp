#include "commands/command_handlers.h"
#include "service/TowerService.h"

int runServiceCommand()
{
    TowerService service;

    if (!service.start())
    {
        return 1;
    }

    service.run();
    service.stop();

    return 0;
}