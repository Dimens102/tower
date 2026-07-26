#include "devices/rf/rf_sender.h"

#include "core/gpio.h"

#include <cstdlib>
#include <iostream>
#include <sstream>
#include <string>
#include <unistd.h>

static void pulse(GPIO& gpio, int pin, int highUs, int lowUs)
{
     gpio.write(pin, true);
     usleep(highUs);
     gpio.write(pin, false);
     usleep(lowUs);
}

static void sendKakuAcBit(GPIO& gpio, int pin, int period, bool bit)
{
     if (bit)
     {
          pulse(gpio, pin, period, period * 5);
          pulse(gpio, pin, period, period);
     }
     else
     {
          pulse(gpio, pin, period, period);
          pulse(gpio, pin, period, period * 5);
     }
}

static void sendKakuAcStart(GPIO& gpio, int pin, int period)
{
     pulse(gpio, pin, period, period * 10 + (period / 2));
}

static void sendKakuAcStop(GPIO& gpio, int pin, int period)
{
     pulse(gpio, pin, period, period * 40);
}

static bool sendKakuAc(const RFDevice& device, bool turnOn)
{
     GPIO gpio;

     if (!gpio.openChip("/dev/gpiochip0"))
     {
          return false;
     }

     if (!gpio.requestOutput(device.gpio, false))
     {
          return false;
     }

     unsigned long address = std::stoul(device.transmitterId, nullptr, 0);
     int period = device.pulse;
     int repeatCount = device.repeat;

     std::cout << "Sending KAKU AC address=" << device.transmitterId
               << " unit=" << device.unit
               << " action=" << (turnOn ? "on" : "off")
               << "\n";

     for (int repeat = 0; repeat < repeatCount; ++repeat)
     {
          sendKakuAcStart(gpio, device.gpio, period);

          for (int bit = 25; bit >= 0; --bit)
          {
               sendKakuAcBit(gpio, device.gpio, period, (address >> bit) & 1);
          }

          sendKakuAcBit(gpio, device.gpio, period, false);
          sendKakuAcBit(gpio, device.gpio, period, turnOn);

          for (int bit = 3; bit >= 0; --bit)
          {
               sendKakuAcBit(gpio, device.gpio, period, device.unit & (1 << bit));
          }

          sendKakuAcStop(gpio, device.gpio, period);
     }

     gpio.write(device.gpio, false);
     return true;
}

bool RFSender::send(const RFDevice& device, bool turnOn)
{
     if (device.protocol == "kaku_ac")
     {
          return sendKakuAc(device, turnOn);
     }

     if (device.protocol != "kaku_old")
     {
          std::cerr << "RF protocol not implemented yet: " << device.protocol << "\n";
          return false;
     }

     unsigned long code = turnOn ? device.onCode : device.offCode;

     std::ostringstream command;

     command << "rpi-rf_send"
             << " -g " << device.gpio
             << " -t 1"
             << " -p " << device.pulse
             << " -r 20"
             << " " << code
             << " && pinctrl set " << device.gpio << " op dl";

     std::cout << "Sending RF code: " << code << "\n";
     std::cout << "Command: " << command.str() << "\n";

     return std::system(command.str().c_str()) == 0;
}
