# PearPass Fix Plan

## Problem

PearPass fails to launch with the error:
`Error: libwebkitgtk-6.0.so.4: cannot open shared object file: No such file or directory`

This indicates that while `webkitgtk_6_0` might have been present in previous attempts, it is either missing from the current FHS environment definition or not being located correctly by the `bare` runtime used by PearPass (which seems to be an Electron/Node-like environment).

## Solution

1.  **Add `webkitgtk_6_0`:** Explicitly add `webkitgtk_6_0` to the `targetPkgs` list in `modules/pearpass.nix`.
2.  **Verify Environment:** Ensure that other potential dependencies for WebKit (like `libsoup_3`) are also present, as WebKit often depends on them.

## Changes

### 1. Update `modules/pearpass.nix`

Modify the `pearpassApp` definition (using `appimageTools.wrapType2`) to include `webkitgtk_6_0` in `extraPkgs`.

_Note: In the previous successful FHS attempt, I used `buildFHSUserEnv` but then switched back to `wrapType2` because `buildFHSUserEnv` was deprecated/removed. The `wrapType2` function also creates an FHS environment, but we must ensure the `extraPkgs` list is comprehensive._

```nix
  pearpassApp = pkgs.appimageTools.wrapType2 {
    # ...
    extraPkgs = pkgs:
      with pkgs; [
        # ... existing packages ...
        webkitgtk_6_0  # <--- CRITICAL ADDITION
        libsoup_3      # Ensure this is present
        # ...
      ];
  };
```

## Verification

1.  **Rebuild:** Run `nixos-rebuild switch`.
2.  **Test:** Run `pearpass` from the terminal. It should now launch the GUI.
3.  **Test Native:** The browser extension native messaging should now also work since the main binary can load its dependencies.
