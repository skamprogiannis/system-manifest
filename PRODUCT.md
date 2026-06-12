# Product

## Register

product

## Users

This is a personal NixOS desktop configuration for a developer working across terminal, chat, browser, shell widgets, and portable USB sessions. The user is usually in task mode: reading dense text, editing code, navigating workspaces, and switching between long-running tools.

## Product Purpose

The system provides a reproducible desktop environment with Hyprland, Ghostty, Vesktop, DankMaterialShell, wallpaper-driven theming, and portable USB workflows. Success means the desktop feels coherent and readable during daily use, with visual effects supporting focus instead of fighting it.

## Brand Personality

Technical, atmospheric, restrained. The desktop should feel custom and glass-like, but still precise enough for long terminal and chat sessions.

## Anti-references

Avoid milky pastel smears, excessive blur that destroys background structure, raw transparent windows with sharp wallpaper showing through text-heavy surfaces, one-off app styling that makes each transparent surface look unrelated, and decorative glass effects that reduce readability.

## Design Principles

- Make Vesktop the glass reference: translucent, readable, and wallpaper-aware without hiding the whole background.
- Keep text surfaces practical first; terminal glyphs and chat text must remain fully legible.
- Use one shared native blur profile for Hyprland, then tune each app's own surface opacity to match.
- Prefer restrained saturation and low vibrancy so wallpaper colors do not blend into muddy pastel blobs.
- Keep rollback and runtime validation simple: screenshots and generation revisions should clearly show what visual profile is active.

## Accessibility & Inclusion

Prioritize readable contrast for long-form terminal and chat text. Avoid motion or blur changes that make the desktop harder to parse. Preserve opaque text by using app-native transparency and compositor opacity `1.0` for text-heavy applications.
