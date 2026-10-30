# Moth

A read-it-later app for music. Share an album, track or playlist from Spotify, Apple Music, Bandcamp, SoundCloud, YouTube Music, Tidal, Deezer (or any web page) to Moth, and it lands in your queue with its album art. Tap it later and it opens straight back in the app it came from.

## Build

Moth needs iOS 18 or later.

Requires a Mac with Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen            # generates Moth.xcodeproj from project.yml
open Moth.xcodeproj
```

The app's bundle ID is `com.ryanschlecht.moth` (share extension: `com.ryanschlecht.moth.share`) and its App Group is `group.com.ryanschlecht.moth`, all set in `project.yml`. Signing uses development team `JH4ZQ9MS78`, also set in `project.yml`, so regenerating the project keeps it. Both targets use the same App Group, which is how the share extension writes into the app's library.

## Using it

- **Queue and Heard** are two pages; swipe left for Heard. Small moths circle the title on Queue and fly to the stone lantern as you swipe; it catches light and they gather around it. Swiping back puts it out.
- **Tap** an album to open its page: the tracklist with soft track lengths, and credits at the bottom (release date, label, genre, copyright, and full credits such as mastering and songwriting where the service provides them). Tap the artwork to listen; tap a track for Listen or Mark Heard (heard tracks are struck through, and the album also appears on Heard with a "3 heard" note until you finish it); the ••• button has Mark Heard, Select and Remove for the album. Tracklists come from Apple Music, Bandcamp, Deezer and Spotify (full detail when Spotify is connected).
- **Press and hold** an album to pick it up; throw it toward the other page to move it there (Queue → Heard, or back). Quick swipes still page and scroll as normal.
- **Pull down** on either page to reveal the search bar under the header, with the view options (three lines) beside it: Grid or Rows, and Newest First, By Type or By Service.
- **Select** lets you mark several as heard (or back to the queue) or remove them at once.
- **Settings** (gear, top left): profile placeholder for future accounts, theme, app icon (five designs), mark-heard-when-opened, where links open, haptics, connections and listening stats.

## Connecting listening services

Stats always include what you mark as heard in Moth. Each service adds more once it's set up; until then its row says "Needs setup".

- **Last.fm** (easiest): create an API account at last.fm/api/account/create, put the API key in `LASTFM_API_KEY` in `project.yml`, run `xcodegen`, rebuild, then connect with your Last.fm username. Adds this week's scrobbles and top artists.
- **Spotify**: create an app at developer.spotify.com/dashboard, add the redirect URI `moth://spotify-callback`, add your Spotify account under Users and Access, put the Client ID in `SPOTIFY_CLIENT_ID` in `project.yml`, run `xcodegen` and rebuild. Uses PKCE, so there is no client secret in the app. Spotify only shares your last 50 plays and your top lists, so listening time from Spotify covers those plays.
- **Apple Music**: needs the paid developer account. In Certificates, Identifiers & Profiles, enable the MusicKit app service for `com.ryanschlecht.moth`. Apple doesn't expose listening time, so Stats shows what you've played recently.

The Spotify Client ID and Last.fm API key aren't secret (both are designed to ship inside apps), but if the repository is public you may still prefer to keep them out of it.

## How it works

- **Share extension** (`ShareExtension/`) accepts a URL or text containing a link, fetches metadata, downloads the artwork, saves it, and dismisses itself.
- **Metadata** (`Shared/MetadataFetcher.swift`) uses Spotify and SoundCloud oEmbed, the iTunes Lookup API for Apple Music, the Deezer API and YouTube oEmbed, then falls back to Open Graph tags (Bandcamp, Tidal, anything else). Short links (`spotify.link`, `deezer.page.link`, …) are resolved first and tracking params are stripped, so saving the same album twice just bumps it to the top.
- **Opening** tries the universal link (lands in the installed app), then the app's URL scheme, then Safari.
- **Storage** is a JSON file plus downsampled JPEG artwork in the App Group container.
- **Header art** (`Moth/Views/Header/`): the lantern and moths are drawn in code with SwiftUI `Canvas`, driven by the page position and a timeline, and pause when Reduce Motion is on.
- **Themes**: 16 in `Shared/Theme.swift`. The default "Moth" theme is a washed near-black so the lantern stands out. "Divine Comedy" draws a star field, angels and a faint Dante and Beatrice behind the library, built by `scripts/make_divine_comedy.py` from a public-domain Renaissance woodcut of the *Paradiso* (`Design/Art/paradiso-woodcut.png`).

## Fonts and icon

All bundled fonts are under the SIL Open Font License (free for commercial use; licences in `Design/fonts`): UnifrakturMaguntia (the Fraktur "M"), Grenze Gotisch Medium (Gothic lowercase), and Cinzel Decorative Black (the illuminated Q and H). The font files live in `Shared/Fonts`.

The app icon is the glowing Fraktur "M". `scripts/make_icon.py` renders it and the four alternates (outline, ring, illuminated initial, wordmark) into the asset catalog, plus the previews used in Settings. Needs Pillow and numpy.
