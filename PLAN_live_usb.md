# Plan: Persistent NixOS Live USB for Computer Labs

## Problem

The current USB setup is:

- A **persistent NixOS installation** configured for **your specific hardware** (NVIDIA GPU, specific monitors)
- Won't boot on unknown lab hardware (likely fails due to missing drivers)

## Goal

Create a USB that:

1. Boots on **any computer** (generic hardware support)
2. Has **persistent state** (files, settings survive reboot)
3. Can be used for **live demos** in computer labs

## Options Compared

| Method                            | Hardware Agnostic | Persistence | Ease of Use |
| --------------------------------- | ----------------- | ----------- | ----------- |
| Official NixOS ISO                | ✅ Yes            | ❌ No       | Easy        |
| mkusb (Ubuntu tool)               | ✅ Yes            | ✅ Yes      | Easy        |
| Ventoy + Persistence              | ✅ Yes            | ✅ Yes      | Easy        |
| Custom NixOS with generic drivers | ⚠️ Limited        | ✅ Yes      | Hard        |
| Virtual Machine on USB            | ✅ Yes            | ✅ Yes      | Medium      |

## Recommended Approach: Ventoy + Persistence

**Ventoy** is a bootable USB creator that:

- Lets you put multiple ISO files on one USB
- Supports **persistence** via a separate partition
- Works with the official NixOS ISO

### Steps

1. **Download NixOS ISO**
   - Get the latest NixOS live/rescue ISO from https://nixos.org/download.html

2. **Create USB with Ventoy**
   - Install Ventoy on a new USB (using Ventoy's GUI or CLI)
   - Create a persistence partition (e.g., `persistence`)

3. **Configure Persistence**
   - Use Ventoy's `ventoy.json` to enable persistence for NixOS
   - Example config:
     ```json
     {
       "persistence": [
         {
           "image": "/nixos*.iso",
           "persistence": "/persistence"
         }
       ]
     }
     ```

4. **Copy ISO to USB**
   - Place the NixOS ISO in the Ventoy partition
   - Boot and select NixOS with persistence

## Alternative: mkusb

If Ventoy doesn't work well with NixOS, use **mkusb**:

- Specifically designed for Ubuntu/diverse Linux ISOs
- Creates a `casper-rw` partition for persistence
- More tested with non-Ubuntu ISOs

## Implementation Notes

- **Persistence partition size**: Recommend 8-16GB for lab use
- **Data backup**: All data on persistence partition will be preserved
- **Multiple ISOs**: Ventoy lets you have multiple ISOs (NixOS, Ubuntu, etc.)

## Action Items

- [ ] Download NixOS live ISO
- [ ] Get a new USB (or backup existing one)
- [ ] Install Ventoy
- [ ] Configure persistence
- [ ] Test on different hardware

## Keep Your Current USB

Your current USB (`update_usb.sh`) is still useful as:

- A **rescue/recovery** drive for your own machines
- A **backup** if something goes wrong
