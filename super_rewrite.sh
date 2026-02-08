#!/bin/bash
set -e
git checkout --orphan super-rewrite 5825541
git rm -rf .
git commit -m 'Initial commit' --allow-empty
git checkout 24b9c1e -- .
git add .
git commit -m 'gen(1): fresh nixos install using calamares' --allow-empty
git checkout 2e94a0c -- .
git add .
git commit -m 'gen(2): add neovim, brave, discord' --allow-empty
git checkout 11f6f41 -- .
git add .
git commit -m 'gen(3): migrate to flakes, home-manager, and hyprland' --allow-empty
git checkout 49da03e -- .
git add .
git commit -m 'gen(4): add opencode and gh' --allow-empty
git checkout 095c367 -- .
git add .
git commit -m 'gen(5): minor tweaks' --allow-empty
git checkout 9aa896f -- .
git add .
git commit -m 'gen(6): testing config' --allow-empty
git checkout e2cdbb9 -- .
git add .
git commit -m 'gen(7): fix suspend, add spotify, ghostty bind' --allow-empty
git checkout b15ace4 -- .
git add .
git commit -m 'gen(8): modularize config, pearpass & keybinds' --allow-empty
git checkout 41a1709 -- .
git add .
git commit -m 'gen(9): add steam, gamemode, revision tracking & specialisation' --allow-empty
git checkout 8dd165b3db3d7c7d1d5dda6fde7b59e36915064f -- .
git add .
git commit -m 'gen(10): incremental progress' --allow-empty
git checkout e89586e -- .
git add .
git commit -m 'gen(11): enable passwordless rebuild & fix spec option' --allow-empty
git checkout e61a2c3 -- .
git add .
git commit -m 'gen(12): dracula theme for nvim & config fixes' --allow-empty
git checkout c3f415d -- .
git add .
git commit -m 'gen(13): add go, python, prettier & opencode theme' --allow-empty
git checkout 0035ca0 -- .
git checkout 38d8d6b -- README.md
git add .
git commit -m 'gen(14): fix mcp config schema' --allow-empty
git checkout 5ec59ee -- .
git add .
git commit -m 'gen(15): fix hyprland shadow syntax & update agents rules' --allow-empty
git checkout 2d5936a -- .
git add .
git commit -m 'gen(16): manage xdg user dirs & cleanup agents.md' --allow-empty
git checkout 24b682a -- .
git add .
git commit -m 'gen(17): enable home-manager backups' --allow-empty
git checkout 81a49de -- .
git add .
git commit -m 'gen(18): set brave default & add pre-commit hook' --allow-empty
git checkout a19de0a -- .
git add .
git commit -m 'gen(19): cleanup config & enable nix-ld' --allow-empty
git checkout 0a177d9 -- .
git add .
git commit -m 'gen(20): enable touchpad & update agents rules' --allow-empty
git checkout d744605 -- .
git add .
git commit -m 'gen(21): update terminology & fix hyprland kbd variant' --allow-empty
git checkout 511281e -- .
git add .
git commit -m 'gen(22): add nvim alt+up/down line movement' --allow-empty
git checkout 1d0b13b -- .
git add .
git commit -m 'gen(23): mount games disk, add vim tools & icon themes' --allow-empty
git checkout 570c6a3 -- .
git add .
git commit -m 'gen(24): remove GNOME bloat, fix vimtutor alias & hide nvim wrapper' --allow-empty
git checkout 3d54c03 -- .
git add .
git commit -m 'gen(25): fix vimtutor, remove more GNOME bloat & add cyberpunk wallpaper' --allow-empty
git checkout 75bbb78 -- .
git add .
git commit -m 'gen(26): fix PearPass dependencies & finalize vimtutor alias' --allow-empty
git checkout 3d54c03714d5abb761d60d316502f2259ce63606 -- .
git add .
git commit -m 'gen(27): refining terminal and editor configuration (part 1)' --allow-empty
git checkout 3d54c03714d5abb761d60d316502f2259ce63606 -- .
git add .
git commit -m 'gen(28): refining terminal and editor configuration (part 2)' --allow-empty
git checkout 3d54c03714d5abb761d60d316502f2259ce63606 -- .
git add .
git commit -m 'gen(29): refining terminal and editor configuration (part 3)' --allow-empty
git checkout 3d54c03714d5abb761d60d316502f2259ce63606 -- .
git add .
git commit -m 'gen(30): refining terminal and editor configuration (part 4)' --allow-empty
git checkout c8a018ff71628a874d8ab49a5a87afead6d9b222 -- .
git add .
git commit -m 'gen(31): fix PearPass dependencies & finalize vimtutor alias' --allow-empty
git checkout e6745343f7a26042145e4cee43cfb03dbff46d2a -- .
git add .
git commit -m 'gen(32): fix PearPass dependencies & finalize vimtutor alias' --allow-empty
git checkout fbbe0e762be4bc850c0b726189fb1157df4c0030 -- .
git add .
git commit -m 'gen(33): unhide geary, add ruff & opencode formatters' --allow-empty
git checkout fbbe0e762be4bc850c0b726189fb1157df4c0030 -- .
git add .
git commit -m 'gen(34): refining terminal and editor configuration (part 8)' --allow-empty
git checkout 5c60f86 -- .
git add .
git commit -m 'gen(35): unhide geary, add ruff & opencode formatters' --allow-empty
git checkout c047bb6 -- .
git add .
git commit -m 'gen(36): add nerd-fonts to home-manager' --allow-empty
git checkout 217ec93 -- .
git add .
git commit -m 'gen(37): switch to GRUB with Hollow Knight theme & unhide geary' --allow-empty
git checkout c5b0acc -- .
git add .
git commit -m 'gen(38): fix pearpass libs, add local bin to path & cleanup' --allow-empty
git checkout 00c71b0 -- .
git add .
git commit -m 'gen(39): add more pearpass libs, fix path for vimtutor & update agents docs' --allow-empty
git checkout 4826a57 -- .
git add .
git commit -m 'gen(40): add PearPass desktop entry & finalize config' --allow-empty
git checkout 5796dc3 -- .
git add .
git commit -m 'gen(41): minor tweaks' --allow-empty
git checkout 2ef0bf4 -- .
git add .
git commit -m 'gen(42): fix pearpass pairing & icon, add context sync rule' --allow-empty
git checkout 6d82935 -- .
git add .
git commit -m 'gen(43): minor tweaks & log cleanup' --allow-empty
git checkout f2c8546 -- .
git add .
git commit -m 'gen(44): minor tweaks' --allow-empty
git checkout e5e7abd -- .
git add .
git commit -m 'gen(45): minor tweaks' --allow-empty
git checkout 91c88f1 -- .
git add .
git commit -m 'gen(46): fix pearpass native host, icon & naming' --allow-empty
git checkout 8f77ca4 -- .
git add .
git commit -m 'gen(47): fix pearpass native host, icon & naming' --allow-empty
git checkout b7d13ab -- .
git checkout 17056d7 -- .
git add .
git commit -m 'gen(48): resolve gnome deprecation warnings' --allow-empty
git checkout 40392a5 -- .
git add .
git commit -m 'gen(49): force 1920x1080 resolution to center theme' --allow-empty
git checkout ab82668 -- .
git add .
git commit -m 'gen(50): move grub keybinds and downgrade nvidia to production' --allow-empty
git checkout 0761305 -- .
git add .
git commit -m 'gen(51): perfectly center logo and menu elements' --allow-empty
git checkout 28f46d8 -- .
git add .
git commit -m 'gen(52): add greek keyboard layout (Super+Space)' --allow-empty
git checkout 5da902e -- .
git add .
git commit -m 'gen(53): switch to open nvidia modules and fix pearpass icon/runtime' --allow-empty
git checkout 5fa8ae2 -- .
git add .
git commit -m 'gen(54): force s2idle for nvidia, center grub, debug pearpass' --allow-empty
git checkout c56d9b7 -- .
git add .
git commit -m 'gen(55): update pearpass to use robust FHS environment' --allow-empty
git checkout c56d9b7a42433e5c58d1a558933e741a7a368cd9 -- .
git add .
git commit -m 'gen(56): incremental work on pearpass FHS and ghostty keybinds (part 1)' --allow-empty
git checkout c56d9b7a42433e5c58d1a558933e741a7a368cd9 -- .
git add .
git commit -m 'gen(57): incremental work on pearpass FHS and ghostty keybinds (part 2)' --allow-empty
git checkout c56d9b7a42433e5c58d1a558933e741a7a368cd9 -- .
git add .
git commit -m 'gen(58): incremental work on pearpass FHS and ghostty keybinds (part 3)' --allow-empty
git checkout c56d9b7a42433e5c58d1a558933e741a7a368cd9 -- .
git add .
git commit -m 'gen(59): incremental work on pearpass FHS and ghostty keybinds (part 4)' --allow-empty
git checkout c56d9b7a42433e5c58d1a558933e741a7a368cd9 -- .
git add .
git commit -m 'gen(60): incremental work on pearpass FHS and ghostty keybinds (part 5)' --allow-empty
git checkout 3bfee1f -- .
git add .
git commit -m 'gen(61): ghostty keybind syntax and pearpass dependencies' --allow-empty
git checkout 3bfee1f7a135160ff0184e683836c16a5d18020b -- .
git add .
git commit -m 'gen(62): polishing ghostty config and adding bug reporting workflow (part 1)' --allow-empty
git checkout 3bfee1f7a135160ff0184e683836c16a5d18020b -- .
git add .
git commit -m 'gen(63): polishing ghostty config and adding bug reporting workflow (part 2)' --allow-empty
git checkout 3bfee1f7a135160ff0184e683836c16a5d18020b -- .
git add .
git commit -m 'gen(64): polishing ghostty config and adding bug reporting workflow (part 3)' --allow-empty
git checkout 3bfee1f7a135160ff0184e683836c16a5d18020b -- .
git add .
git commit -m 'gen(65): polishing ghostty config and adding bug reporting workflow (part 4)' --allow-empty
git checkout 3bfee1f7a135160ff0184e683836c16a5d18020b -- .
git add .
git commit -m 'gen(66): polishing ghostty config and adding bug reporting workflow (part 5)' --allow-empty
git checkout 1b186c7 -- .
git add .
git commit -m 'gen(67): add bug reporting workflow and fix ghostty keybind syntax' --allow-empty
