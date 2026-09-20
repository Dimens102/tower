#!/usr/bin/env python3
"""Convert the existing Set Two/Set Three routines, keeping user data/backups."""
import copy
import datetime
import json
import os
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]

def convert(config, store):
    config, store = copy.deepcopy(config), copy.deepcopy(store)
    children = config['command_tree']['zone']['children']
    devices = {'KPN Media Box', '1610HD', 'AVR X2800H'}
    for leaf, state in [('set two', 'on'), ('set three', 'off')]:
        actions = children[leaf]['actions']
        converted = []
        index = 0
        while index < len(actions):
            action = actions[index]
            index += 1
            device = action.get('device')
            if action.get('type', 'command') != 'command' or device not in devices or action.get('command') != 'Power':
                converted.append(action)
                continue
            key = 'ir:' + device
            if device == '1610HD' and state == 'off':
                if index >= len(actions) or actions[index].get('device') != device or actions[index].get('command') != 'Power' or actions[index].get('delay_before_seconds') != 2:
                    raise ValueError('Dell shutdown differs from the expected two presses / 2 seconds. No files changed.')
                index += 1
            outputs = action.get('transmitters', [])
            store['profiles'].setdefault(key, {
                'discrete': False,
                'on': [{'command': 'Power'}],
                'off': ([{'command': 'Power'}, {'command': 'Power', 'delay_before_seconds': 2}]
                        if device == '1610HD' else [{'command': 'Power'}]),
                'effects': {'Power': 'unknown' if device == '1610HD' else 'toggle'},
                'transmitters': outputs,
            })
            store['states'].setdefault(key, {'state': 'unknown', 'source': 'not initialized', 'updated': 0})
            converted.append({'type': 'device_power', 'device': key, 'state': state,
                              'delay_before_seconds': action.get('delay_before_seconds', 0)})
        children[leaf]['actions'] = converted
    return config, store

def main():
    voice = ROOT / 'data/voice/voice_commands.json'
    states = ROOT / 'data/control/device_states.json'
    original = json.loads(voice.read_text(encoding='utf-8-sig'))
    stored = json.loads(states.read_text()) if states.exists() else {'version': 1, 'profiles': {}, 'states': {}}
    new_voice, new_states = convert(original, stored)
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    for path, data in [(states, new_states), (voice, new_voice)]:
        if path.exists() and json.loads(path.read_text(encoding='utf-8-sig')) == data:
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists():
            shutil.copy2(path, str(path) + '.before-state-' + stamp)
        temporary = path.with_name(path.name + '.state-tmp')
        with temporary.open('w', encoding='utf-8') as output:
            json.dump(data, output, indent=2, ensure_ascii=False)
            output.write('\n'); output.flush(); os.fsync(output.fileno())
        os.replace(temporary, path)
        print('Updated:', path.relative_to(ROOT))
    print('Set Two requests ON; Set Three requests OFF. Schedule times are unchanged.')
    print('Before running them, use Devices > Mark On/Off to record the actual initial state.')

if __name__ == '__main__':
    main()
