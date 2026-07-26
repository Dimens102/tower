#pragma once

class RFReceiver
{
public:
    bool initialize(int gpio);
    void start();
    void stop();
};
