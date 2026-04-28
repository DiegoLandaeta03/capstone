# Mixd

A social music platform for creating and sharing custom mixtapes. Built with Flutter and Supabase.

## Tech Stack

- **Framework:** Flutter (Dart SDK ^3.10.8)
- **Backend:** [Supabase](https://supabase.com/) (PostgreSQL, Auth, Storage)
- **Auth:** Google Sign-In via Supabase OAuth
- **Audio:** just_audio
- **UI:** Material 3, Google Fonts (Outfit), dark theme

## Features

- **Feed** — TikTok-style vertical scroll of community mixes with cassette-style cards
- **Explore Entry in Feed** — Fixed search bar at the top of Feed that opens the Explore screen
- **Create + Mixtape Editor** — Select songs, reorder tracks, trim/snip each clip, and preview full mix timeline
- **Mixes Tab** — Dedicated mixes hub with:
  - `My mixes` (saved mixes owned by the user)
  - `Shared with you` (mixes shared to the current user)
- **Save to Supabase** — Save mixtapes to `public.mixtapes` with title, description, visibility, and track clip metadata
- **Delete Mixtapes** — Delete owned mixes from `My mixes` with confirmation
- **Walkman Player** — Portrait cassette-style player with:
  - Full mix timeline across all snippets
  - Seek across track boundaries
  - Tracklist bottom sheet with cover art and per-track previews
- **Friends** — Friends list view
- **Profile** — Google account info, stats (mixes, followers, following), sign out

## Project Structure

```
├── lib/
│   ├── main.dart                  # App entry, Supabase init, auth routing
│   ├── auth_service.dart          # Google OAuth sign-in/sign-out
│   ├── login_screen.dart          # Login UI
│   ├── home_screen.dart           # Bottom nav with 5 tabs
│   ├── feed_screen.dart           # Vertical feed + Explore entry bar
│   ├── explore_screen.dart        # Explore/search page
│   ├── create_screen.dart         # Song selection before editing
│   ├── mixtape_editor_screen.dart # Reorder/snip/save mixtapes
│   ├── mixes_screen.dart          # My mixes + Shared with you
│   ├── friends_screen.dart        # Friends page
│   ├── profile_screen.dart        # User profile page
│   └── walkman_player_screen.dart # Cassette-style audio player
├── assets/
│   └── audio/
│       └── sample.mp3             # Placeholder audio (will be replaced with DB audio)
├── android/                       # Android platform config
├── ios/                           # iOS platform config + Podfile
├── web/                           # Web platform config
├── windows/                       # Windows platform config
└── pubspec.yaml                   # Dependencies and assets
```

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel)
- Android Studio or Xcode (for emulators)
- A connected device or emulator

## Documentation

- **Team docs**: see `docs/` (architecture, development notes)
- **API docs (auto-generated)**: generated via `dart doc` and deployed via GitHub Pages (see `.github/workflows/docs.yml`)

### Run the App

```bash
# Install dependencies
flutter pub get

# Run on a connected device or emulator
flutter run
```

### Build

```bash
# Android APK
flutter build apk

# iOS
flutter build ios

# Web
flutter build web

# Windows
flutter build windows
```

## Environment Setup

This project uses a `.env` file for client config. It is **not** committed to git.

1. Copy the example file:
   ```bash
   cp .env.example .env
   ```
2. Fill in the values (get them from a teammate)

The `.env.example` file shows which variables are needed:
- `SUPABASE_URL` — Supabase project URL
- `SUPABASE_ANON_KEY` — Supabase anonymous key
- `GOOGLE_WEB_CLIENT_ID` — Google OAuth web client ID
- `GOOGLE_IOS_CLIENT_ID` — Google OAuth iOS client ID (must also match the URL scheme in `ios/Runner/Info.plist`)
- `MIXD_API_KEY` — Mixd song download API key

## Branch Conventions

| Type | Format | Example |
|------|--------|---------|
| Feature | `feature/description` | `feature/create-mixtape` |
| Bug fix | `fix/description` | `fix/login-crash` |
| Docs | `docs/description` | `docs/readme` |
| Chore | `chore/description` | `chore/cleanup-assets` |

Always branch off `main`, open a PR, get it reviewed, then merge.

## Team

- [@Shreyan9](https://github.com/Shreyan9)
- [@atkinsonl477](https://github.com/atkinsonl477)
- [@camdenbalberg](https://github.com/camdenbalberg)
- [@DiegoLandaeta03](https://github.com/DiegoLandaeta03)
