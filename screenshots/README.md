<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# MeedyaConverter — App Store Screenshots

Required sizes (PNG, sRGB, no alpha):

- `01_main-window_1280x800.png`
- `01_main-window_1440x900.png`
- `01_main-window_2560x1600.png`
- `01_main-window_2880x1800.png`
- `02_profile-editor_*.png`
- `03_queue_*.png`
- `04_quality-metrics_*.png`
- `05_cloud-delivery_*.png`
- `06_dark-mode_*.png`

Captures are produced by the release operator from a fully-populated
instance of the app. They are intentionally **not** checked into git as
binaries — see `.gitignore` for the PNG exclusion. They are uploaded to
App Store Connect via `fastlane deliver --skip_screenshots=false` using a
local `fastlane/screenshots/en-US/` directory at submission time.

Numbering ensures App Store Connect displays them in the intended order.
