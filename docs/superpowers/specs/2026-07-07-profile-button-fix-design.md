# Account Management: Fix Invisible Profile Button

**Date:** 2026-07-07
**Status:** Approved

## Problem

Profile button + `ProfileSheet` (user info, Sign Out → `AuthService.signOut()` → `RootView` shows `SignInView`) already exist in `ContentView.swift`, but the `.toolbar { profileButton }` modifier is applied outside `HomeView`'s internal `NavigationStack`, so SwiftUI never renders it. Account management is built but unreachable on both iPhone and iPad.

## Fix

### 1. `MyStuff/Views/HomeView.swift`

- Add `var onProfileTap: (() -> Void)? = nil`.
- In the existing `.toolbar`, add:

```swift
if let onProfileTap {
    ToolbarItem(placement: .topBarLeading) {
        Button(action: onProfileTap) {
            Image(systemName: "person.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
        }
    }
}
```

Leading placement because trailing (`primaryAction`) holds the gallery/list toggle. Nil closure → no button; previews unaffected.

### 2. `MyStuff/Views/ContentView.swift`

- Remove dead `.toolbar { ... profileButton ... }` block and the `profileButton` computed var.
- Pass `onProfileTap: { showingProfile = true }` to `HomeView`.
- Keep existing `.sheet(isPresented: $showingProfile) { ProfileSheet(...) }` unchanged.

## Boundaries

Auth stays owned by `ContentView`/`AuthService`; `HomeView` receives only a closure.

## Testing

Build for simulator. Manual: person button top-left on Home tab (iPhone + iPad sidebar mode), tap opens Profile sheet, Sign Out returns to auth screen. No test target exists.
