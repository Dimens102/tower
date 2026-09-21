#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_build_dir=$(mktemp -d)
trap 'rm -rf "$test_build_dir"' EXIT HUP INT TERM
g++ -std=c++17 -Iinclude -Iexternal tests/device_state_test.cpp \
  src/core/service/DeviceStateService.cpp src/core/service/ActionExecutionService.cpp \
  src/core/service/ScriptService.cpp -pthread -o "$test_build_dir/state-tests"
"$test_build_dir/state-tests"
g++ -std=c++17 -Iinclude -Iexternal tests/script_service_test.cpp \
  src/core/service/ScriptService.cpp -pthread -o "$test_build_dir/script-tests"
"$test_build_dir/script-tests"
g++ -std=c++17 -Iinclude -Iexternal tests/schedule_service_test.cpp \
  src/core/service/ScheduleService.cpp -pthread -o "$test_build_dir/schedule-tests"
"$test_build_dir/schedule-tests"
echo "Scheduler catch-up and duplicate-prevention tests passed"
