# Architecture

## Overview

Mixd is a Flutter app backed by Supabase. The app authenticates users, fetches/saves mixtape data, and plays audio snippets as a combined timeline (walkman-style player).

## High-level components

- **UI / Screens**: Flutter widgets (primarily under `lib/`) for feed, explore, creation, mixes, friends, profile, and playback.
- **Auth**: Google Sign-In via Supabase OAuth.
- **Backend**: Supabase (Postgres + Auth + Storage).
- **Audio**: `just_audio` for playback.

## Data flow (typical)

- **Sign in** → Supabase session created
- **Read** → fetch mixtapes/metadata from Supabase
- **Create** → build clip metadata in-app → save to Supabase
- **Play** → build a combined playback timeline across clips → seek across boundaries

## Suggested docs to keep updated

- Tables/columns used in Supabase (names + required fields)
- Any security/visibility rules (public/private/shared)
- Any non-obvious audio timeline assumptions (clip units, boundaries, seek rules)
