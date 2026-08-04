#pragma once

int runVersionCommand();
int runReceiveCommand();
int runMonitorCommand();
int runServiceCommand();
int runSendCommand(int argc, char* argv[]);
int runLearnCommand(int argc, char* argv[]);
int runLearnWizard();
int runLearnKernelCommand();
int runIRReceiversCommand();
int runIRCaptureCommand(int argc, char* argv[]);
int runIRAnalyzeCommand(int argc, char* argv[]);
int runReplayCommand(int argc, char* argv[]);
int runConfigCommand();
int runSensorCommand();
int runTemperatureCommand(int argc, char* argv[]);
int runDeviceCommand(int argc, char* argv[]);
int runLogicalCommand(int argc, char* argv[]);
int runExecuteCommand(int argc, char* argv[]);
