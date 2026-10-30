# Hatch

Hatch is a small keyboard launcher for macOS. Launches apps, calculates, runs scripts. Native Swift, no dependencies.

## Build and run

    scripts/bundle.sh          # release build -> build/Hatch.app
    open build/Hatch.app

Press **Option+Space** to open (change it in Settings). It lives in the menu bar (no Dock icon). Menu bar > Settings… opens a window with every setting: shortcut, recents, theme, opacity, row padding, icons, and the apps that open folders and links. Changes apply immediately and are written to `config.yml`, which you can still edit by hand.

The app icon (a hatch swung open, with chevrons launching out of it) is drawn in code: edit `scripts/make-icon.swift` and run `scripts/make-icon.sh` to regenerate `assets/Hatch.icns`.

## Using it

- Type to fuzzy-search apps. Apps you launch often rank higher.
- Type a calculation (`12*(3+4)`, `sqrt(2)^2`, `2^10`) and press Return to copy the answer.
  Operators `+ - * / % ^`, parentheses, constants `pi e tau`, functions `sqrt abs floor ceil round sin cos tan asin acos atan ln log log2 exp`.
- Type `theme` (or `theme nord`) to switch themes.
- Type `:` to pick a type (Applications, Scripts, Folders, Themes). The choice becomes a chip and search is limited to that type; with nothing typed after it, every item of that type is listed. Shorthand works too: `:s lock`, `:a saf`, `:f Pro`, `:t nord` (any prefix of the type name, followed by a space). Tab on a type fills it in, Backspace on an empty field removes the chip, and Esc removes the chip before it closes the panel. In Folders, bare text is relative to your home folder.
- Type a link starting with `http://` or `https://` to get an Open result; Return opens it in your default browser, or the one chosen under Settings > Open with. Only the explicit prefix counts.
- Type a path (`~/Pro`, `/usr/`) to find folders. Tab descends into the selected folder, Return opens it with the app chosen under Settings > Open with (Finder by default).
- Up/Down or Ctrl+N/Ctrl+P to move, Return to run, Esc to close.

## Scripts

Every executable file in `~/.config/hatch/scripts/` is a command. Starters (lock, screensaver, sleep, shut down) are written on first run. Optional header comments:

    #!/bin/zsh
    # name: Shut Down
    # description: Shut down the Mac
    # keywords: power off
    # confirm: true

A non-zero exit shows an alert with stderr.

## Themes

YAML, in `~/.config/hatch/themes/` (`.yml`; old `.toml` files still load).
Menu bar > Theme > Save Current Theme as YAML gives you a starting point:

    name: "My Theme"
    dark: true
    background: "#16181d"
    surface: "#1d2027"
    text: "#e6e8ee"
    subtext: "#8b91a1"
    accent: "#5b9cf5"
    selection: "#2c4a7a"
    radius: 14         # optional, panel corners
    row_radius: 8      # optional, result row corners

## Config and keybinding

`~/.config/hatch/config.yml` (menu bar > Open Config File, or Settings > Config File). Created on first run; config, scripts and themes from earlier versions (including from when the app was called Launcher) are moved here.

    hotkey: option+space
    opacity: 0.85      # 0.3-1, independent of the theme. Also in Settings
    padding: 8         # vertical padding inside each row in points, 0-20. Lower is more compact
    start_at_login: false   # start Hatch when you log in. Also in Settings
    recents: 0         # most-launched apps to list when the search box is empty, 0-10 (0 shows nothing)
    icons: color       # or monochrome: icons tinted with the theme accent. Also in Settings
    theme: "Nord"      # a preset or the name inside a file in ~/.config/hatch/themes/
    folder_app: /Applications/Ghostty.app   # omit for Finder
    link_app: /Applications/Firefox.app     # omit for the default browser

Every setting lives in this file and is re-read every time the panel opens, and Settings (and picking a theme in the launcher) write back to it, keeping your comments. Keys missing from an older file are added as commented placeholders. The only thing kept elsewhere is how often you launch each item, which is learned data rather than a setting. A `folder_app` or `link_app` path may start with `~`.


Hotkey modifiers are `cmd`, `option` (or `alt`), `ctrl`, `shift`; keys are `a-z`, `0-9`, `space`, `return`, `tab`, `f1-f12` and common punctuation. Examples: `cmd+shift+space`, `ctrl+option+l`, `f5`. If the combination is invalid or already taken by another app, it falls back to `option+space` and the menu shows which shortcut is active. To use `cmd+space`, first disable Spotlight's shortcut in System Settings > Keyboard > Keyboard Shortcuts > Spotlight.
