# apex (Flutter app)

Android app for the news editions in `../data`. See the repo README and the
build plan for the spec.

- `flutter test` runs unit and UI tests.
- `flutter test test_goldens --update-goldens` renders Home in every style to
  `test_goldens/goldens/` for a visual check (not committed).
- Release APKs are built and signed by `.github/workflows/build-apk.yml`.
