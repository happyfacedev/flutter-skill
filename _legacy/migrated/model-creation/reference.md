# Model Creation — Reference

## Mason Brick Output

Running:

```bash
mason make simple_freezed_model --name user_response \
  --output-dir lib/features/auth/logic/models/responses
```

produces:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_response.gen.dart';
part 'user_response.g.dart';

@freezed
abstract class UserResponse with _$UserResponse {
  const factory UserResponse({
    // Add your fields here
  }) = _UserResponse;

  factory UserResponse.fromJson(Map<String, dynamic> json) =>
      _$UserResponseFromJson(json);
}
```

Fill in the factory parameters; everything else stays untouched.

## `@JsonKey` — snake_case API fields

Backends typically return `snake_case`; Dart uses `camelCase`. Map them with `@JsonKey(name: 'snake_field')`:

```dart
const factory UserResponse({
  required String id,
  @JsonKey(name: 'display_name') required String displayName,
  @JsonKey(name: 'is_active') required bool isActive,
  @JsonKey(name: 'created_at') required DateTime createdAt,
}) = _UserResponse;
```

`@JsonKey` lives on the parameter, not the field. It only affects JSON serialization — Dart code still uses the camelCase name.

Other useful `@JsonKey` flags:
- `defaultValue: ...` — used when the JSON key is absent
- `includeIfNull: false` — omit the field from the output `toJson` when `null`
- `unknownEnumValue: ...` — fallback enum value when the JSON string doesn't match any variant

## Enums with `@JsonValue`

Backend enums are typically lowercase strings. Map each Dart variant to its wire format with `@JsonValue('...')`:

```dart
enum ItemStatus {
  @JsonValue('active') active,
  @JsonValue('inactive') inactive,
  @JsonValue('archived') archived,
}
```

Then reference the enum in a model:

```dart
const factory ItemResponse({
  required String id,
  required ItemStatus status,
}) = _ItemResponse;
```

The serializer reads/writes the `@JsonValue` strings; Dart code uses the enum variants.

If the backend may return an unknown variant (e.g. a newly added one your app doesn't know about), set a fallback on the `@JsonKey`:

```dart
@JsonKey(unknownEnumValue: ItemStatus.archived)
required ItemStatus status,
```

Without `unknownEnumValue`, an unknown string throws at parse time.

## Optional vs required fields

```dart
const factory UserResponse({
  required String id,                     // present and non-null
  String? avatarUrl,                       // nullable — may be absent or null
  @Default(false) bool isVerified,         // present in JSON, but with a default if not
}) = _UserResponse;
```

- `required` + non-nullable: the JSON key must be present and non-null. Parse-time error otherwise.
- Nullable (`?`): tolerated as missing or null.
- `@Default(value)`: used when the field is absent — useful for boolean flags or new fields added to legacy responses.

## Nested model serialization

`json_serializable` handles nested `@freezed` models automatically — no extra annotations:

```dart
const factory OrderResponse({
  required String id,
  required UserResponse customer,                    // nested object
  required List<OrderLineResponse> lines,            // list of nested
}) = _OrderResponse;
```

The generated `fromJson` calls `UserResponse.fromJson` and `OrderLineResponse.fromJson` for each item. Just make sure the nested types also have a `fromJson` factory.

## Part Directive Pattern

This project keeps generated code (`.g.dart`, `.freezed.dart`) under `lib/core/generated/<mirror of source path>/` — not next to the source file. The `fix_part_directives.dart` script rewires part directives to point there.

**Brick output (before script):**

```dart
part 'my_model.g.dart';
part 'my_model.freezed.dart';
```

**After `dart tools/fix_part_directives.dart`:**

```dart
part '../../../../../core/generated/features/<feature>/logic/models/responses/my_model.freezed.dart';
part '../../../../../core/generated/features/<feature>/logic/models/responses/my_model.g.dart';
```

The deep relative path looks wrong at first glance but is correct — it's a relative path from the source file's directory up to `lib/` and back down to `core/generated/<same path>`. Don't shorten it back to the brick's adjacent form, and don't edit the generated mirror by hand (it's regenerated on every `dart run build_runner build`).

Workflow per model:

```bash
# 1. Generate the source file
mason make simple_freezed_model --name <model_name> --output-dir <feature_path>

# 2. Rewire part directives — analyzer errors before this are expected
dart tools/fix_part_directives.dart

# 3. Run build_runner to produce the .g.dart / .freezed.dart files in core/generated/
dart run build_runner build --delete-conflicting-outputs
```

## Folder Structure Example

```
lib/features/auth/logic/models/
├── responses/
│   ├── login_response.dart           # First model receiving raw JSON
│   └── user_response.dart
├── request_bodies/
│   └── login_request_body.dart
└── user.dart                          # Optional domain model
```

Failure models live in a sibling `failures/` directory and follow the `failure-modeling` skill — they are not `@freezed` and aren't generated by the brick.

## Common Mistakes to Avoid

| ❌ Don't | ✅ Do |
|----------|-------|
| Hand-write a `@freezed` class | `mason make simple_freezed_model ...` |
| Change `abstract class` to concrete | Keep `abstract`; only edit the factory parameters |
| Use relative imports | Package imports (`package:your_app/...`) |
| Fix `part` directive errors by hand | Run `dart tools/fix_part_directives.dart` |
| Edit files in `lib/core/generated/...` | They're regenerated on every build — edit the source instead |
| "Tidy" the deep relative path after the script ran | The path is correct; that's where generated code lives |
| Flat `models/` directory | Organise into `responses/`, `request_bodies/` |
| Name first JSON model without suffix (`User`) | Add `Response` suffix (`UserResponse`) |
| Name a wire-shape model without the suffix (`NotificationPreferences` for a Supabase row) "because it's also used as input" | Use the `Response` suffix and pass the same model to upsert — the suffix labels the shape, not the direction |
| Name a REST response model after the entity it represents (`ClinicLocation` because the endpoint returns a clinic location) | Use the `Response` suffix on the parsed body (`ClinicLocationResponse` or `LocationByIdResponse`); reserve the bare name (`ClinicLocation`) for a deliberate domain model built from one or more responses |
| Hand-cast snake_case fields in code | `@JsonKey(name: 'snake_field')` on the parameter |
| `String status` for an enum value | Proper `enum` with `@JsonValue('...')` per variant |
| Throw on unknown enum value from backend | `@JsonKey(unknownEnumValue: ...)` fallback |
| Put failure models under `models/` | Put them under `failures/` (see `failure-modeling`) |
