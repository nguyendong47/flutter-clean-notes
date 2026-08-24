# Clean Notes Branding

This file is the durable identity and launcher-asset record. Use `Clean Notes`
for user-visible product copy. The repository and Dart package remain
`flutter-clean-notes` and `flutter_clean_notes`; platform identifiers and
binary names remain separate release decisions tracked in
[release readiness](release.md#current-identity-snapshot).

## Visual system

The product uses the Aurora Glass language: calm midnight surfaces, luminous
violet, mint highlights, translucent layers, and restrained depth.

| Role | Value | Source of truth |
| --- | --- | --- |
| Launcher background | `#15172B` | `pubspec.yaml` launcher configuration |
| Launcher violet | `#8B7CF6` | Versioned launcher master |
| Launcher mint | `#79E0C6` | Versioned launcher master |
| UI light primary | `#6757D9` | `lib/app/theme/aurora_theme.dart` |
| UI dark primary | `#A99BFF` | `lib/app/theme/aurora_theme.dart` |
| UI mint accent | `#2DB9A8` | `lib/app/theme/aurora_theme.dart` |
| UI light/dark canvas | `#F4F6FF` / `#0B1020` | `lib/app/theme/aurora_theme.dart` |
| UI light text | `#17203B` | `lib/app/theme/aurora_theme.dart` |

The launcher mark is a folded note forming a subtle abstract N with an aurora
sparkle. Keep the silhouette recognizable at 32-48 px. Operating systems apply
their own outer masks; the source artwork has no simulated rounded-square frame.

Android notification status bars use the separate monochrome drawable
`android/app/src/main/res/drawable/ic_stat_clean_notes.xml`, not any launcher
image. Keep that resource referenced by
`android/app/src/main/res/raw/keep.xml` so release shrinking cannot remove it.
Changes must retain a transparent background and a solid white silhouette, then
pass `test/app/android_notification_small_icon_test.dart`. The notification
drawable is maintained independently and is not an output of
`flutter_launcher_icons`; launcher regeneration must leave it and its keep rule
intact.

## Versioned source assets

| Asset | Purpose | Properties | SHA-256 |
| --- | --- | --- | --- |
| [`assets/branding/aurora_launcher_icon.png`](../assets/branding/aurora_launcher_icon.png) | Opaque master for legacy Android, Apple, web, Windows, and macOS | 1254 x 1254, RGB, opaque | `88FD1B53088B19DF8938A99E7B338EBBCC8C7848CE820B77EDDF51D7143D2F85` |
| [`assets/branding/aurora_launcher_foreground.png`](../assets/branding/aurora_launcher_foreground.png) | Android adaptive foreground | 1254 x 1254, ARGB, genuine transparency | `AA04546D2638D7D6EC8E7D021DB58073392295FAA2DB39833E125983B74A216B` |

Both files were generated on 2026-08-24 with OpenAI's built-in image generation
tool, then copied byte-for-byte into the tracked paths above. The generated
resolution is recorded as produced even though the first prompt requested a
1024 x 1024 master.

### Opaque master prompt

Mode: image generation, `logo-brand`.

```text
Use case: logo-brand
Asset type: production mobile and desktop app launcher icon master, square 1024x1024
Primary request: Create a distinctive icon for a modern local-first note-taking app with an Aurora Glass visual system.
Subject: One bold, minimal folded note sheet forming a subtle abstract letter N, with a tiny four-point aurora sparkle near the upper fold. The mark must remain instantly recognizable at 32–48 px.
Style/medium: premium vector-friendly 3D glass emblem; clean geometric silhouettes; restrained depth; crisp edges; polished but not photorealistic.
Composition/framing: centered, generous 18% safe zone, large simple mark, full-bleed square background; do not draw rounded outer corners because operating systems apply their own masks.
Lighting/mood: soft internal glow, refined calm productivity, high contrast.
Color palette: deep midnight indigo background (#15172B), luminous lavender/violet (#8B7CF6), mint/aqua (#79E0C6), small cool-white highlight.
Materials/textures: translucent frosted glass layers with controlled gradients and one soft shadow; avoid noisy texture.
Constraints: no text, no letters drawn literally, no watermark, no Flutter logo, no pen or pencil cliché, no tiny details, no transparency, no border, no mockup/device frame, no extra objects. Produce a clean standalone app icon image.
```

### Adaptive foreground prompt

Mode: image edit, `background-extraction`, using the opaque master as the input.

```text
Use case: background-extraction
Asset type: Android adaptive launcher icon foreground, square master
Primary request: Remove only the midnight indigo background and make it genuinely transparent.
Invariants: preserve the central lavender-and-mint folded-note/N glass emblem and white four-point sparkle exactly in shape, proportions, colors, highlights, scale, and centered placement; keep a restrained close glow attached to the emblem; keep the same generous safe zone.
Constraints: transparent background with alpha, no new background, no text, no watermark, no border, no outer rounded-square plate, no extra objects, no cropping.
```

## Regeneration guardrails

`flutter_launcher_icons` is intentionally pinned to `0.14.4` in
`pubspec.yaml`. Its configuration generates Android legacy/adaptive icons, iOS,
web, Windows, and macOS outputs. Android uses `#15172B`, zero foreground inset,
and no monochrome layer.

After changing a source or launcher setting:

```powershell
flutter pub get --enforce-lockfile
dart run flutter_launcher_icons
git diff --check
```

Review every generated binary and catalog diff at small sizes before committing.
Version `0.14.4` can incorrectly rewrite two iOS project settings to
`ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = AppIcon`. Run the
generator a second time first and verify that the intended launcher outputs are
byte-stable. After that final generator run, restore the affected settings to
`YES` and verify the project contains no `AppIcon` assignment for this setting.
Keep the source PNGs and all shipping generated icons in the same commit.
