#!/usr/bin/env bash
ROOT="$1"
[ -z "$ROOT" ] && exit 1

find "$ROOT" -maxdepth 4 -type d | while read dir; do
  [ ! -d "$dir" ] && continue
  [ -L "$dir" ] && continue
  
  parent=$(dirname "$dir")
  base=$(basename "$dir")
  low=$(echo "$base" | tr '[:upper:]' '[:lower:]')
  
  # Avoid infinite loops or matching self
  [ "$base" == "$low" ] && continue
  
  target="$parent/$low"
  
  if [ -d "$target" ] && [ ! -L "$target" ]; then
    echo "Found duplicate: $dir and $target"
    # Compare sizes
    size_dir=$(du -s "$dir" | cut -f1)
    size_target=$(du -s "$target" | cut -f1)
    
    if [ "$size_dir" -ge "$size_target" ]; then
      echo "Merging $target into $dir (larger)"
      rsync -a "$target/" "$dir/"
      rm -rf "$target"
      ln -s "$base" "$target"
    else
      echo "Merging $dir into $target (larger)"
      rsync -a "$dir/" "$target/"
      rm -rf "$dir"
      ln -s "$low" "$dir"
    fi
  fi
done
