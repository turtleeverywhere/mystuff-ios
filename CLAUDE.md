# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

- Open `MyStuff.xcodeproj` in Xcode 26+. SPM deps (Firebase, GoogleSignIn) resolve automatically.
- Requires `GoogleService-Info.plist` in `MyStuff/` (gitignored, download from Firebase Console).
- Target: iOS 26.0, Swift 6.0, bundle ID `com.flyingturtle.mystuff`.
- Unit tests: `MyStuffTests` (Swift Testing, hosted in the app). Run with
  `xcodebuild test -project MyStuff.xcodeproj -scheme MyStuff -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -only-testing:MyStuffTests`.
  `StuffViewModel` hardcodes Firebase and is not unit-tested; put testable logic in types that don't need it.

## Switching to Mock Data

In `StuffViewModel.swift`, swap the service line:
```swift
private let service: DataService = MockDataService()  // instead of FirebaseDataService()
```

## Architecture

MVVM + repository pattern. Single shared `StuffViewModel` owns all state; views receive it via `@Bindable`.

**Auth flow:** `MyStuffApp` → `RootView` switches between `SignInView` and `ContentView` based on `AuthService.isSignedIn`. `AuthService` is `@Observable`, wraps Firebase Auth + Google Sign-In.

**Data layer:** `DataService` protocol defines CRUD for `Item` and `Location`. Two implementations:
- `FirebaseDataService` — Firestore, scoped to `users/{uid}/items` and `users/{uid}/locations`
- `MockDataService` — in-memory, for previews/dev

**View hierarchy:** `ContentView` holds a `TabView` (Home/Items/Locations). Each tab view gets the shared `StuffViewModel`. Form sheets (`ItemFormSheet`, `LocationFormSheet`, `MoveItemSheet`) handle create/edit via closures.

**Models:** `Item` (name, notes?, locationId?, timestamps) and `Location` (name, emoji?, createdAt). Both are `Codable`/`Sendable` with String IDs.

**Item recognition:** `ItemScanView` runs a scan session (`ScanSessionModel`): capture → `ImageEmbedder` (Vision feature print over the foreground subject) → `ItemMatcher` nearest-neighbour over `RecognitionStore` references → review sheet → `moveItemsSharingDestination`. References (item photo / enrolled / learned) are on-device only, under `Application Support/Recognition/<uid>/` — nothing recognition-related is in Firestore. Thresholds in `ItemMatcher` are estimates; DEBUG builds show distances on the match card. In the simulator the feature print is pinned to CPU and returns near-constant vectors, and the subject mask can't run — the flow works there (photo-library fallback), but recognition quality can only be judged on a device.

## Conventions

- Uses iOS 26 Liquid Glass / `ultraThinMaterial` throughout
- `@Observable` macro (not `ObservableObject`), `@Bindable` in views
- Haptics via `HapticManager` enum on CRUD operations
- Firestore uses `Codable` mapping (`data(as:)` / `setData(from:)`)
