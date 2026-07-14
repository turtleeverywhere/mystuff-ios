# Location QR Codes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate printable QR codes for locations that, when scanned (system Camera or in-app), open the app to that location's items — and let an item be moved by scanning a location's QR.

**Architecture:** Reuse the existing universal-link deep-link path (host `mystuff.coding-turtle.org`). A new `AppLink` router parses both `/item/*` and `/location/*`. A single `LocationDetailView` is the QR home and the scan/deep-link target (pushed in the Locations tab, presented as a sheet on deep-link). QR images come from CoreImage; PNG/PDF export and print come from `ImageRenderer` over a shared `QRStickerView`. In-app scanning uses VisionKit `DataScannerViewController`.

**Tech Stack:** Swift 6 / SwiftUI, iOS 26, CoreImage (`CIFilter.qrCodeGenerator`), `ImageRenderer`, `UIPrintInteractionController`, VisionKit.

## Global Constraints

- Target iOS 26.0, Swift 6.0, bundle ID `com.flyingturtle.mystuff`.
- **No test target exists.** Every task is verified by `xcodebuild` compile + manual runtime check — there are no XCTest steps.
- Build command (run from repo root, look for `** BUILD SUCCEEDED **`):
  ```
  xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build
  ```
- Universal-link host is `mystuff.coding-turtle.org` (already in `MyStuff.entitlements` associated domains).
- `NSCameraUsageDescription` already present in `MyStuff/Info.plist` — do NOT add a new key.
- Follow existing conventions: `@Observable`/`@Bindable`, `.ultraThinMaterial`, `HapticManager`, `LinearGradient.appBackground`, `Color.appText`/`appAccent`.
- New Swift files must be added to the Xcode target. This project's `.pbxproj` uses Xcode 26 file-system synchronized groups (`PBXFileSystemSynchronizedRootGroup`) — files under `MyStuff/` are picked up automatically, so no manual `.pbxproj` edit is needed. If a new file fails to compile as "not in target", verify this before hand-editing.

---

## File Structure

**New**
- `MyStuff/Services/AppLink.swift` — URL router for `.item`/`.location` targets; owns the shared host.
- `MyStuff/Utilities/QRCodeGenerator.swift` — string → crisp QR `UIImage`.
- `MyStuff/Views/QRStickerView.swift` — SwiftUI sticker (QR + emoji + name); shared by preview and export.
- `MyStuff/Views/QRCodeSheet.swift` — export (PNG/PDF via `ImageRenderer`), Share, Print.
- `MyStuff/Views/LocationDetailView.swift` — items + sub-locations + Edit/QR toolbar; pushed and sheet.
- `MyStuff/Views/QRScannerView.swift` — VisionKit representable + `QRScannerSheet` wrapper (parses `AppLink`, surfaces errors).

**Modified**
- `.well-known/apple-app-site-association` — add `/location/*`.
- `MyStuff/Services/NFCService.swift` — `NFCLink` delegates to `AppLink`.
- `MyStuff/Views/ContentView.swift` — location deep-link routing + sheet.
- `MyStuff/Views/LocationsView.swift` — row tap → detail; global Scan toolbar button.
- `MyStuff/Views/HomeView.swift` — `MoveItemSheet` Scan QR button.

---

## Task 1: `AppLink` router + `NFCLink` delegation

**Files:**
- Create: `MyStuff/Services/AppLink.swift`
- Modify: `MyStuff/Services/NFCService.swift:4-23` (the `NFCLink` enum)

**Interfaces:**
- Produces: `AppLink.host: String`; `AppLink.Target` enum (`.item(String)`, `.location(String)`); `AppLink.url(for: Target) -> URL`; `AppLink.parse(_ url: URL) -> Target?`.
- `NFCLink.url(forItemId:)` and `NFCLink.itemId(from:)` keep their existing signatures (used by `NFCService` + `ContentView`), now delegating to `AppLink`.

- [ ] **Step 1: Create `AppLink.swift`**

```swift
import Foundation

/// Universal-link router for the app's deep-link targets.
/// URLs look like `https://mystuff.coding-turtle.org/{item|location}/<uuid>`.
enum AppLink {
    static let host = "mystuff.coding-turtle.org"

    enum Target: Equatable {
        case item(String)
        case location(String)
    }

    private static let itemPrefix = "/item/"
    private static let locationPrefix = "/location/"

    static func url(for target: Target) -> URL {
        let path: String
        switch target {
        case .item(let id): path = itemPrefix + id
        case .location(let id): path = locationPrefix + id
        }
        return URL(string: "https://\(host)\(path)")!
    }

    static func parse(_ url: URL) -> Target? {
        guard url.scheme == "https", url.host == host else { return nil }
        if url.path.hasPrefix(itemPrefix) {
            let id = String(url.path.dropFirst(itemPrefix.count))
            return id.isEmpty ? nil : .item(id)
        }
        if url.path.hasPrefix(locationPrefix) {
            let id = String(url.path.dropFirst(locationPrefix.count))
            return id.isEmpty ? nil : .location(id)
        }
        return nil
    }
}
```

- [ ] **Step 2: Rewrite `NFCLink` to delegate**

Replace the `NFCLink` enum (lines 4-23 of `MyStuff/Services/NFCService.swift`) with:

```swift
/// Item universal-link helpers used by the NFC read/write path.
/// Delegates to `AppLink` so the host and URL shape live in one place.
enum NFCLink {
    static var host: String { AppLink.host }

    static func url(forItemId id: String) -> String {
        AppLink.url(for: .item(id)).absoluteString
    }

    /// Extract item UUID from any URL we recognize as an NFC payload.
    static func itemId(from url: URL) -> String? {
        if case .item(let id)? = AppLink.parse(url) { return id }
        return nil
    }
}
```

Leave the rest of `NFCService.swift` unchanged (it only calls `NFCLink.url(forItemId:)` and `NFCLink.itemId(from:)`).

- [ ] **Step 3: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`. If a "cannot find `pathPrefix`" error appears, search for `NFCLink.pathPrefix` / `NFCLink.host` references and confirm none remain outside the rewritten enum (there should be none).

- [ ] **Step 4: Manual regression check (deferred until a device/sim run)**

Note in commit body: NFC item write/scan must still work (item URL shape is byte-identical). This is validated during the Task 9 manual pass.

- [ ] **Step 5: Commit**

```bash
git add MyStuff/Services/AppLink.swift MyStuff/Services/NFCService.swift
git commit -m "feat: add AppLink router, delegate NFCLink to it"
```

---

## Task 2: `QRCodeGenerator`

**Files:**
- Create: `MyStuff/Utilities/QRCodeGenerator.swift`

**Interfaces:**
- Produces: `QRCodeGenerator.image(for string: String, scale: CGFloat = 12) -> UIImage?`

- [ ] **Step 1: Create `QRCodeGenerator.swift`**

```swift
import UIKit
import CoreImage.CIFilterBuiltins

/// Generates crisp QR-code images from a string using CoreImage.
enum QRCodeGenerator {
    private static let context = CIContext()

    /// - Parameter scale: point multiplier applied to the raw QR matrix (higher = larger/crisper).
    /// - Returns: nil if generation fails.
    static func image(for string: String, scale: CGFloat = 12) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
```

- [ ] **Step 2: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MyStuff/Utilities/QRCodeGenerator.swift
git commit -m "feat: add QRCodeGenerator"
```

---

## Task 3: `QRStickerView`

**Files:**
- Create: `MyStuff/Views/QRStickerView.swift`

**Interfaces:**
- Consumes: `Location` (model), `UIImage`.
- Produces: `QRStickerView(location: Location, qrImage: UIImage)` — a fixed-layout, white-background sticker used for on-screen preview and `ImageRenderer` export.

- [ ] **Step 1: Create `QRStickerView.swift`**

```swift
import SwiftUI

/// Printable sticker: QR code above the location's emoji + name, on a white card.
/// Deliberately white-on-black regardless of app theme for print contrast.
/// Rendered on-screen and via `ImageRenderer` for PNG/PDF export, so its layout
/// is fixed-size and self-contained.
struct QRStickerView: View {
    let location: Location
    let qrImage: UIImage

    var body: some View {
        VStack(spacing: 16) {
            Image(uiImage: qrImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 240, height: 240)

            HStack(spacing: 8) {
                Text(location.emoji ?? "📍")
                    .font(.title)
                Text(location.name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(width: 320)
        .background(Color.white)
    }
}

#Preview {
    QRStickerView(
        location: Location(name: "Garage", emoji: "🚗"),
        qrImage: QRCodeGenerator.image(for: "https://mystuff.coding-turtle.org/location/demo") ?? UIImage()
    )
}
```

- [ ] **Step 2: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MyStuff/Views/QRStickerView.swift
git commit -m "feat: add QRStickerView"
```

---

## Task 4: `QRCodeSheet` (export + print)

**Files:**
- Create: `MyStuff/Views/QRCodeSheet.swift`

**Interfaces:**
- Consumes: `Location`, `AppLink.url(for:)`, `QRCodeGenerator.image(for:)`, `QRStickerView`.
- Produces: `QRCodeSheet(location: Location)` — presented as a sheet.

- [ ] **Step 1: Create `QRCodeSheet.swift`**

```swift
import SwiftUI
import UIKit

/// Sheet that shows a location's QR sticker with Share (PNG/PDF) and Print actions.
struct QRCodeSheet: View {
    let location: Location
    @Environment(\.dismiss) private var dismiss

    @State private var qrImage: UIImage?
    @State private var pngURL: URL?
    @State private var pdfURL: URL?

    var body: some View {
        NavigationStack {
            Group {
                if let qrImage {
                    content(qrImage: qrImage)
                } else {
                    ContentUnavailableView("Couldn’t generate code", systemImage: "qrcode")
                }
            }
            .navigationTitle("QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task { prepare() }
    }

    @ViewBuilder
    private func content(qrImage: UIImage) -> some View {
        VStack(spacing: 24) {
            QRStickerView(location: location, qrImage: qrImage)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 8)

            HStack(spacing: 16) {
                if let pdfURL {
                    ShareLink(item: pdfURL,
                              preview: SharePreview("\(location.name) QR", image: Image(uiImage: qrImage))) {
                        Label("Share PDF", systemImage: "doc")
                    }
                }
                if let pngURL {
                    ShareLink(item: pngURL,
                              preview: SharePreview("\(location.name) QR", image: Image(uiImage: qrImage))) {
                        Label("Share PNG", systemImage: "photo")
                    }
                }
            }

            Button {
                printSticker()
            } label: {
                Label("Print", systemImage: "printer")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.appAccent)
            .disabled(pdfURL == nil)
            .padding(.horizontal)

            Spacer()
        }
        .padding()
    }

    // MARK: - Export

    @MainActor
    private func prepare() {
        let urlString = AppLink.url(for: .location(location.id)).absoluteString
        guard let qr = QRCodeGenerator.image(for: urlString) else { return }
        qrImage = qr

        let renderer = ImageRenderer(content: QRStickerView(location: location, qrImage: qr))
        renderer.scale = 3

        if let uiImage = renderer.uiImage, let data = uiImage.pngData() {
            pngURL = writeTemp(data, ext: "png")
        }
        if let data = renderPDF(renderer) {
            pdfURL = writeTemp(data, ext: "pdf")
        }
    }

    private func renderPDF(_ renderer: ImageRenderer<QRStickerView>) -> Data? {
        let pdfData = NSMutableData()
        renderer.render { size, renderInContext in
            var box = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
                  let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            renderInContext(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
        }
        return pdfData.length > 0 ? (pdfData as Data) : nil
    }

    private func writeTemp(_ data: Data, ext: String) -> URL? {
        let safe = location.name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "-")
        let name = safe.isEmpty ? "location" : safe
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-qr.\(ext)")
        do { try data.write(to: url); return url } catch { return nil }
    }

    private func printSticker() {
        guard let pdfURL, let data = try? Data(contentsOf: pdfURL) else { return }
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = "\(location.name) QR"
        info.outputType = .general
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = data
        controller.present(animated: true, completionHandler: nil)
    }
}
```

- [ ] **Step 2: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`. If `ImageRenderer<QRStickerView>` triggers a generic-inference error in `renderPDF`, confirm `QRStickerView` has no generic parameters (it doesn't).

- [ ] **Step 3: Commit**

```bash
git add MyStuff/Views/QRCodeSheet.swift
git commit -m "feat: add QRCodeSheet with PNG/PDF export and print"
```

---

## Task 5: `LocationDetailView` + Locations row navigation

**Files:**
- Create: `MyStuff/Views/LocationDetailView.swift`
- Modify: `MyStuff/Views/LocationsView.swift` (wrap stack with a path; row label → `NavigationLink(value:)`; add `navigationDestination`)

**Interfaces:**
- Consumes: `StuffViewModel` (`items(for:)`, `childLocations(for:)`, `recursiveItemCount(for:)`, `updateLocation(_:)`, `locations`), `QRCodeSheet`, `LocationFormSheet`, `ItemDetailSheet(item:viewModel:)`.
- Produces: `LocationDetailView(location: Location, viewModel: StuffViewModel)`.

- [ ] **Step 1: Create `LocationDetailView.swift`**

```swift
import SwiftUI

/// A location's home: its items and sub-locations, with Edit and QR actions.
/// Used both pushed (Locations tab) and presented as a sheet (deep-link / scan).
struct LocationDetailView: View {
    let location: Location
    @Bindable var viewModel: StuffViewModel

    @State private var showingEdit = false
    @State private var showingQR = false
    @State private var detailItem: Item?

    /// Follow live edits so the header/list update after Edit.
    private var live: Location {
        viewModel.locations.first(where: { $0.id == location.id }) ?? location
    }

    private var children: [Location] {
        viewModel.childLocations(for: live)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var directItems: [Item] {
        viewModel.items(for: live)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Text(live.emoji ?? "📍").font(.largeTitle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(live.name).font(.title2.weight(.semibold))
                        Text("\(viewModel.recursiveItemCount(for: live)) items")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            if !children.isEmpty {
                Section("Sub-locations") {
                    ForEach(children) { child in
                        NavigationLink {
                            LocationDetailView(location: child, viewModel: viewModel)
                        } label: {
                            Label { Text(child.name) } icon: { Text(child.emoji ?? "📍") }
                        }
                    }
                }
            }

            Section("Items") {
                if directItems.isEmpty {
                    Text("No items here yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(directItems) { item in
                        Button {
                            detailItem = item
                        } label: {
                            Text(item.name).foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
        .navigationTitle(live.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showingQR = true } label: { Image(systemName: "qrcode") }
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingQR) {
            QRCodeSheet(location: live)
        }
        .sheet(isPresented: $showingEdit) {
            LocationFormSheet(
                location: live,
                viewModel: viewModel,
                onSave: { name, emoji, parentId in
                    var updated = live
                    updated.name = name
                    updated.emoji = emoji
                    updated.parentId = parentId
                    Task { await viewModel.updateLocation(updated) }
                }
            )
        }
        .sheet(item: $detailItem) { item in
            ItemDetailSheet(item: item, viewModel: viewModel)
        }
        .containerBackground(LinearGradient.appBackground, for: .navigation)
    }
}
```

- [ ] **Step 2: Wire Locations rows to push the detail view**

In `MyStuff/Views/LocationsView.swift`:

a) Add a navigation path state near the other `@State` (top of `LocationsView`):

```swift
    @State private var path: [Location] = []
```

b) Change the opening `NavigationStack {` (line ~11) to:

```swift
        NavigationStack(path: $path) {
```

c) Replace the location-label `Button { editingLocation = entry.location } label: { ... }` block (lines ~122-141) with a `NavigationLink(value:)` wrapping the same label content:

```swift
                    // Location label -> detail
                    NavigationLink(value: entry.location) {
                        HStack {
                            Text(entry.location.emoji ?? "📍")
                                .font(.title2)
                            Text(entry.location.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(viewModel.recursiveItemCount(for: entry.location)) items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .padding(.vertical, 4)
                    }
```

d) Register the destination. Add this modifier on the `Group { ... }` inside the stack, right after `.navigationTitle("Locations")` (line ~19):

```swift
            .navigationDestination(for: Location.self) { loc in
                LocationDetailView(location: loc, viewModel: viewModel)
            }
```

e) The `editingLocation` state and its `.sheet(item: $editingLocation)` are now unreachable from the row tap. **Keep them** — Task 5 leaves editing to `LocationDetailView`'s Edit button, but removing the sheet is a separate concern. To avoid an unused-warning, leave `editingLocation` in place (still declared, harmless). Do NOT delete it in this task.

- [ ] **Step 3: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual check**

Run in simulator: Locations tab → tap a location → detail view shows items + sub-locations; tap **Edit** → form; tap **QR** → sheet renders the sticker; Share PDF/PNG present the share sheet.

- [ ] **Step 5: Commit**

```bash
git add MyStuff/Views/LocationDetailView.swift MyStuff/Views/LocationsView.swift
git commit -m "feat: LocationDetailView with QR/edit; push from Locations rows"
```

---

## Task 6: AASA + location deep-link routing in `ContentView`

**Files:**
- Modify: `.well-known/apple-app-site-association`
- Modify: `MyStuff/Views/ContentView.swift`

**Interfaces:**
- Consumes: `AppLink.parse(_:)`, `LocationDetailView`, `viewModel.locations`.
- Produces: opening a `/location/<id>` universal link presents `LocationDetailView` in a sheet.

- [ ] **Step 1: Add the `/location/*` component to AASA**

Replace the `components` array in `.well-known/apple-app-site-association`:

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["WDJPX25GFC.com.flyingturtle.mystuff"],
        "components": [
          { "/": "/item/*" },
          { "/": "/location/*" }
        ]
      }
    ]
  }
}
```

(You must redeploy the Cloudflare worker/host serving this file for Camera-app scans to route into the app. No worker code change is required.)

- [ ] **Step 2: Add location deep-link state + routing to `ContentView`**

In `MyStuff/Views/ContentView.swift`:

a) Add state next to the existing deep-link state (after line 9):

```swift
    @State private var pendingLocationId: String?
    @State private var deepLinkedLocation: Location?
```

b) Add a sheet for the location, right after the existing `.sheet(item: $deepLinkedItem)` block (line ~42):

```swift
        .sheet(item: $deepLinkedLocation) { location in
            NavigationStack {
                LocationDetailView(location: location, viewModel: viewModel)
            }
        }
```

c) Replace `handleDeepLink(_:)` (lines 51-54) to route by target:

```swift
    private func handleDeepLink(_ url: URL) {
        switch AppLink.parse(url) {
        case .item(let id):
            pendingNFCItemId = id
        case .location(let id):
            pendingLocationId = id
        case nil:
            break
        }
    }
```

d) Extend `resolvePendingDeepLink()` (lines 56-63) to also resolve locations:

```swift
    private func resolvePendingDeepLink() {
        if let id = pendingNFCItemId,
           let item = viewModel.items.first(where: { $0.id == id }) {
            pendingNFCItemId = nil
            deepLinkedItem = item
            HapticManager.success()
        }
        if let id = pendingLocationId,
           let location = viewModel.locations.first(where: { $0.id == id }) {
            pendingLocationId = nil
            deepLinkedLocation = location
            HapticManager.success()
        }
    }
```

e) Add a resolver trigger for locations. Change `.onChange(of: pendingNFCItemId)` (line 48) region to also watch locations and the pending location id:

```swift
        .onChange(of: viewModel.items) { resolvePendingDeepLink() }
        .onChange(of: viewModel.locations) { resolvePendingDeepLink() }
        .onChange(of: pendingNFCItemId) { resolvePendingDeepLink() }
        .onChange(of: pendingLocationId) { resolvePendingDeepLink() }
```

- [ ] **Step 3: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add .well-known/apple-app-site-association MyStuff/Views/ContentView.swift
git commit -m "feat: route /location/* universal links to LocationDetailView sheet"
```

---

## Task 7: `QRScannerView` + `QRScannerSheet`

**Files:**
- Create: `MyStuff/Views/QRScannerView.swift`

**Interfaces:**
- Consumes: VisionKit, `AppLink.parse(_:)`.
- Produces:
  - `QRScannerView(onScan: (String) -> Void)` — raw representable; `QRScannerView.isSupported: Bool`.
  - `QRScannerSheet(onLocation: (String) -> Void)` — full sheet that parses a scanned code and calls `onLocation` with a **location id**, or shows an inline error for non-location / non-app codes.

- [ ] **Step 1: Create `QRScannerView.swift`**

```swift
import SwiftUI
import VisionKit

/// VisionKit live QR scanner. Reports the first decoded barcode string via `onScan`.
struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        try? vc.startScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private var handled = false

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ scanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            handle(addedItems)
        }

        func dataScanner(_ scanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle([item])
        }

        private func handle(_ items: [RecognizedItem]) {
            guard !handled else { return }
            for case let .barcode(barcode) in items {
                if let payload = barcode.payloadStringValue {
                    handled = true
                    onScan(payload)
                    return
                }
            }
        }
    }
}

/// Sheet wrapper: presents the scanner, parses the code via `AppLink`,
/// and calls `onLocation(id)` for a location code. Non-location / non-app
/// codes surface an inline message and keep scanning.
struct QRScannerSheet: View {
    let onLocation: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Group {
                if QRScannerView.isSupported {
                    QRScannerView { payload in handle(payload) }
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView("Scanning unavailable",
                                           systemImage: "camera",
                                           description: Text("This device can’t scan QR codes."))
                }
            }
            .overlay(alignment: .bottom) {
                if let errorText {
                    Text(errorText)
                        .font(.callout)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 32)
                }
            }
            .navigationTitle("Scan QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func handle(_ payload: String) {
        guard let url = URL(string: payload), let target = AppLink.parse(url) else {
            errorText = "Not a MyStuff code"
            return
        }
        guard case .location(let id) = target else {
            errorText = "That’s not a location code"
            return
        }
        HapticManager.success()
        onLocation(id)
        dismiss()
    }
}
```

- [ ] **Step 2: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`. (`ContentUnavailableView` with `description:` label is iOS 17+ — fine for the iOS 26 target.)

- [ ] **Step 3: Commit**

```bash
git add MyStuff/Views/QRScannerView.swift
git commit -m "feat: add VisionKit QR scanner + QRScannerSheet"
```

---

## Task 8: Global Scan button in Locations tab

**Files:**
- Modify: `MyStuff/Views/LocationsView.swift`

**Interfaces:**
- Consumes: `QRScannerSheet`, `viewModel.locations`, the `path` state from Task 5.
- Produces: a **Scan** toolbar button that pushes the scanned location's `LocationDetailView`.

- [ ] **Step 1: Add scanner state + toolbar button**

In `MyStuff/Views/LocationsView.swift`:

a) Add state near `path`:

```swift
    @State private var showingScanner = false
```

b) Add a scan button to the toolbar. The existing toolbar has one `ToolbarItem(placement: .primaryAction)` with the `+` button (lines ~20-27). Add a second toolbar item beside it:

```swift
                ToolbarItem(placement: .topBarLeading) {
                    if QRScannerView.isSupported {
                        Button {
                            showingScanner = true
                        } label: {
                            Image(systemName: "qrcode.viewfinder")
                        }
                    }
                }
```

c) Present the scanner sheet. Add after the existing `.sheet(item: $editingLocation)` modifier (line ~49):

```swift
            .sheet(isPresented: $showingScanner) {
                QRScannerSheet { locationId in
                    if let loc = viewModel.locations.first(where: { $0.id == locationId }) {
                        path.append(loc)
                    }
                }
            }
```

Because `QRScannerSheet` dismisses itself before `onLocation` returns control, appending to `path` pushes `LocationDetailView` cleanly onto the tab's stack (no sheet-over-sheet).

- [ ] **Step 2: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual check**

Simulator has no camera → the Scan button is hidden (`isSupported == false`). On a device: Locations → Scan → point at a location QR → its detail pushes.

- [ ] **Step 4: Commit**

```bash
git add MyStuff/Views/LocationsView.swift
git commit -m "feat: global QR scan in Locations tab"
```

---

## Task 9: Scan-to-move in `MoveItemSheet`

**Files:**
- Modify: `MyStuff/Views/HomeView.swift` (`MoveItemSheet`, struct at line ~648)

**Interfaces:**
- Consumes: `QRScannerView.isSupported`, `QRScannerSheet`, existing `onMove: (String?) -> Void`, `viewModel.locations`.
- Produces: a **Scan QR** row in `MoveItemSheet` that moves the item to a scanned location.

- [ ] **Step 1: Add scanner state + Scan row to `MoveItemSheet`**

In `MyStuff/Views/HomeView.swift`, `MoveItemSheet`:

a) Add state after `@Environment(\.horizontalSizeClass)`:

```swift
    @State private var showingScanner = false
    @State private var unknownScan = false
```

b) In `content`'s `List`, add a new `Section` above the existing `Section("Move \"\(item.name)\" to…")`:

```swift
                if QRScannerView.isSupported {
                    Section {
                        Button {
                            showingScanner = true
                        } label: {
                            Label("Scan location QR", systemImage: "qrcode.viewfinder")
                        }
                    }
                }
```

c) Attach the scanner sheet + an alert to the `List` (after the `.toolbar { ... }` modifier, before the closing of `content`):

```swift
            .sheet(isPresented: $showingScanner) {
                QRScannerSheet { locationId in
                    if viewModel.locations.contains(where: { $0.id == locationId }) {
                        onMove(locationId)
                        dismiss()
                    } else {
                        unknownScan = true
                    }
                }
            }
            .alert("Location not found", isPresented: $unknownScan) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("That QR points to a location that no longer exists.")
            }
```

- [ ] **Step 2: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Full manual verification pass**

On a physical device (camera + NFC required for the regression):
1. Locations → a location → **QR** → **Print**: AirPrint preview shows the sticker (QR + emoji + name).
2. Share **PDF** and **PNG** → files open correctly (Files/Quick Look).
3. Print/screenshot the QR, scan with the **system Camera app** → MyStuff opens → correct location's items sheet.
4. Locations → **Scan** (global) → scan the QR → location detail pushes.
5. Home or Items → long-press/move an item → **Scan location QR** → scan → item moves to that location (verify in the list).
6. Scan a random non-MyStuff QR in-app → "Not a MyStuff code".
7. **NFC regression:** pair/scan an NFC item tag → still opens the item update sheet (validates the Task 1 `AppLink` refactor).

- [ ] **Step 4: Commit**

```bash
git add MyStuff/Views/HomeView.swift
git commit -m "feat: scan a location QR to move an item"
```

---

## Self-Review Notes

- **Spec coverage:** QR generation (T2/T3), PNG+PDF export + print (T4), Location detail view as QR home (T5), Camera-app deep-link → items sheet (T1 AppLink + T6 AASA/ContentView), in-app global scan (T7/T8), scan-to-move (T9), AppLink router + NFC regression (T1). All spec sections mapped.
- **Type consistency:** `AppLink.Target`, `AppLink.parse`/`url(for:)`, `QRCodeGenerator.image(for:scale:)`, `QRStickerView(location:qrImage:)`, `QRCodeSheet(location:)`, `LocationDetailView(location:viewModel:)`, `QRScannerView(onScan:)`/`.isSupported`, `QRScannerSheet(onLocation:)` — names/signatures used identically across tasks.
- **No unit tests:** intentional — no test target exists (CLAUDE.md); verification is `xcodebuild` + manual, per Global Constraints.
- **Known caveat:** DataScanner is unavailable in the Simulator, so scan buttons only appear on device; QR generation/export/print and deep-link routing are all testable in the Simulator.
