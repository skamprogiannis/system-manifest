{ pkgs, ... }: {
  home.packages = with pkgs; [
    nwg-wrapper
    fastfetch
    (pkgs.writeShellScriptBin "desktop-widget" ''
      # Kill any existing instances
      pkill nwg-wrapper || true
      
      # Wait for wallpaper to load
      sleep 3
      
      # Create the script that nwg-wrapper will run repeatedly
      WIDGET_SCRIPT="/tmp/desktop-stats.sh"
      cat << 'INNER_EOF' > "$WIDGET_SCRIPT"
      #!/usr/bin/env bash
      # Minimalist Fastfetch with progress bars
      fastfetch --logo none \
        --color-keys cyan \
        --color-title magenta \
        --percent-type 9 \
        --bar-char-elapsed "■" \
        --bar-char-total "-" \
        --bar-width 20 \
        --modules "Title,Separator,OS,Host,Kernel,Uptime,Packages,Shell,Display,WM,Terminal,CPU,GPU,Memory,Disk,LocalIP,Battery,Break,Colors" \
        --pipe
      INNER_EOF
      
      chmod +x "$WIDGET_SCRIPT"
      
      # Launch the wrapper glued to the wallpaper on the bottom right
      ${pkgs.nwg-wrapper}/bin/nwg-wrapper -s "$WIDGET_SCRIPT" -r 60000 -p right -a bottom -mr 50 -mb 50 -j right &
    '')
  ];
}
