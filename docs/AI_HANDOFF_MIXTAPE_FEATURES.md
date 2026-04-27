# Mixd AI Handoff: Mixtape Editing and Playback

Use this document as full project context for generating an implementation prompt.

## What This App Is

Mixd is a Flutter app (Dart) backed by Supabase.
It is a social music platform where users create and share custom mixtapes.

Core concept:
- A mixtape is saved as metadata (ordered clips of source songs), not as a rendered final audio file.
- Playback is reconstructed on demand from song files in Supabase Storage + clip start/end times.

## Tech Stack

- Frontend: Flutter
- Language: Dart (SDK ^3.10.8)
- Backend: Supabase (Postgres, Auth, Storage)
- Auth: Google Sign-In via Supabase OAuth
- Audio engine: `just_audio`
- Key package versions:
  - `just_audio: ^0.10.4`
  - `supabase_flutter: ^2.12.0`
  - `google_sign_in: ^7.2.0`
  - `flutter_dotenv: ^5.2.1`

## Current User Flow (Important)

1) Create tab (`lib/create_screen.dart`)
- Loads songs from `songs` table.
- User can search songs by title/artist/genre.
- User can select songs for a mixtape.
- User can preview each song up to 30 seconds.
- Audio preview URL is generated from private storage bucket `song-files` using signed URLs.

2) Mixtape editor (`lib/mixtape_editor_screen.dart`)
- Selected songs become editable clips.
- User can reorder clips.
- User can trim each clip with `RangeSlider` (`start_seconds`, `end_seconds`).
- User can "zoom in" currently by narrowing slider min/max range (not waveform zoom).
- User can preview individual clip or full mix timeline.
- Full mix is played by concatenating clipped sources using `just_audio`.

3) Save mixtape
- On save, app inserts row into `mixtapes`.
- Saved fields include:
  - `creator_id`
  - `title`
  - `description`
  - `cover_art_url`
  - `tracks` JSON payload
  - `is_public`
  - `updated_at`

4) Playback later (`lib/walkman_player_screen.dart`)
- Mix is reconstructed from `tracks` payload:
  - for each track -> signed URL from `song-files`
  - wrap each URL in `ClippingAudioSource(start,end)`
  - combine via `ConcatenatingAudioSource`
- Supports seeking across entire mix timeline.
- Tracklist sheet provides per-track preview and jump-to-track.

5) Discovery + access points
- Feed (`lib/feed_screen.dart`) loads public mixtapes.
- Explore (`lib/explore_screen.dart`) searches public mixes.
- Mixes (`lib/mixes_screen.dart`) shows my mixes + shared mixes.
- Chat (`lib/chat_screen.dart`) supports sharing mixes via `mix{mixtape_id}` references.

## Backend/Data Model Context

No custom backend service in this repo. Client talks directly to Supabase.

### Tables used by app
- `songs`
- `mixtapes`
- `profiles`
- `messages`
- `mixtape_likes`
- `mixtape_comments`

### Storage
- Supabase Storage bucket: `song-files` (private).
- Audio objects mapped from `file_key` (usually `<file_key>.mp3`).
- App generates short-lived signed URLs (typically 5 minutes).

### Mixtape tracks payload shape (current)

`mixtapes.tracks` is JSON object:
- `tracks`: array of track objects

Each track object currently includes:
- `position` (int)
- `song_id` (string/uuid)
- `title` (string)
- `artist` (string)
- `album_art_url` (string|null)
- `file_key` (string)
- `start_seconds` (double)
- `end_seconds` (double)
- `original_duration_seconds` (int)
- `trimmed_duration_seconds` (double)

## Existing Constraints and Behavior

- Mixes are metadata-only; there is no pre-rendered output file.
- Playback is runtime reconstruction.
- Signed URLs can expire; editor/player currently refetch as needed.
- Transitions are currently hard cuts between tracks.
- "Zoom in" is not waveform-based yet.
- App must continue to open and play old mixes that only have existing fields.

## What We Want to Build Next

Primary goals:
1) Waveform-based zoom editing in Mixtape Editor.
2) Song-to-song transitions (fade-in, fade-out, optional crossfade).

### Feature A: Waveform Zoom Editing

Need:
- Render waveform per clip/song in editor.
- Support zoom + pan with fine trimming handles.
- Keep existing trim behavior but make it precise and visual.
- Ensure acceptable performance for multi-track mixes.

Expected design considerations:
- How waveform data is generated (on-device extraction vs precomputed peaks vs hybrid).
- Caching strategy (memory + disk).
- Async loading UI states per clip.
- Reuse waveform data across create/editor/player where possible.

### Feature B: Transitions Between Clips

Need:
- Add transition metadata between adjacent clips.
- User controls for transition type and duration.
- Playback engine must audibly apply transitions at boundaries.

Minimum transition set:
- Fade-out ending of clip A.
- Fade-in beginning of clip B.
- Optional overlap crossfade if technically feasible with current stack.

Expected design considerations:
- Data schema for transitions.
- Validation rules:
  - duration > 0
  - duration must not exceed available clip length
  - safe fallback to hard cut
- Backward compatibility when transition fields are absent.

## Backward Compatibility Requirements

- Existing mixes must keep playing with no migration blocker.
- New reader/parser logic should tolerate:
  - missing new fields
  - malformed values
  - mixed old/new data
- Editor should gracefully load old mixes and assign sane defaults.

## Key Files to Modify (Likely)

- `lib/mixtape_editor_screen.dart`
  - waveform UI, zoom/pan, trim precision, transition controls, payload writing
- `lib/walkman_player_screen.dart`
  - transition-aware playback timeline/audio source strategy
- `lib/mixes_screen.dart`
  - parser updates for new payload fields if needed
- `lib/feed_screen.dart`
  - parser updates for new payload fields if needed
- `lib/explore_screen.dart`
  - parser updates for new payload fields if needed
- `lib/chat_screen.dart`
  - parser updates for new payload fields if needed
- `lib/create_screen.dart`
  - optional pre-warm waveform metadata for selected songs

Potential additions:
- New model/parser utilities for tracks + transitions.
- New waveform service(s) and caching layer.
- Optional migration notes/SQL docs under `docs/`.

## Non-Goals (for this iteration)

- Full DAW-grade editing.
- Cloud-side rendering/export of a single mixed audio file.
- Real-time multi-track stem mixing.
- Deep social redesign.

## Definition of Done (Suggested)

- User sees waveform for clips in editor.
- User can zoom and trim with improved precision.
- User can configure transition per boundary.
- Saved payload includes transition metadata.
- Playback applies transitions (or clear best-effort fallback).
- Old mixes still playable.
- No regressions in create/save/play/share flows.

## Testing Expectations

Must include:
- Unit tests for payload parsing and backward compatibility.
- Unit tests for transition validation logic.
- Integration/widget tests for:
  - save/load with new metadata
  - editor timeline interaction
  - playback seek consistency
- Manual QA checklist for:
  - long mixes
  - short clips
  - URL expiration edge cases
  - old mixes without transition data

## Prompt Request to Another AI

Generate an implementation-ready engineering prompt that includes:
- Architecture approach options with tradeoffs.
- Final recommended approach.
- Supabase schema/payload changes (exact fields).
- Flutter file-by-file implementation plan.
- Playback algorithm details for transitions.
- Backward compatibility strategy.
- Testing plan (unit/integration/manual).
- Risks and mitigation.
- Step-by-step execution order.

Return the prompt in a format directly usable by a coding AI agent.
