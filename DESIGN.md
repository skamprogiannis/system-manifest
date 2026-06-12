# Design

## Visual Register

This desktop is a task-focused glass environment. The glass should preserve enough wallpaper context to feel integrated, while keeping terminal and chat text readable for long sessions.

## Glass Contract

`modules/home/glass.nix` is the source of truth for glass surface values. Do not tune Ghostty, Vesktop, DMS, or Hyprland blur independently unless the token module cannot express the behavior.

The visual reference is Vesktop with its pre-native-blur Translucence surface ramp darkened by five percentage points. That correction applies to Vesktop's CSS surface percentages, not as a blind `+0.05` opacity rule for every transparent app.

## Surface Model

- Vesktop: compositor opacity stays `1.0 override`; visible transparency comes from Translucence, QuickCSS, and Matugen CSS surface variables.
- Ghostty: compositor opacity stays `1.0 override`; visible transparency comes from Ghostty's native black background opacity so glyphs remain opaque.
- DMS: shell popups and bar widgets use the same density family as Vesktop, with native Hyprland blur on selected layer namespaces.
- Spotify: Spicetify/Hazy keeps its music-art background, but its dark backdrops and blur are overridden from the shared glass contract to stay close to the Vesktop density ramp.
- GTK: popovers and menus use the shared glass token values, but GTK/WebKit app windows themselves are not made transparent.
- Hyprland: blur stays restrained. Excessive blur or vibrancy blends wallpaper colors into milky pastel blobs and should not be used to create darkness.

## Calibration Rules

- First tune Vesktop toward the desired reference look.
- Then tune Ghostty and DMS visually toward that corrected Vesktop reference.
- Keep app-specific renderers honest: Hazy can use album art, Neovim can inherit Ghostty, and GTK popovers can be translucent, but none of them should invent a separate glass palette.
- Increase app-side dark surface density before increasing compositor blur.
- Keep broad transparent surfaces low-vibrancy and readable; avoid making the wallpaper unrecognizable behind normal windows.
