{
  host = ["desktop" "usb" "laptop"];

  support = [
    "usb-initrd-ordering"
    "usb-steam"
    "usb-update-integration"
    "hyprland-keybinds"
    "desktop-glass"
    "spotify-runtime"
    "desktop-runtime-config"
    "neovim-langmap"
    "neovim-lsp-health"
    "wallpaper-runtime"
    "codex-skills"
    "codex-clef"
    "bannerlord-codex"
    "bannerlord-speech"
    "bannerlord-speech-unit"
    "desktop-installed-environment"
    "usb-installed-environment"
    "script-smoke"
    "shellcheck"
    "ci-registry"
    "host-configuration-contracts"
  ];

  # CI owns one assignment per check; full flake checks retain the public groups above.
  ci = {
    hostChecks = {
      desktop = ["desktop" "bannerlord-speech" "desktop-installed-environment"];
      usb = ["usb" "usb-initrd-ordering" "usb-steam" "usb-update-integration" "usb-installed-environment"];
      laptop = ["laptop"];
    };
    supportGroups = {
      desktop = ["hyprland-keybinds" "desktop-glass" "spotify-runtime" "desktop-runtime-config" "wallpaper-runtime"];
      neovim = ["neovim-langmap" "neovim-lsp-health"];
      codex = ["codex-skills" "codex-clef" "bannerlord-codex"];
      scripts = ["script-smoke" "shellcheck"];
      registry = ["ci-registry"];
    };
    unitGroups = {
      speech = ["bannerlord-speech-unit"];
      configuration = ["host-configuration-contracts"];
    };
    alwaysUnitGroups = ["configuration"];
    hostCheckSources.installed-environment = ["desktop" "usb"];

    # Coarse source domains avoid maintaining a path list for every individual check.
    domains = {
      desktop = {
        prefixes = ["modules/home/dms/" "modules/home/wallpaper/" "modules/home/vesktop" "modules/home/hyprland" "modules/home/glass" "modules/home/ghostty" "modules/home/gtk" "modules/home/spicetify" "modules/home/skwd-"];
        checkPrefixes = ["hyprland-keybinds" "desktop-glass" "spotify-runtime" "desktop-runtime-config" "wallpaper" "skwd-"];
        support = ["desktop"];
        units = [];
      };
      neovim = {
        prefixes = ["modules/home/neovim"];
        checkPrefixes = ["neovim"];
        support = ["neovim"];
        units = [];
      };
      codex = {
        prefixes = ["modules/home/codex/" "modules/home/bannerlord-codex/" "modules/home/bannerlord/" "modules/home/player2-ai-influence/"];
        checkPrefixes = ["codex-" "bannerlord-codex" "fixtures/codex-"];
        support = ["codex" "scripts"];
        units = [];
      };
      speech = {
        prefixes = ["modules/home/bannerlord-speech/" "modules/home/desktop-dictation/"];
        checkPrefixes = ["bannerlord-speech"];
        support = ["scripts"];
        units = ["speech"];
      };
      usb = {
        prefixes = ["modules/home/scripts/usb/"];
        checkPrefixes = ["usb-"];
        support = ["scripts"];
        units = [];
        hosts = ["desktop" "usb"];
      };
      scripts = {
        prefixes = ["modules/home/scripts/"];
        checkPrefixes = ["script-smoke" "shellcheck"];
        support = ["scripts"];
        units = [];
      };
    };
  };
}
