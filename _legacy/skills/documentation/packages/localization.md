# Localization Package

Location: `lib/core/localization/` (ARB files under `lib/core/localization/arb/`)

## Purpose

Provides internationalization (i18n) support using Flutter's gen-l10n. Manages translations and locale-specific formatting.

## Key Concepts

- ARB files for translations (`app_en.arb`, `app_ro.arb`)
- English is the primary language — add new keys to `app_en.arb` first, then every other ARB file
- Generated `AppLocalizations` class for accessing strings
- Supports parameterized strings and plurals
- Context extension for easy access (`context.localization`)
- App UI locale is owned by `LanguageCubit` (`lib/core/localization/cubit/language_cubit.dart`)

## Supported Languages

- English (primary / default)
- Romanian