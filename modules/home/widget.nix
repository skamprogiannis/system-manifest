{ pkgs, ... }: {
  home.packages = with pkgs; [
    nwg-wrapper
    (pkgs.writeShellScriptBin "desktop-widget" ''
      # Kill any existing instances
      pkill nwg-wrapper || true
      
      # Wait for wallpaper to load
      sleep 3
      
      # Create the script that nwg-wrapper will run repeatedly
      WIDGET_SCRIPT="/tmp/desktop-stats.sh"
      cat << 'INNER_EOF' > "$WIDGET_SCRIPT"
      #!/usr/bin/env bash
      
      # Get System Stats
      CPU=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
      RAM=$(free -m | awk '/Mem:/ { printf("%3.1f%%", $3/$2*100) }')
      DISK=$(df -h / | awk 'NR==2 {print $5}')
      UPTIME=$(uptime -p | sed 's/^up //')
      
      # Print Pango Markup (Dracula Colors)
      echo "<span font_family='JetBrainsMono Nerd Font' size='xx-large' color='#bd93f9'><b>SYSTEM</b></span>"
      echo ""
      echo "<span font_family='JetBrainsMono Nerd Font' size='large' color='#ff79c6'>  CPU: </span><span font_family='JetBrainsMono Nerd Font' size='large' color='#f8f8f2'>''${CPU}%</span>"
      echo "<span font_family='JetBrainsMono Nerd Font' size='large' color='#50fa7b'>  RAM: </span><span font_family='JetBrainsMono Nerd Font' size='large' color='#f8f8f2'>$RAM</span>"
      echo "<span font_family='JetBrainsMono Nerd Font' size='large' color='#ffb86c'>󰋊 DISK: </span><span font_family='JetBrainsMono Nerd Font' size='large' color='#f8f8f2'>$DISK</span>"
      echo ""
      echo "<span font_family='JetBrainsMono Nerd Font' size='medium' color='#6272a4'>󰔟 $UPTIME</span>"
      INNER_EOF
      
      chmod +x "$WIDGET_SCRIPT"
      
      # Launch the wrapper glued to the wallpaper on the bottom right
      ${pkgs.nwg-wrapper}/bin/nwg-wrapper -s "$WIDGET_SCRIPT" -r 5000 -p right -a bottom -mr 50 -mb 50 -j right &
    '')
  ];
}
