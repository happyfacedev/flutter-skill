# Theme Package

Location: `lib/core/theme/`

## Purpose

Provides theme utilities, sizing constants, and theming helpers for consistent UI across the app. Supports dynamic theming from per-organization configuration.

## Key Concepts

- Standard spacing and sizing values (`AppSize`)
- Theme generation from seed colors (Material 3)
- Organization-specific theme overrides via `ThemeCubit` (themes derive from the selected `OrganizationConfig`)
- Context extensions for easy access to theme data

## Components

| Component | Purpose |
|-----------|---------|
| `AppSize` | Standard padding, radius, icon sizes |
| `ThemeCubit` | Global theme state management |
| `AppTheme` | Light/dark theme generation |
| `AppColors` | Color constants |
| `AppAnimations` | Standard animation durations |