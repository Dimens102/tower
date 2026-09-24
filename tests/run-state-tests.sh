#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_build_dir=$(mktemp -d)
trap 'rm -rf "$test_build_dir"' EXIT HUP INT TERM
g++ -std=c++17 -Iinclude -Iexternal tests/device_state_test.cpp \
  src/core/service/DeviceStateService.cpp src/core/service/ActionExecutionService.cpp \
  src/core/service/ScriptService.cpp src/core/service/ExecutionDisplay.cpp \
  -pthread -o "$test_build_dir/state-tests"
"$test_build_dir/state-tests"
g++ -std=c++17 -Iinclude -Iexternal tests/script_service_test.cpp \
  src/core/service/ScriptService.cpp -pthread -o "$test_build_dir/script-tests"
"$test_build_dir/script-tests"
g++ -std=c++17 -Iinclude -Iexternal tests/schedule_service_test.cpp \
  src/core/service/ScheduleService.cpp src/core/service/ExecutionDisplay.cpp \
  -pthread -o "$test_build_dir/schedule-tests"
"$test_build_dir/schedule-tests"
echo "Scheduler catch-up and duplicate-prevention tests passed"
g++ -std=c++17 -Iinclude tests/execution_display_test.cpp \
  src/core/service/ExecutionDisplay.cpp -pthread \
  -o "$test_build_dir/execution-display-tests"
"$test_build_dir/execution-display-tests"
echo "Live execution-display sequencing tests passed"

grep -q "'At log off'" windows/Tower-Control-Tab.ps1
grep -q "'On shutdown'" windows/Tower-Control-Tab.ps1
grep -q "'windows_logoff'" windows/Tower-Windows-Schedule-Manager.ps1
grep -q 'EventID=4647' windows/Tower-Windows-Schedule-Manager.ps1
grep -q "'windows_shutdown'" windows/Tower-Windows-Schedule-Manager.ps1
grep -q 'EventID=1074' windows/Tower-Windows-Schedule-Manager.ps1
grep -q 'param5.*power off' windows/Tower-Windows-Schedule-Manager.ps1
grep -q 'Tower-Home-Actions.ps1' windows/Tower-Control.ps1
grep -q '/api/v1/schedules/run' windows/Tower-Home-Actions.ps1
grep -q 'Tower-Home-Action.ps1' windows/Tower-Home-Actions.ps1
grep -q 'scheduleDocument.schedules' windows/Tower-Home-Actions.ps1
grep -q 'WrapContents = \$true' windows/Tower-Home-Actions.ps1
grep -q 'dsScriptId=\[Guid\]::NewGuid' windows/Tower-Devices-Scripts.ps1
grep -q "'\[WOL\]'" windows/Tower-Devices-Scripts.ps1
grep -q "PowerShell window" windows/Tower-Devices-Scripts.ps1
grep -q -- "-RunLevel Highest" windows/Tower-Script-Worker.ps1
grep -q "Tower-Script-Worker.ps1" windows/Tower-Windows-Agent.ps1
grep -q "script worker installed or repaired" windows/Tower-Windows-Agent.ps1
grep -q "exit-code.txt" windows/Tower-Script-Worker.ps1
grep -q "Script completed (\$windowMode, elevated)" windows/Tower-Script-Worker.ps1
if grep -q "Enable Windows worker" windows/Tower-Devices-Scripts.ps1; then
  echo "Manual Windows-worker controls must not return" >&2
  exit 1
fi
grep -q 'sidebarEditHold' windows/Tower-Control.ps1
grep -q 'Clone-ControlSchedule' windows/Tower-Control-Tab.ps1
grep -q 'Add-ControlDraftAction' windows/Tower-Control-Tab.ps1
grep -q 'Button cloned as' windows/Tower-Home-Actions.ps1
grep -q 'Clone-VoiceLevel' windows/Tower-Voice-Tab.ps1
grep -q "'\[WIN\]'" windows/Tower-Control-Tab.ps1
grep -q 'Wake packet sent 3 times' src/core/service/ScriptService.cpp
echo "Windows Home dashboard and power-trigger wiring checks passed"
