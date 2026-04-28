# Development

## Commands

```bash
# Dependencies
flutter pub get

# Static analysis
flutter analyze

# Run
flutter run

# API docs (dartdoc)
dart doc --output docs/api
```

## Environment variables

This project uses a `.env` file for client config (do not commit secrets).

Expected keys (see the project README for details):
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `GOOGLE_WEB_CLIENT_ID`
- `GOOGLE_IOS_CLIENT_ID`
- `MIXD_API_KEY`

## Documentation expectations (assignment)

- Keep `docs/ARCHITECTURE.md` aligned with the actual code and Supabase schema.
- Add Dart doc comments (`///`) to public classes/services so `dart doc` produces useful API docs.
