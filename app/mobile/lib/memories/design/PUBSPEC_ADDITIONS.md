# Design system: pubspec.yaml additions

No new packages. Only bundled assets and fonts (all files are already in the repo).

Under `flutter:` -> `assets:` add:

```yaml
    - assets/memories/
```

Under `flutter:` -> `fonts:` add:

```yaml
    - family: Fraunces
      fonts:
        - asset: fonts/Fraunces/Fraunces-400.ttf
          weight: 400
        - asset: fonts/Fraunces/Fraunces-400-Italic.ttf
          weight: 400
          style: italic
        - asset: fonts/Fraunces/Fraunces-500.ttf
          weight: 500
        - asset: fonts/Fraunces/Fraunces-500-Italic.ttf
          weight: 500
          style: italic
        - asset: fonts/Fraunces/Fraunces-600.ttf
          weight: 600
        - asset: fonts/Fraunces/Fraunces-700.ttf
          weight: 700
    - family: Manrope
      fonts:
        - asset: fonts/Manrope/Manrope-400.ttf
          weight: 400
        - asset: fonts/Manrope/Manrope-500.ttf
          weight: 500
        - asset: fonts/Manrope/Manrope-600.ttf
          weight: 600
        - asset: fonts/Manrope/Manrope-700.ttf
          weight: 700
        - asset: fonts/Manrope/Manrope-800.ttf
          weight: 800
    - family: NotoSansDevanagari
      fonts:
        - asset: fonts/NotoSansDevanagari/NotoSansDevanagari-400.ttf
          weight: 400
        - asset: fonts/NotoSansDevanagari/NotoSansDevanagari-500.ttf
          weight: 500
        - asset: fonts/NotoSansDevanagari/NotoSansDevanagari-600.ttf
          weight: 600
        - asset: fonts/NotoSansDevanagari/NotoSansDevanagari-700.ttf
          weight: 700
```

Fonts are SIL OFL 1.1 (licence text next to each family in `fonts/<Family>/OFL.txt`).
Photos are credited in `assets/memories/CREDITS.md`.
