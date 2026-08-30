# App icon sources

This directory contains only the current production icon masters.

- `app-icon-ios-master.png` is the opaque 1024×1024 iPhone source. iOS applies the final icon mask.
- `app-icon-macos-master.png` uses the same artwork with transparent pixels outside the macOS rounded rectangle.

The artwork is intentionally flat: black background, white cup, and no baked-in frame, bevel, shadow, gradient, or texture.

The production iPhone copy lives in `BrewFocusiOS/Resources/Assets.xcassets/AppIcon.appiconset`. Regenerate the ten macOS catalog sizes with:

```sh
swift scripts/generate-macos-app-icon.swift \
  BrewFocusiOS/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png \
  assets/brand/app-icon-macos-master.png \
  BrewFocus/Resources/Assets.xcassets/AppIcon.appiconset
```
