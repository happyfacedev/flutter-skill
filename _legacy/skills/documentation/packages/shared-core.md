# Shared Core Package

Location: `lib/core/` (utilities under `lib/core/utils/`, e.g. `bloc_status.dart`)

## Purpose

Contains common utilities, types, and helpers shared across the app's features.

## Key Concepts

- `BlocStatus` enum for process-based cubits (initial, loading, success, failure)
- Common extensions and utility functions
- Base classes and mixins
- Platform-agnostic helpers

## BlocStatus

Standard status enum for async operations:
- `initial` - Before any action
- `loading` - Operation in progress
- `success` - Completed successfully
- `failure` - Operation failed

Use for process-based cubits (LoginCubit, ItemsCubit). Don't use for state-based cubits like AuthCubit.