<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# MeedyaConverter Brand Guidelines

## Icon Architecture

The MeedyaConverter icon is designed for **adaptive/masked rendering** across all platforms.

### Layer Structure

| File | Purpose |
|------|---------|
| `icons/icon-source.svg` | Master source with all layers (design reference) |
| `icons/icon-background.svg` | Background layer (gradient, no transparency) |
| `icons/icon-foreground.svg` | Foreground layer (symbol, transparent background) |
| `icons/icon-monochrome.svg` | Single-color silhouette (Android 13+ themed icons) |

### Safe Zone

All critical icon elements are within the **inner 66%** of the canvas (170–854px on a 1024px canvas). The outer 17% on each side may be clipped by platform-specific masks.

### Platform Masking

| Platform | Mask Shape | Notes |
|----------|-----------|-------|
| macOS | Rounded rectangle (squircle) | Use `icon-source.svg` composited, Apple applies mask |
| iOS | Superellipse | Same as macOS, submitted as square |
| Android | Adaptive (circle/squircle/etc.) | Separate `icon-background.svg` + `icon-foreground.svg` |
| Android 13+ | Themed monochrome | Use `icon-monochrome.svg` |
| Windows | Square, optional rounding | Use composited `icon-source.svg` |
| Linux | Circle or square (DE-dependent) | Use composited `icon-source.svg` |
| Web (favicon) | Circle or square | Use `logos/mark/` at small sizes |

### Export Sizes

| Platform | Sizes Required |
|----------|---------------|
| macOS (.icns) | 16, 32, 64, 128, 256, 512, 1024 |
| iOS | 20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024 |
| Android | 48, 72, 96, 144, 192, 512 (mdpi through xxxhdpi) |
| Windows (.ico) | 16, 24, 32, 48, 64, 256 |
| Web (favicon) | 16, 32, 180 (apple-touch-icon), 192, 512 |

## Color Palette

### Primary Colors

| Name | Hex | RGB | Usage |
|------|-----|-----|-------|
| Dark Primary | `#1A1A2E` | 26, 26, 46 | App background, icon bg start |
| Dark Secondary | `#16213E` | 22, 33, 62 | Icon bg midpoint |
| Dark Accent | `#0F3460` | 15, 52, 96 | Icon bg end, sidebar bg |
| Brand Red | `#E94560` | 233, 69, 96 | Primary accent, source indicator |
| Brand Purple | `#533483` | 83, 52, 131 | Secondary accent, output indicator |

### Semantic Colors

| Role | Light Mode | Dark Mode |
|------|-----------|-----------|
| Accent / Tint | Brand Red `#E94560` | Brand Red `#E94560` |
| Success | System Green | System Green |
| Warning | System Orange | System Orange |
| Error | System Red | System Red |
| HDR indicator | Purple | Purple |

## Logo Variants

| Variant | File | Use Case |
|---------|------|----------|
| Full (dark bg) | `logos/full/meedyaconverter-logo-full.svg` | Headers on dark backgrounds |
| Full (light bg) | `logos/full/meedyaconverter-logo-full-light.svg` | Headers on light backgrounds |
| Mark only | `logos/mark/meedyaconverter-mark.svg` | Favicons, avatars, small spaces |
| Wordmark only | `logos/wordmark/meedyaconverter-wordmark.svg` | Text-only contexts |

## Typography

- **Primary**: SF Pro Display (macOS/iOS), Segoe UI (Windows), Inter (Linux/Web)
- **Wordmark**: Light weight "Meedya" + Semibold "Converter"
- **Monospace**: SF Mono (macOS/iOS), Cascadia Code (Windows), JetBrains Mono (Linux)

## Minimum Clear Space

The icon mark requires a minimum clear space of **25% of the icon width** on all sides when used alongside other elements.
