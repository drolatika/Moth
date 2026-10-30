# Moth

A read-it-later app for music. Share an album, track or playlist from Spotify, Apple Music, Bandcamp, SoundCloud, YouTube Music, Tidal, Deezer (or any web page) to Moth, and it lands in your queue with its album art. Tap it later and it opens straight back in the app it came from.

## Build

Requires a Mac with Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen            # generates Moth.xcodeproj from project.yml
open Moth.xcodeproj
```

The app's bundle ID is `com.ryanschlecht.moth` (share extension: `com.ryanschlecht.moth.share`) and its App Group is `group.com.ryanschlecht.moth`, all set in `project.yml`. Pick your signing team in Xcode under Signing & Capabilities. Both targets use the same App Group, which is how the share extension writes into the app's library.

## How it works

- **Share extension** (`ShareExtension/`) accepts a URL or text containing a link, fetches metadata, downloads the artwork, saves it, and dismisses itself.
- **Metadata** (`Shared/MetadataFetcher.swift`) uses Spotify and SoundCloud oEmbed, the iTunes Lookup API for Apple Music, the Deezer API and YouTube oEmbed, then falls back to Open Graph tags (Bandcamp, Tidal, anything else). Short links (`spotify.link`, `deezer.page.link`, …) are resolved first and tracking params are stripped, so saving the same album twice just bumps it to the top.
- **Opening** tries the universal link (lands in the installed app), then the app's URL scheme, then Safari.
- **Storage** is a JSON file plus downsampled JPEG artwork in the App Group container.
- **Themes**: 15 of them in `Shared/Theme.swift`, picked from the palette button. The share sheet uses your theme too.

## Icon

The app icon is a glowing Fraktur "M" set in UnifrakturMaguntia (SIL Open Font License, bundled in `Design/fonts`). `scripts/make_icon.py` renders it into the asset catalog, along with alternate designs kept in `Design/Icons/alternates` (outline, ring, illuminated initial, and the full "Moth" wordmark). Needs Pillow and numpy.
