# MyStuff 📦

A personal item location tracker for iOS. Never lose track of your stuff again.

**"Where did I put that?"** — solved.

## Features

- 🏠 **Home** — See all your locations at a glance with the items inside each
- 📦 **Items** — Full CRUD for items with search, notes, and location assignment
- 📍 **Locations** — Manage locations like "Living Room", "Garage", "Car"
- 🔐 **Google Sign-In** — Secure per-user data via Firebase Auth
- ☁️ **Cloud Sync** — Firestore backend, data syncs across devices
- 🪟 **Liquid Glass** — iOS 26 translucent material design throughout
- 🌓 **Dark Mode** — Full light and dark mode support

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Swift 6.2+ |
| UI | SwiftUI |
| Min Target | iOS 26 |
| Auth | Firebase Auth + Google Sign-In |
| Database | Cloud Firestore |
| Architecture | MVVM + Repository pattern |

## Setup

### Prerequisites

- **Xcode 26** (beta or later)
- A Firebase project with Firestore and Google Sign-In enabled
- An iOS 26 simulator or device

### Steps

1. **Clone the repo:**
   ```bash
   git clone https://github.com/turtleeverywhere/mystuff-ios.git
   cd mystuff-ios
   ```

2. **Add Firebase config:**
   - Download `GoogleService-Info.plist` from your [Firebase Console](https://console.firebase.google.com)
   - Drop it into the `MyStuff/` folder
   - Make sure it's added to the MyStuff target in Xcode

3. **Open in Xcode:**
   ```bash
   open MyStuff.xcodeproj
   ```
   Xcode will automatically resolve SPM dependencies (Firebase SDK, GoogleSignIn).

4. **Run** on an iOS 26 simulator or device.

### Firebase Console Setup

Make sure you have:
- **Authentication** → Sign-in method → **Google** enabled
- **Cloud Firestore** database created (start in test mode or configure security rules)

### Firestore Data Structure

Data is scoped per user:

```
users/
  {uid}/
    items/
      {itemId}: { name, notes?, locationId?, createdAt, updatedAt }
    locations/
      {locationId}: { name, emoji?, createdAt }
```

## Development

To inspect the UI without signing in, add `-ui-preview` to the MyStuff scheme's **Run → Arguments Passed On Launch** in a Debug build. This uses in-memory demo data and skips social sync and notification prompts. Release builds ignore the flag.

Views and previews can also inject mock services:
```swift
StuffViewModel(service: MockDataService(), storageService: MockStorageService())
```

The shared visual conventions are documented in [the UI design system](design-system/mystuff/MASTER.md).

## Security Note

`GoogleService-Info.plist` is excluded from git via `.gitignore`. Never commit Firebase config files to public repositories.

## License

MIT
