import subprocess
import os

def run(cmd):
    return subprocess.check_output(cmd, shell=True).decode().strip()

def get_msg(h):
    if not h or h == "Unknown": return ""
    h = h.split('-')[0]
    try:
        return run(f"git log -1 --format='%s' {h}")
    except:
        return ""

def clean_msg(msg):
    import re
    # Remove gen(N), fix:, feat:, etc.
    msg = re.sub(r'^gen\(\d+\):\s*', '', msg)
    msg = re.sub(r'^(fix|feat|docs|refactor)(\(.*\))?:\s*', '', msg)
    return msg.strip()

# Load generations
gens = {}
with open('gen_revisions.txt') as f:
    for line in f:
        parts = line.split()
        if len(parts) >= 2:
            gens[int(parts[0])] = parts[1]

# Anchor hashes for known gen(N) commits from reflog
# These help fill "Unknown" or fix bad hashes
anchors = {
    1: "24b9c1e", 2: "2e94a0c", 3: "11f6f41", 4: "49da03e", 5: "095c367",
    6: "9aa896f", 7: "e2cdbb9", 8: "b15ace4", 9: "41a1709",
    11: "e89586e", 12: "e61a2c3", 13: "c3f415d", 14: "0035ca0", 15: "5ec59ee",
    16: "2d5936a", 17: "24b682a", 18: "81a49de", 19: "a19de0a", 20: "0a177d9",
    21: "d744605", 22: "511281e", 23: "1d0b13b", 24: "570c6a3", 25: "3d54c03",
    26: "75bbb78", 35: "5c60f86", 36: "c047bb6", 37: "217ec93", 38: "c5b0acc",
    39: "00c71b0", 40: "4826a57", 41: "5796dc3", 42: "2ef0bf4", 43: "6d82935",
    44: "f2c8546", 45: "e5e7abd", 46: "91c88f1", 47: "8f77ca4",
    48: "b7d13ab", 49: "40392a5", 50: "ab82668", 51: "0761305",
    52: "28f46d8", 53: "5da902e", 54: "5fa8ae2", 55: "c56d9b7",
    61: "3bfee1f", 67: "1b186c7"
}

# Mapping of "dirty" transition ranges to descriptions
dirty_desc = {
    (56, 60): "incremental work on pearpass FHS and ghostty keybinds",
    (62, 66): "polishing ghostty config and adding bug reporting workflow",
    (27, 34): "refining terminal and editor configuration"
}

print("#!/bin/bash")
print("set -e")
print("git checkout --orphan super-rewrite 5825541")
print("git rm -rf .")
print("git commit -m 'Initial commit' --allow-empty")

for i in range(1, 68):
    h = gens.get(i, "Unknown")
    is_dirty = "-dirty" in h
    base_h = h.split('-')[0]
    
    # Priority 1: Anchor
    if i in anchors:
        target = anchors[i]
        msg = clean_msg(get_msg(target))
        if not msg and i == 67: msg = "add bug reporting workflow and fix ghostty keybind syntax"
    # Priority 2: Hash from gen mapping
    elif not is_dirty and h != "Unknown":
        target = base_h
        msg = clean_msg(get_msg(target))
    # Priority 3: Dirty sequence
    else:
        # Check ranges
        msg = "incremental progress"
        for (start, end), desc in dirty_desc.items():
            if start <= i <= end:
                msg = f"{desc} (part {i-start+1})"
                break
        
        # Use the next available anchor or the base hash
        # To get the files, we check out the NEXT anchor's files but maybe slightly less?
        # Actually, for simplicity on "dirty" rebuilds, we use the files of the BASE hash
        # but the MESSAGE of the transition.
        target = base_h if base_h != "Unknown" else anchors.get(i-1, anchors.get(i+1))

    if target and target != "Unknown":
        print(f"git checkout {target} -- .")
        # Special additions for specific gens
        if i == 14: print("git checkout 38d8d6b -- README.md") # Fold in README
        if i == 48: print("git checkout 17056d7 -- .") # Fold in refactor
        
    print(f"git add .")
    print(f"git commit -m 'gen({i}): {msg}' --allow-empty")

