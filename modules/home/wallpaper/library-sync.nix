{pkgs, ...}: {
  home.packages = [
    (pkgs.writeShellScriptBin "wallpaper-library-sync" ''
      set -euo pipefail

      REPO_URL="''${WALLPAPER_REPO_URL:-}"
      REPO_BRANCH="''${WALLPAPER_REPO_BRANCH:-main}"
      REPO_DIR="''${WALLPAPER_REPO_DIR:-$HOME/wallpapers}"

      if [ -n "''${1:-}" ]; then
        REPO_URL="$1"
      fi

      if [ -n "$REPO_URL" ] && [ ! -d "$REPO_DIR/.git" ]; then
        mkdir -p "$(dirname "$REPO_DIR")"
        ${pkgs.git}/bin/git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
      fi

      if [ ! -d "$REPO_DIR/.git" ]; then
        echo "No git repo found at $REPO_DIR and no repo URL provided."
        echo "Usage (first run): wallpaper-library-sync git@github.com:you/wallpapers.git"
        exit 1
      fi

      if ${pkgs.git}/bin/git -C "$REPO_DIR" remote get-url origin >/dev/null 2>&1; then
        ${pkgs.git}/bin/git -C "$REPO_DIR" fetch --depth 1 origin "$REPO_BRANCH"
        if ! ${pkgs.git}/bin/git -C "$REPO_DIR" show-ref --verify --quiet "refs/heads/$REPO_BRANCH"; then
          ${pkgs.git}/bin/git -C "$REPO_DIR" checkout -b "$REPO_BRANCH" "origin/$REPO_BRANCH"
        else
          ${pkgs.git}/bin/git -C "$REPO_DIR" checkout -q "$REPO_BRANCH"
        fi
        ${pkgs.git}/bin/git -C "$REPO_DIR" reset --hard "origin/$REPO_BRANCH"
      else
        echo "No origin remote configured at $REPO_DIR; skipping fetch/reset."
      fi

      mkdir -p "$REPO_DIR/.wallpaper-engine"
      touch "$REPO_DIR/.gitignore"
      if ! grep -qxF '.wallpaper-engine/' "$REPO_DIR/.gitignore"; then
        echo ".wallpaper-engine/" >> "$REPO_DIR/.gitignore"
        echo "Added .wallpaper-engine/ to $REPO_DIR/.gitignore"
      fi

      if ! grep -qxF '.DS_Store' "$REPO_DIR/.gitignore"; then
        echo ".DS_Store" >> "$REPO_DIR/.gitignore"
      fi
      if ! grep -qxF 'Thumbs.db' "$REPO_DIR/.gitignore"; then
        echo "Thumbs.db" >> "$REPO_DIR/.gitignore"
      fi

      echo "Synced static wallpapers repo at $REPO_DIR"
    '')
  ];
}
