# Item Recognition Scan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A camera scan session that recognizes known items from on-device image embeddings and batch-moves them to a destination chosen by NFC, QR, or manual pick, after one review step.

**Architecture:** Three pure/service units (`ItemMatcher`, `ImageEmbedder`, `RecognitionStore`) feed a testable `ScanSessionModel`; SwiftUI views sit on top and perform Firestore writes through the existing `StuffViewModel`. Recognition references live on-device only, per uid. The existing `DataScannerViewController` wrapper is reused for both QR and still capture.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, Vision (Swift API: `GenerateImageFeaturePrintRequest`, `GenerateForegroundInstanceMaskRequest`), VisionKit `DataScannerViewController`, Accelerate, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-10-item-recognition-scan-design.md`

## Global Constraints

- iOS deployment target 26.0, `SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete`. No warnings-as-errors, but new code must compile without concurrency errors.
- No new package dependencies. No Firestore schema or `firestore.rules` change.
- `@Observable` (never `ObservableObject`); views take models as plain `let` / `@Bindable`.
- UI chrome uses `.ultraThinMaterial`; haptics go through `HapticManager`.
- Match the comment density and naming of surrounding code (doc comment on each type and on non-obvious members).
- Matching constants, verbatim from the spec: accept `0.55`, margin `0.08`, reject `0.90`. Store constants: cap `8` per item, `5` enrolled, learned dedupe `0.15`.
- Reference sources: `itemPhoto` comes from the **item** photo (`itemPhotoURL` / `remoteItemPhotoURL`), never the location photo (`photoURL`).
- Nothing is written to Firestore before the review sheet's Confirm, except items the user explicitly creates.
- `MyStuff/GoogleService-Info.plist` is gitignored — never `git add` it.
- Commits: conventional prefix, terse subject, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

**Commands used throughout**

Build:

```bash
xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | grep -E "error:|warning: unre|BUILD (SUCCEEDED|FAILED)" | tail -30
```

Test:

```bash
xcodebuild test -project MyStuff.xcodeproj -scheme MyStuff -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -only-testing:MyStuffTests 2>&1 | grep -E "error:|✘|failed|issue|TEST (SUCCEEDED|FAILED)|Test run" | tail -40
```

## Deviations from the spec (spec updated to match)

- `ImageEmbedder.embed` takes encoded image `Data` and `Embedding` carries a JPEG `thumbnail: Data` — both `Sendable`, so no `CGImage` crosses an actor boundary.
- `ItemReference.vector` is `[Float]` in memory, raw Float32 bytes on disk.
- `MatchOutcome.none` is named `noMatch` (avoids colliding with `Optional.none`).
- No new `ScanCameraView`: `QRScannerView` gains an optional `ScanCameraController`; the shared viewfinder UI is `ScanCaptureStage`.
- `StuffViewModel.moveItems` returns `Bool` so the review sheet can stay open on failure.

## File Structure

| File | Responsibility |
|---|---|
| `MyStuff/Models/ItemReference.swift` (new) | Reference record + Float32 ⇄ `Data` helpers |
| `MyStuff/Services/ItemMatcher.swift` (new) | Pure distance, ranking, classification |
| `MyStuff/Services/ImageEmbedder.swift` (new) | Protocol, `Embedding`, Vision implementation |
| `MyStuff/Services/RecognitionStore.swift` (new) | On-device persistence, caps, item-photo sync |
| `MyStuff/Services/ItemPhotoLoader.swift` (new) | Item-photo bytes, local first then remote |
| `MyStuff/ViewModels/ScanSessionModel.swift` (new) | Session state machine |
| `MyStuff/Views/Scan/ScanCaptureStage.swift` (new) | Viewfinder + shutter + library fallback, `ScanCameraController` |
| `MyStuff/Views/Scan/ItemScanView.swift` (new) | Session screen |
| `MyStuff/Views/Scan/ScanMatchCard.swift` (new) | Candidate chooser, `ScanItemRow`, item search list |
| `MyStuff/Views/Scan/ScanReviewSheet.swift` (new) | Review + confirm |
| `MyStuff/Views/Scan/RecognitionPhotosSection.swift` (new) | Item-detail reference strip + `EnrollCaptureView` |
| `MyStuffTests/*.swift` (new) | Unit tests |
| `MyStuff/ViewModels/StuffViewModel.swift` | Store ownership, hooks, move helper |
| `MyStuff/Views/QRScannerView.swift` | Optional capture controller |
| `MyStuff/Views/MoveItemsHereSheet.swift` | Use move helper |
| `MyStuff/Views/{LocationDetailView,NFCTabView,HomeView,ItemDetailSheet}.swift` | Entry points / section |
| `MyStuff/Info.plist`, `MyStuff.xcodeproj/*`, `CLAUDE.md` | Camera string, test target, docs |

## Review Focus

1. **First use, empty reference library** — no item has a reference yet; a capture must still open the match card with "Other item…" / "New item", not fail or auto-accept. (Task 4)
2. **Same item captured twice in one session** — one tray entry, one move, both captures available for learning. (Task 4)
3. **Item deleted on another device mid-session** — it leaves the tray and gets no learned reference. (Task 4)
4. **Corrupt or truncated reference file on disk** — skipped on load; other references survive. (Task 3)
5. **Vector of the wrong length** (file from a different model build under the same id) — ignored by ranking, never a crash. (Task 1)

---

### Task 1: Test target, `ItemReference`, `ItemMatcher`

**Files:**
- Modify: `MyStuff.xcodeproj/project.pbxproj`
- Modify: `MyStuff.xcodeproj/xcshareddata/xcschemes/MyStuff.xcscheme`
- Create: `MyStuff/Models/ItemReference.swift`
- Create: `MyStuff/Services/ItemMatcher.swift`
- Test: `MyStuffTests/ItemMatcherTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct ItemReference: Codable, Identifiable, Hashable, Sendable` with `id, itemId, source, modelID, vector: [Float], sourceKey: String?, createdAt` and `init(id: String = UUID().uuidString, itemId: String, source: Source, modelID: String, vector: [Float], sourceKey: String? = nil, createdAt: Date = .now)`; `enum Source: String { case itemPhoto, enrolled, learned }`.
  - `extension Array where Element == Float { init(rawData: Data); var rawData: Data }`
  - `struct ItemMatch: Sendable, Equatable { let itemId: String; let distance: Float }`
  - `enum MatchOutcome: Sendable, Equatable { case confident(ItemMatch, alternatives: [ItemMatch]); case ambiguous([ItemMatch]); case noMatch([ItemMatch]) }`
  - `enum ItemMatcher` with `acceptDistance`, `acceptMargin`, `rejectDistance`, `maxCandidates`, `static func distance(_ a: [Float], _ b: [Float]) -> Float`, `static func rank(_ query: [Float], references: [ItemReference], knownItemIds: Set<String>, modelID: String) -> [ItemMatch]`, `static func classify(_ ranked: [ItemMatch]) -> MatchOutcome`.

- [ ] **Step 1: Add the `MyStuffTests` target to the project**

Run from the repo root:

```bash
mkdir -p MyStuffTests && python3 - <<'EOF'
import pathlib
p = pathlib.Path("MyStuff.xcodeproj/project.pbxproj")
s = p.read_text()

def tabs(block):
    return block.replace("    ", "\t")

def before(marker, text):
    global s
    assert s.count(marker) == 1, marker
    s = s.replace(marker, tabs(text) + marker)

def after(marker, text):
    global s
    assert s.count(marker) == 1, marker
    s = s.replace(marker, marker + tabs(text))

before("/* Begin PBXFileReference section */", """/* Begin PBXContainerItemProxy section */
        BB000091 /* PBXContainerItemProxy */ = {
            isa = PBXContainerItemProxy;
            containerPortal = AA000000 /* Project object */;
            proxyType = 1;
            remoteGlobalIDString = AA000010;
            remoteInfo = MyStuff;
        };
/* End PBXContainerItemProxy section */

""")
before("/* End PBXFileReference section */",
       "        BB000001 /* MyStuffTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = MyStuffTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };\n")
before("/* End PBXFileSystemSynchronizedRootGroup section */", """        BB000003 /* MyStuffTests */ = {
            isa = PBXFileSystemSynchronizedRootGroup;
            path = MyStuffTests;
            sourceTree = "<group>";
        };
""")
before("/* End PBXFrameworksBuildPhase section */", """        BB000020 /* Frameworks */ = {
            isa = PBXFrameworksBuildPhase;
            buildActionMask = 2147483647;
            files = (
            );
            runOnlyForDeploymentPostprocessing = 0;
        };
""")
after("\t\t\t\tAA000003 /* MyStuff */,\n\t\t\t\t466CA64D3007811700AC0825 /* Frameworks */,\n",
      "                BB000003 /* MyStuffTests */,\n")
after("\t\t\t\tAA000001 /* MyStuff.app */,\n",
      "                BB000001 /* MyStuffTests.xctest */,\n")
before("/* End PBXNativeTarget section */", """        BB000010 /* MyStuffTests */ = {
            isa = PBXNativeTarget;
            buildConfigurationList = BB000060 /* Build configuration list for PBXNativeTarget "MyStuffTests" */;
            buildPhases = (
                BB000040 /* Sources */,
                BB000020 /* Frameworks */,
                BB000050 /* Resources */,
            );
            buildRules = (
            );
            dependencies = (
                BB000092 /* PBXTargetDependency */,
            );
            fileSystemSynchronizedGroups = (
                BB000003 /* MyStuffTests */,
            );
            name = MyStuffTests;
            packageProductDependencies = (
            );
            productName = MyStuffTests;
            productReference = BB000001 /* MyStuffTests.xctest */;
            productType = "com.apple.product-type.bundle.unit-test";
        };
""")
after("\t\t\t\t\tAA000010 = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n\t\t\t\t\t};\n", """                    BB000010 = {
                        CreatedOnToolsVersion = 16.0;
                        TestTargetID = AA000010;
                    };
""")
after("\t\t\ttargets = (\n\t\t\t\tAA000010 /* MyStuff */,\n",
      "                BB000010 /* MyStuffTests */,\n")
before("/* End PBXResourcesBuildPhase section */", """        BB000050 /* Resources */ = {
            isa = PBXResourcesBuildPhase;
            buildActionMask = 2147483647;
            files = (
            );
            runOnlyForDeploymentPostprocessing = 0;
        };
""")
before("/* End PBXSourcesBuildPhase section */", """        BB000040 /* Sources */ = {
            isa = PBXSourcesBuildPhase;
            buildActionMask = 2147483647;
            files = (
            );
            runOnlyForDeploymentPostprocessing = 0;
        };
""")
before("/* Begin XCBuildConfiguration section */", """/* Begin PBXTargetDependency section */
        BB000092 /* PBXTargetDependency */ = {
            isa = PBXTargetDependency;
            target = AA000010 /* MyStuff */;
            targetProxy = BB000091 /* PBXContainerItemProxy */;
        };
/* End PBXTargetDependency section */

""")
config = """        %(id)s /* %(name)s */ = {
            isa = XCBuildConfiguration;
            buildSettings = {
                BUNDLE_LOADER = "$(TEST_HOST)";
                CODE_SIGN_STYLE = Automatic;
                CURRENT_PROJECT_VERSION = 1;
                DEVELOPMENT_TEAM = WDJPX25GFC;
                GENERATE_INFOPLIST_FILE = YES;
                IPHONEOS_DEPLOYMENT_TARGET = 26.0;
                MARKETING_VERSION = 1.0;
                PRODUCT_BUNDLE_IDENTIFIER = com.flyingturtle.mystuff.tests;
                PRODUCT_NAME = "$(TARGET_NAME)";
                SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
                SWIFT_EMIT_LOC_STRINGS = NO;
                SWIFT_VERSION = 6.0;
                TARGETED_DEVICE_FAMILY = "1,2";
                TEST_HOST = "$(BUILT_PRODUCTS_DIR)/MyStuff.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/MyStuff";
            };
            name = %(name)s;
        };
"""
before("/* End XCBuildConfiguration section */",
       config % {"id": "BB000061", "name": "Debug"} + config % {"id": "BB000062", "name": "Release"})
before("/* End XCConfigurationList section */", """        BB000060 /* Build configuration list for PBXNativeTarget "MyStuffTests" */ = {
            isa = XCConfigurationList;
            buildConfigurations = (
                BB000061 /* Debug */,
                BB000062 /* Release */,
            );
            defaultConfigurationIsVisible = 0;
            defaultConfigurationName = Release;
        };
""")
p.write_text(s)

sp = pathlib.Path("MyStuff.xcodeproj/xcshareddata/xcschemes/MyStuff.xcscheme")
x = sp.read_text()
marker = '      shouldAutocreateTestPlan = "YES">\n   </TestAction>'
assert x.count(marker) == 1
x = x.replace(marker, '''      shouldAutocreateTestPlan = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "BB000010"
               BuildableName = "MyStuffTests.xctest"
               BlueprintName = "MyStuffTests"
               ReferencedContainer = "container:MyStuff.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>''')
sp.write_text(x)
EOF
xcodebuild -list -project MyStuff.xcodeproj 2>&1 | sed -n '/Targets:/,/Build Configurations:/p'
```

Expected: the target list shows both `MyStuff` and `MyStuffTests`. If `xcodebuild -list` reports a parse error, the printed line number points at the malformed block in `project.pbxproj`; fix that block's braces/semicolons and rerun.

- [ ] **Step 2: Write the failing tests**

Create `MyStuffTests/ItemMatcherTests.swift`:

```swift
import Testing
@testable import MyStuff

struct ItemMatcherTests {

    private func ref(_ itemId: String, _ vector: [Float], model: String = "m1") -> ItemReference {
        ItemReference(itemId: itemId, source: .learned, modelID: model, vector: vector)
    }

    private func match(_ itemId: String, _ distance: Float) -> ItemMatch {
        ItemMatch(itemId: itemId, distance: distance)
    }

    // MARK: - distance

    @Test func distanceIsEuclidean() {
        #expect(ItemMatcher.distance([0, 0], [3, 4]) == 5)
    }

    @Test func distanceOfMismatchedLengthsIsInfinite() {
        #expect(ItemMatcher.distance([1, 0], [1, 0, 0]) == .infinity)
        #expect(ItemMatcher.distance([], []) == .infinity)
    }

    // MARK: - rank

    @Test func rankUsesNearestReferencePerItem() {
        let ranked = ItemMatcher.rank(
            [0, 0],
            references: [ref("a", [3, 4]), ref("a", [0, 1]), ref("a", [6, 8])],
            knownItemIds: ["a"],
            modelID: "m1"
        )
        #expect(ranked == [match("a", 1)])
    }

    @Test func rankSortsNearestFirst() {
        let ranked = ItemMatcher.rank(
            [0, 0],
            references: [ref("far", [0, 5]), ref("near", [0, 1]), ref("mid", [0, 2])],
            knownItemIds: ["far", "near", "mid"],
            modelID: "m1"
        )
        #expect(ranked.map(\.itemId) == ["near", "mid", "far"])
    }

    @Test func rankSkipsUnknownItemsAndOtherModels() {
        let ranked = ItemMatcher.rank(
            [0, 0],
            references: [ref("deleted", [0, 1]), ref("a", [0, 1], model: "m2"), ref("b", [0, 2])],
            knownItemIds: ["a", "b"],
            modelID: "m1"
        )
        #expect(ranked == [match("b", 2)])
    }

    @Test func rankSkipsVectorsOfWrongLength() {
        let ranked = ItemMatcher.rank(
            [0, 0],
            references: [ref("short", [1]), ref("ok", [0, 1])],
            knownItemIds: ["short", "ok"],
            modelID: "m1"
        )
        #expect(ranked == [match("ok", 1)])
    }

    @Test func rankOfNoReferencesIsEmpty() {
        #expect(ItemMatcher.rank([0, 0], references: [], knownItemIds: ["a"], modelID: "m1").isEmpty)
    }

    // MARK: - classify

    @Test func classifyConfidentWhenCloseAndClear() {
        let outcome = ItemMatcher.classify([match("a", 0.30), match("b", 0.70), match("c", 0.80)])
        #expect(outcome == .confident(match("a", 0.30), alternatives: [match("b", 0.70), match("c", 0.80)]))
    }

    @Test func classifyConfidentAtAcceptBoundaryWithNoRunnerUp() {
        let outcome = ItemMatcher.classify([match("a", ItemMatcher.acceptDistance)])
        #expect(outcome == .confident(match("a", ItemMatcher.acceptDistance), alternatives: []))
    }

    @Test func classifyAmbiguousWhenRunnerUpTooClose() {
        let ranked = [match("a", 0.30), match("b", 0.33)]
        #expect(ItemMatcher.classify(ranked) == .ambiguous(ranked))
    }

    @Test func classifyAmbiguousBetweenAcceptAndReject() {
        let ranked = [match("a", 0.70)]
        #expect(ItemMatcher.classify(ranked) == .ambiguous(ranked))
    }

    @Test func classifyNoMatchWhenBeyondReject() {
        let ranked = [match("a", 0.95), match("b", 1.20)]
        #expect(ItemMatcher.classify(ranked) == .noMatch(ranked))
    }

    @Test func classifyNoMatchWhenEmpty() {
        #expect(ItemMatcher.classify([]) == .noMatch([]))
    }

    @Test func classifyCapsCandidatesAtThree() {
        let ranked = [match("a", 0.60), match("b", 0.61), match("c", 0.62), match("d", 0.63)]
        #expect(ItemMatcher.classify(ranked) == .ambiguous(Array(ranked.prefix(3))))
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run the Test command. Expected: build fails with `cannot find 'ItemMatcher' in scope` / `cannot find type 'ItemReference'`.

- [ ] **Step 4: Implement `ItemReference`**

Create `MyStuff/Models/ItemReference.swift`:

```swift
import Foundation

/// One recognition sample for an item: an embedding vector plus bookkeeping.
/// Lives on-device only (see `RecognitionStore`); never written to Firestore.
struct ItemReference: Codable, Identifiable, Hashable, Sendable {
    enum Source: String, Codable, Sendable {
        /// Derived from the item's item photo. At most one per item.
        case itemPhoto
        /// Captured by the user through "Add angles".
        case enrolled
        /// A scan capture the user confirmed for this item.
        case learned
    }

    var id: String
    var itemId: String
    var source: Source
    /// Model + revision that produced `vector`. Vectors only compare within one modelID.
    var modelID: String
    var vector: [Float]
    /// `itemPhoto` only: `remoteItemPhotoURL ?? itemPhotoURL` at embed time, to detect a changed photo.
    var sourceKey: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        itemId: String,
        source: Source,
        modelID: String,
        vector: [Float],
        sourceKey: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.itemId = itemId
        self.source = source
        self.modelID = modelID
        self.vector = vector
        self.sourceKey = sourceKey
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, itemId, source, modelID, vector, sourceKey, createdAt
    }

    /// The vector is stored as raw Float32 bytes — a third the size of a plist number array.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        itemId = try container.decode(String.self, forKey: .itemId)
        source = try container.decode(Source.self, forKey: .source)
        modelID = try container.decode(String.self, forKey: .modelID)
        vector = [Float](rawData: try container.decode(Data.self, forKey: .vector))
        sourceKey = try container.decodeIfPresent(String.self, forKey: .sourceKey)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(itemId, forKey: .itemId)
        try container.encode(source, forKey: .source)
        try container.encode(modelID, forKey: .modelID)
        try container.encode(vector.rawData, forKey: .vector)
        try container.encodeIfPresent(sourceKey, forKey: .sourceKey)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

extension Array where Element == Float {
    /// Reads raw Float32 bytes. Trailing bytes that don't fill a Float are dropped.
    init(rawData: Data) {
        let count = rawData.count / MemoryLayout<Float>.size
        self = rawData.withUnsafeBytes { bytes in
            (0..<count).map { bytes.loadUnaligned(fromByteOffset: $0 * MemoryLayout<Float>.size, as: Float.self) }
        }
    }

    var rawData: Data {
        withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
```

- [ ] **Step 5: Implement `ItemMatcher`**

Create `MyStuff/Services/ItemMatcher.swift`:

```swift
import Accelerate
import Foundation

/// One candidate item for a captured photo. Smaller distance = more alike.
struct ItemMatch: Sendable, Equatable {
    let itemId: String
    let distance: Float
}

/// How sure the matcher is about a capture. Candidates are always nearest first.
enum MatchOutcome: Sendable, Equatable {
    /// Close enough, and clearly ahead of the runner-up, to accept without asking.
    case confident(ItemMatch, alternatives: [ItemMatch])
    /// Plausible, but the user has to choose.
    case ambiguous([ItemMatch])
    /// Nothing near enough. The nearest guesses are still offered.
    case noMatch([ItemMatch])
}

/// Nearest-neighbour lookup over recognition references. Pure — no I/O, no state.
enum ItemMatcher {
    // Starting estimates, not measured values: tune on a real device using the
    // DEBUG distance readout on the match card.
    static let acceptDistance: Float = 0.55
    static let acceptMargin: Float = 0.08
    static let rejectDistance: Float = 0.90
    static let maxCandidates = 3

    /// Euclidean distance — what Vision's `FeaturePrintObservation.distance(to:)` computes.
    /// Vectors of different (or zero) length are incomparable: `.infinity`.
    static func distance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return .infinity }
        return vDSP.distanceSquared(a, b).squareRoot()
    }

    /// Every known item that has a comparable reference, nearest first. An item's
    /// distance is that of its closest reference.
    static func rank(
        _ query: [Float],
        references: [ItemReference],
        knownItemIds: Set<String>,
        modelID: String
    ) -> [ItemMatch] {
        var nearest: [String: Float] = [:]
        for reference in references where reference.modelID == modelID && knownItemIds.contains(reference.itemId) {
            let separation = distance(query, reference.vector)
            guard separation.isFinite else { continue }
            if separation < nearest[reference.itemId, default: .infinity] {
                nearest[reference.itemId] = separation
            }
        }
        return nearest
            .map { ItemMatch(itemId: $0.key, distance: $0.value) }
            .sorted { ($0.distance, $0.itemId) < ($1.distance, $1.itemId) }
    }

    static func classify(_ ranked: [ItemMatch]) -> MatchOutcome {
        let top = Array(ranked.prefix(maxCandidates))
        guard let best = top.first, best.distance <= rejectDistance else { return .noMatch(top) }
        let isClear = ranked.dropFirst().first.map { $0.distance - best.distance >= acceptMargin } ?? true
        if best.distance <= acceptDistance && isClear {
            return .confident(best, alternatives: Array(top.dropFirst()))
        }
        return .ambiguous(top)
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run the Test command. Expected: `** TEST SUCCEEDED **`, 14 tests passed.

- [ ] **Step 7: Commit**

```bash
git add MyStuff.xcodeproj MyStuffTests MyStuff/Models/ItemReference.swift MyStuff/Services/ItemMatcher.swift
git commit -m "feat: item matcher + unit test target

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `ImageEmbedder` and the Vision implementation

**Files:**
- Create: `MyStuff/Services/ImageEmbedder.swift`
- Test: `MyStuffTests/FakeEmbedder.swift`, `MyStuffTests/VisionFeaturePrintEmbedderTests.swift`

**Interfaces:**
- Consumes: `[Float].init(rawData:)` (Task 1), `ImageDownsampler.downsample(data:maxPixelSize:)` (existing).
- Produces:
  - `struct Embedding: Sendable, Equatable { let vector: [Float]; let thumbnail: Data }`
  - `enum EmbeddingError: Error { case unreadableImage, emptyVector }`
  - `protocol ImageEmbedder: Sendable { var modelID: String { get }; func embed(imageData: Data) async throws -> Embedding }`
  - `struct VisionFeaturePrintEmbedder: ImageEmbedder` with `static func centerSquare(of image: CGImage) -> CGImage`
  - Test-only `struct FakeEmbedder: ImageEmbedder` (`var modelID = "fake-1"`); `Data("1,0".utf8)` embeds to `[1, 0]`, non-numeric bytes throw.

- [ ] **Step 1: Write the fake embedder and the failing tests**

Create `MyStuffTests/FakeEmbedder.swift`:

```swift
import Foundation
@testable import MyStuff

/// Reads the "image" bytes as comma-separated floats: `Data("1,0".utf8)` embeds
/// to `[1, 0]`. Anything else throws, standing in for an unreadable photo.
struct FakeEmbedder: ImageEmbedder {
    var modelID = "fake-1"

    func embed(imageData: Data) async throws -> Embedding {
        let parts = String(decoding: imageData, as: UTF8.self).split(separator: ",").map { Float($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { throw EmbeddingError.unreadableImage }
        return Embedding(vector: parts.compactMap { $0 }, thumbnail: imageData)
    }
}

extension Embedding {
    /// An embedding whose thumbnail re-embeds to the same vector under `FakeEmbedder`.
    static func fake(_ vector: [Float]) -> Embedding {
        Embedding(vector: vector, thumbnail: Data(vector.map { "\($0)" }.joined(separator: ",").utf8))
    }
}

extension Data {
    /// Fake image bytes for `FakeEmbedder`.
    static func fakeImage(_ vector: [Float]) -> Data { Embedding.fake(vector).thumbnail }
}
```

Create `MyStuffTests/VisionFeaturePrintEmbedderTests.swift`:

```swift
import Testing
import UIKit
@testable import MyStuff

/// Runs the real Vision pipeline in the simulator: proves the request types and
/// the Float decoding work, not that recognition is accurate.
@MainActor
struct VisionFeaturePrintEmbedderTests {

    /// A filled circle on a plain background, as JPEG.
    private func image(circle: UIColor, background: UIColor) -> Data {
        let size = CGSize(width: 400, height: 400)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            circle.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 100, y: 100, width: 200, height: 200))
        }.jpegData(compressionQuality: 0.9)!
    }

    @Test func sameImageEmbedsToTheSameVector() async throws {
        let embedder = VisionFeaturePrintEmbedder()
        let data = image(circle: .red, background: .white)
        let first = try await embedder.embed(imageData: data)
        let second = try await embedder.embed(imageData: data)
        #expect(!first.vector.isEmpty)
        #expect(ItemMatcher.distance(first.vector, second.vector) < 0.01)
    }

    @Test func thumbnailIsADecodableImageNoLargerThan320() async throws {
        let embedding = try await VisionFeaturePrintEmbedder().embed(imageData: image(circle: .red, background: .white))
        let thumbnail = try #require(UIImage(data: embedding.thumbnail)?.cgImage)
        #expect(max(thumbnail.width, thumbnail.height) <= 320)
    }

    @Test func differentImagesAreFartherApartThanIdenticalOnes() async throws {
        let embedder = VisionFeaturePrintEmbedder()
        let red = try await embedder.embed(imageData: image(circle: .red, background: .white))
        let again = try await embedder.embed(imageData: image(circle: .red, background: .white))
        let other = try await embedder.embed(imageData: image(circle: .black, background: .yellow))
        #expect(ItemMatcher.distance(red.vector, other.vector) > ItemMatcher.distance(red.vector, again.vector))
    }

    @Test func unreadableDataThrows() async {
        await #expect(throws: EmbeddingError.self) {
            try await VisionFeaturePrintEmbedder().embed(imageData: Data("not an image".utf8))
        }
    }

    @Test func centerSquareIsCentredAndSquare() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let wide = try #require(UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100), format: format)
            .image { _ in }.cgImage)
        let square = VisionFeaturePrintEmbedder.centerSquare(of: wide)
        #expect(square.width == 70)
        #expect(square.height == 70)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the Test command. Expected: build fails with `cannot find type 'ImageEmbedder'`.

- [ ] **Step 3: Implement the embedder**

Create `MyStuff/Services/ImageEmbedder.swift`:

```swift
import CoreImage
import Foundation
import UIKit
import Vision

/// The result of embedding one photo.
struct Embedding: Sendable, Equatable {
    let vector: [Float]
    /// JPEG of the crop that was embedded, at most 320 px. Stored as the reference thumbnail.
    let thumbnail: Data
}

enum EmbeddingError: Error {
    case unreadableImage
    case emptyVector
}

/// Turns a photo into a vector such that photos of the same object land close
/// together. Behind a protocol so the model can be swapped (e.g. for MobileCLIP)
/// without touching storage, matching, or UI.
protocol ImageEmbedder: Sendable {
    /// Identifies model + revision. Vectors are only comparable within one modelID.
    var modelID: String { get }
    /// `imageData` is an encoded image (JPEG/HEIC/PNG); EXIF orientation is honoured.
    func embed(imageData: Data) async throws -> Embedding
}

/// Apple Vision feature print over the photo's foreground subject.
struct VisionFeaturePrintEmbedder: ImageEmbedder {
    let modelID = "vision-featureprint-r2"

    static let workingPixelSize: CGFloat = 1024
    static let thumbnailPixelSize: CGFloat = 320
    /// Subjects smaller than this are treated as noise and ignored.
    static let minSubjectSide = 64
    static let fallbackCropFraction: CGFloat = 0.7

    func embed(imageData: Data) async throws -> Embedding {
        guard let source = ImageDownsampler.downsample(data: imageData, maxPixelSize: Self.workingPixelSize)?.cgImage else {
            throw EmbeddingError.unreadableImage
        }
        // Embed the subject alone so the shelf behind it doesn't dominate the vector.
        // References and scan captures both go through here, so they stay comparable.
        let crop = (try? await Self.subjectCrop(of: source)) ?? Self.centerSquare(of: source)

        let observation = try await GenerateImageFeaturePrintRequest(.revision2).perform(on: crop)
        guard observation.elementType == .float else { throw EmbeddingError.emptyVector }
        let vector = [Float](rawData: observation.data)
        guard !vector.isEmpty else { throw EmbeddingError.emptyVector }

        guard let jpeg = UIImage(cgImage: crop).jpegData(compressionQuality: 0.8),
              let thumbnail = ImageDownsampler.downsample(data: jpeg, maxPixelSize: Self.thumbnailPixelSize)?
                .jpegData(compressionQuality: 0.7)
        else { throw EmbeddingError.unreadableImage }

        return Embedding(vector: vector, thumbnail: thumbnail)
    }

    /// The foreground object under the image centre (else every foreground object),
    /// background blacked out, cropped to its extent. nil when Vision finds no subject.
    private static func subjectCrop(of image: CGImage) async throws -> CGImage? {
        let handler = ImageRequestHandler(image)
        guard let observation = try await handler.perform(GenerateForegroundInstanceMaskRequest()) else { return nil }

        var instances = observation.instanceAtPoint(NormalizedPoint(x: 0.5, y: 0.5))
        instances.remove(0) // index 0 is the background
        if instances.isEmpty { instances = observation.allInstances }
        guard !instances.isEmpty else { return nil }

        let buffer = try observation.generateMaskedImage(
            for: instances,
            imageFrom: handler,
            croppedToInstancesExtent: true
        )
        let masked = CIImage(cvPixelBuffer: buffer)
        let opaque = masked.composited(over: CIImage(color: .black).cropped(to: masked.extent))
        guard let result = CIContext().createCGImage(opaque, from: masked.extent),
              min(result.width, result.height) >= minSubjectSide
        else { return nil }
        return result
    }

    /// Fallback when no subject is found: the middle of the frame, where the reticle is.
    static func centerSquare(of image: CGImage) -> CGImage {
        let side = (CGFloat(min(image.width, image.height)) * fallbackCropFraction).rounded()
        let rect = CGRect(
            x: ((CGFloat(image.width) - side) / 2).rounded(),
            y: ((CGFloat(image.height) - side) / 2).rounded(),
            width: side,
            height: side
        )
        return image.cropping(to: rect) ?? image
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the Test command. Expected: `** TEST SUCCEEDED **`.

If the three embedding tests fail in the simulator with an error mentioning an inference context / Espresso / compute device, the simulator cannot use the default compute device. Pin both requests to CPU there — replace the two request constructions with:

```swift
var request = GenerateImageFeaturePrintRequest(.revision2)
#if targetEnvironment(simulator)
// The simulator has no Neural Engine; pin Vision to the CPU.
if let cpu = request.supportedComputeStageDevices[.main]?.first(where: { if case .cpu = $0 { true } else { false } }) {
    request.setComputeDevice(cpu, for: .main)
}
#endif
let observation = try await request.perform(on: crop)
```

and the same block for `var request = GenerateForegroundInstanceMaskRequest()` before `handler.perform(request)`. Rerun; expected `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add MyStuff/Services/ImageEmbedder.swift MyStuffTests/FakeEmbedder.swift MyStuffTests/VisionFeaturePrintEmbedderTests.swift
git commit -m "feat: Vision feature-print image embedder

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `RecognitionStore`

**Files:**
- Create: `MyStuff/Services/RecognitionStore.swift`
- Create: `MyStuff/Services/ItemPhotoLoader.swift`
- Test: `MyStuffTests/RecognitionStoreTests.swift`

**Interfaces:**
- Consumes: `ItemReference`, `ItemMatcher.distance` (Task 1); `ImageEmbedder`, `Embedding` (Task 2); `Item.hasItemPhoto`, `PhotoUploadManager.shared.localFullURL(itemId:filename:)` (existing).
- Produces, all `@MainActor`:
  - `final class RecognitionStore` (`@Observable`): `init(directory: URL, embedder: ImageEmbedder)`, `static func directory(forUid: String) -> URL`, `let embedder: ImageEmbedder`, `private(set) var references: [ItemReference]`, `private(set) var syncProgress: SyncProgress?`, `struct SyncProgress: Equatable { var done: Int; var total: Int }`
  - `func references(for itemId: String) -> [ItemReference]`
  - `func thumbnailURL(for reference: ItemReference) -> URL`
  - `@discardableResult func add(_ embedding: Embedding, to itemId: String, source: ItemReference.Source, sourceKey: String? = nil, now: Date = .now) -> ItemReference?`
  - `func remove(_ reference: ItemReference)`, `func removeAll(itemId: String)`, `func removeItemPhotoReference(itemId: String)`
  - `func enroll(imageData: Data, itemId: String) async -> Bool`
  - `func refreshItemPhoto(for item: Item, imageData: Data) async`
  - `func syncItemPhotos(for items: [Item], loadImageData: @MainActor (Item) async -> Data? = ItemPhotoLoader.data(for:)) async`
  - `static func sourceKey(for item: Item) -> String?`
  - `static let maxPerItem = 8`, `maxEnrolled = 5`, `learnedDedupeDistance: Float = 0.15`
  - `enum ItemPhotoLoader { @MainActor static func data(for item: Item) async -> Data? }`

- [ ] **Step 1: Write the failing tests**

Create `MyStuffTests/RecognitionStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import MyStuff

@MainActor
struct RecognitionStoreTests {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)

    private func makeStore(model: String = "fake-1") -> RecognitionStore {
        RecognitionStore(directory: directory, embedder: FakeEmbedder(modelID: model))
    }

    /// A unit vector along `axis` — any two are √2 apart, far beyond the dedupe distance.
    private func axis(_ axis: Int, of count: Int = 12) -> [Float] {
        (0..<count).map { $0 == axis ? 1 : 0 }
    }

    /// Counts loader calls from inside a `@MainActor` closure.
    @MainActor
    final class Counter {
        var value = 0
    }

    private func photoItem(_ id: String, remote: String? = nil) -> Item {
        Item(id: id, name: id, itemPhotoURL: "Photos/\(id)_item_photo.jpg", remoteItemPhotoURL: remote)
    }

    // MARK: - Persistence

    @Test func addedReferenceSurvivesReload() throws {
        let added = try #require(makeStore().add(.fake([1, 0]), to: "a", source: .enrolled))
        let reloaded = makeStore()
        #expect(reloaded.references == [added])
        #expect(reloaded.references.first?.vector == [1, 0])
    }

    @Test func thumbnailIsWrittenNextToTheRecord() throws {
        let store = makeStore()
        let added = try #require(store.add(.fake([1, 0]), to: "a", source: .enrolled))
        #expect(try Data(contentsOf: store.thumbnailURL(for: added)) == Embedding.fake([1, 0]).thumbnail)
    }

    @Test func corruptRecordIsSkippedOnLoad() throws {
        makeStore().add(.fake([1, 0]), to: "a", source: .enrolled)
        try Data("garbage".utf8).write(to: directory.appendingPathComponent("broken.plist"))
        #expect(makeStore().references.map(\.itemId) == ["a"])
    }

    @Test func directoriesAreScopedByUid() {
        let a = RecognitionStore.directory(forUid: "uid-a")
        let b = RecognitionStore.directory(forUid: "uid-b")
        #expect(a != b)
        #expect(a.lastPathComponent == "uid-a")
        #expect(a.deletingLastPathComponent().lastPathComponent == "Recognition")
    }

    // MARK: - Rules

    @Test func itemPhotoReferenceReplacesThePreviousOne() {
        let store = makeStore()
        store.add(.fake(axis(0)), to: "a", source: .itemPhoto, sourceKey: "old")
        store.add(.fake(axis(1)), to: "a", source: .itemPhoto, sourceKey: "new")
        #expect(store.references(for: "a").map(\.sourceKey) == ["new"])
    }

    @Test func enrolledIsCappedAtFive() {
        let store = makeStore()
        for index in 0..<5 {
            #expect(store.add(.fake(axis(index)), to: "a", source: .enrolled) != nil)
        }
        #expect(store.add(.fake(axis(5)), to: "a", source: .enrolled) == nil)
        #expect(store.references(for: "a").count == 5)
    }

    @Test func nearDuplicateLearnedReferenceIsDropped() {
        let store = makeStore()
        store.add(.fake([1, 0]), to: "a", source: .itemPhoto)
        #expect(store.add(.fake([1, 0.05]), to: "a", source: .learned) == nil)
        #expect(store.add(.fake([0, 1]), to: "a", source: .learned) != nil)
    }

    @Test func overflowEvictsTheOldestLearnedReferenceOnly() {
        let store = makeStore()
        let start = Date(timeIntervalSince1970: 1_000)
        store.add(.fake(axis(0)), to: "a", source: .itemPhoto, now: start)
        for index in 1...5 {
            store.add(.fake(axis(index)), to: "a", source: .enrolled, now: start.addingTimeInterval(Double(index)))
        }
        let oldest = store.add(.fake(axis(6)), to: "a", source: .learned, now: start.addingTimeInterval(6))
        store.add(.fake(axis(7)), to: "a", source: .learned, now: start.addingTimeInterval(7))
        #expect(store.references(for: "a").count == 8)

        store.add(.fake(axis(8)), to: "a", source: .learned, now: start.addingTimeInterval(8))

        let remaining = store.references(for: "a")
        #expect(remaining.count == 8)
        #expect(!remaining.contains { $0.id == oldest?.id })
        #expect(remaining.filter { $0.source == .enrolled }.count == 5)
        #expect(remaining.filter { $0.source == .itemPhoto }.count == 1)
    }

    @Test func removeAllDeletesRecordsAndThumbnails() throws {
        let store = makeStore()
        store.add(.fake(axis(0)), to: "a", source: .enrolled)
        store.add(.fake(axis(1)), to: "a", source: .learned)
        store.add(.fake(axis(2)), to: "b", source: .enrolled)

        store.removeAll(itemId: "a")

        #expect(store.references.map(\.itemId) == ["b"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2)
        #expect(makeStore().references.map(\.itemId) == ["b"])
    }

    @Test func enrollEmbedsAndStores() async {
        let store = makeStore()
        let saved = await store.enroll(imageData: .fakeImage([1, 0]), itemId: "a")
        let rejected = await store.enroll(imageData: Data("bad".utf8), itemId: "a")
        #expect(saved)
        #expect(rejected == false)
        #expect(store.references(for: "a").map(\.source) == [.enrolled])
    }

    // MARK: - Item photo sync

    @Test func syncCreatesAnItemPhotoReferencePerItemWithAPhoto() async {
        let store = makeStore()
        await store.syncItemPhotos(for: [photoItem("a"), Item(id: "b", name: "b")]) { _ in Data.fakeImage([1, 0]) }
        #expect(store.references.map(\.itemId) == ["a"])
        #expect(store.references.first?.source == .itemPhoto)
        #expect(store.references.first?.sourceKey == "Photos/a_item_photo.jpg")
        #expect(store.syncProgress == nil)
    }

    @Test func syncSkipsReferencesThatAreUpToDate() async {
        let store = makeStore()
        let loads = Counter()
        let loader: @MainActor (Item) async -> Data? = { _ in
            loads.value += 1
            return Data.fakeImage([1, 0])
        }
        await store.syncItemPhotos(for: [photoItem("a")], loadImageData: loader)
        await store.syncItemPhotos(for: [photoItem("a")], loadImageData: loader)
        #expect(loads.value == 1)
    }

    @Test func syncReembedsWhenThePhotoChanged() async {
        let store = makeStore()
        await store.syncItemPhotos(for: [photoItem("a")]) { _ in Data.fakeImage([1, 0]) }
        await store.syncItemPhotos(for: [photoItem("a", remote: "https://x/new.jpg")]) { _ in Data.fakeImage([0, 1]) }
        #expect(store.references(for: "a").map(\.vector) == [[0, 1]])
        #expect(store.references(for: "a").first?.sourceKey == "https://x/new.jpg")
    }

    @Test func syncDropsTheReferenceWhenThePhotoWasRemoved() async {
        let store = makeStore()
        await store.syncItemPhotos(for: [photoItem("a")]) { _ in Data.fakeImage([1, 0]) }
        store.add(.fake([0, 1]), to: "a", source: .learned)
        await store.syncItemPhotos(for: [Item(id: "a", name: "a")]) { _ in nil }
        #expect(store.references(for: "a").map(\.source) == [.learned])
    }

    @Test func syncLeavesItemsWhosePhotoCannotBeLoaded() async {
        let store = makeStore()
        await store.syncItemPhotos(for: [photoItem("a"), photoItem("b")]) { item in
            item.id == "a" ? nil : Data.fakeImage([1, 0])
        }
        #expect(store.references.map(\.itemId) == ["b"])
        #expect(store.syncProgress == nil)
    }

    @Test func syncReembedsReferencesFromAnotherModel() async {
        makeStore(model: "fake-1").add(.fake([1, 0]), to: "a", source: .learned)
        let upgraded = makeStore(model: "fake-2")
        await upgraded.syncItemPhotos(for: []) { _ in nil }
        #expect(upgraded.references.map(\.modelID) == ["fake-2"])
        #expect(makeStore(model: "fake-2").references.map(\.modelID) == ["fake-2"])
    }

    @Test func refreshItemPhotoReplacesOrClearsTheReference() async {
        let store = makeStore()
        await store.refreshItemPhoto(for: photoItem("a"), imageData: .fakeImage([1, 0]))
        #expect(store.references(for: "a").map(\.vector) == [[1, 0]])
        await store.refreshItemPhoto(for: photoItem("a"), imageData: Data("bad".utf8))
        #expect(store.references(for: "a").isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the Test command. Expected: build fails with `cannot find 'RecognitionStore' in scope`.

- [ ] **Step 3: Implement `ItemPhotoLoader`**

Create `MyStuff/Services/ItemPhotoLoader.swift`:

```swift
import Foundation

/// Encoded bytes of an item's **item** photo, resolved the way `PhotoView` does:
/// the local file first, else the remote copy (which is then kept locally).
enum ItemPhotoLoader {
    @MainActor
    static func data(for item: Item) async -> Data? {
        let local = PhotoUploadManager.shared.localFullURL(itemId: item.id, filename: "item_photo")
        if let data = try? Data(contentsOf: local) { return data }

        guard let remote = item.remoteItemPhotoURL.flatMap(URL.init(string:)),
              let (data, _) = try? await URLSession.shared.data(from: remote)
        else { return nil }
        try? data.write(to: local)
        return data
    }
}
```

- [ ] **Step 4: Implement `RecognitionStore`**

Create `MyStuff/Services/RecognitionStore.swift`:

```swift
import Foundation
import Observation

/// On-device library of recognition references, one directory per signed-in uid.
/// Each reference is a binary plist (`<id>.plist`) plus a thumbnail (`<id>.jpg`).
/// Nothing here syncs: a second device starts from item photos only.
@MainActor
@Observable
final class RecognitionStore {
    static let maxPerItem = 8
    static let maxEnrolled = 5
    /// A learned reference this close to an existing one teaches nothing new.
    static let learnedDedupeDistance: Float = 0.15

    struct SyncProgress: Equatable {
        var done: Int
        var total: Int
    }

    let embedder: ImageEmbedder
    private(set) var references: [ItemReference] = []
    /// Non-nil while `syncItemPhotos` is working.
    private(set) var syncProgress: SyncProgress?

    private let directory: URL
    private let fileManager = FileManager.default
    @ObservationIgnored private var isSyncing = false

    /// Loads every reference synchronously — a few hundred 3 KB files.
    init(directory: URL, embedder: ImageEmbedder) {
        self.directory = directory
        self.embedder = embedder
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        references = Self.load(from: directory)
    }

    /// `Application Support/Recognition/<uid>/`. Application Support is backed up,
    /// which matters: enrolled and learned references can't be rebuilt.
    static func directory(forUid uid: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recognition", isDirectory: true)
            .appendingPathComponent(uid.isEmpty ? "signed-out" : uid, isDirectory: true)
    }

    private static func load(from directory: URL) -> [ItemReference] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = PropertyListDecoder()
        return urls
            .filter { $0.pathExtension == "plist" }
            .compactMap { url in
                // Unreadable or corrupt records are skipped, not fatal.
                (try? Data(contentsOf: url)).flatMap { try? decoder.decode(ItemReference.self, from: $0) }
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Reading

    func references(for itemId: String) -> [ItemReference] {
        references.filter { $0.itemId == itemId }
    }

    func thumbnailURL(for reference: ItemReference) -> URL {
        directory.appendingPathComponent("\(reference.id).jpg")
    }

    private func recordURL(for reference: ItemReference) -> URL {
        directory.appendingPathComponent("\(reference.id).plist")
    }

    // MARK: - Writing

    /// Stores a reference, subject to the per-source rules. Returns nil when the
    /// reference was rejected (enrolled quota full, or a near-duplicate learned one).
    @discardableResult
    func add(
        _ embedding: Embedding,
        to itemId: String,
        source: ItemReference.Source,
        sourceKey: String? = nil,
        now: Date = .now
    ) -> ItemReference? {
        let comparable = references(for: itemId).filter { $0.modelID == embedder.modelID }
        switch source {
        case .itemPhoto:
            removeItemPhotoReference(itemId: itemId)
        case .enrolled:
            guard comparable.filter({ $0.source == .enrolled }).count < Self.maxEnrolled else { return nil }
        case .learned:
            let isDuplicate = comparable.contains {
                ItemMatcher.distance($0.vector, embedding.vector) < Self.learnedDedupeDistance
            }
            guard !isDuplicate else { return nil }
        }

        let reference = ItemReference(
            itemId: itemId,
            source: source,
            modelID: embedder.modelID,
            vector: embedding.vector,
            sourceKey: sourceKey,
            createdAt: now
        )
        references.append(reference)
        write(reference)
        try? embedding.thumbnail.write(to: thumbnailURL(for: reference), options: .atomic)
        evictOverflow(itemId: itemId)
        return reference
    }

    func remove(_ reference: ItemReference) {
        references.removeAll { $0.id == reference.id }
        try? fileManager.removeItem(at: recordURL(for: reference))
        try? fileManager.removeItem(at: thumbnailURL(for: reference))
    }

    func removeAll(itemId: String) {
        references(for: itemId).forEach(remove)
    }

    func removeItemPhotoReference(itemId: String) {
        references(for: itemId).filter { $0.source == .itemPhoto }.forEach(remove)
    }

    /// Embeds a photo taken through "Add angles". False when the photo is unreadable
    /// or the enrolled quota is full.
    func enroll(imageData: Data, itemId: String) async -> Bool {
        guard let embedding = try? await embedder.embed(imageData: imageData) else { return false }
        return add(embedding, to: itemId, source: .enrolled) != nil
    }

    /// Only learned references are evicted: the item photo and enrolled ones are
    /// deliberate, and together they can never exceed the cap.
    private func evictOverflow(itemId: String) {
        while references(for: itemId).count > Self.maxPerItem,
              let oldest = references(for: itemId)
                .filter({ $0.source == .learned })
                .min(by: { $0.createdAt < $1.createdAt }) {
            remove(oldest)
        }
    }

    private func write(_ reference: ItemReference) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(reference) else { return }
        try? data.write(to: recordURL(for: reference), options: .atomic)
    }

    // MARK: - Item photos

    /// What an `itemPhoto` reference was derived from. Changes when the photo is
    /// replaced on another device (new remote URL).
    static func sourceKey(for item: Item) -> String? {
        item.remoteItemPhotoURL ?? item.itemPhotoURL
    }

    /// Re-derives the item-photo reference right after the photo changed on this
    /// device. Needed because the local path stays the same when a photo is
    /// replaced, so `sourceKey` alone can't see it.
    func refreshItemPhoto(for item: Item, imageData: Data) async {
        guard let embedding = try? await embedder.embed(imageData: imageData) else {
            removeItemPhotoReference(itemId: item.id)
            return
        }
        add(embedding, to: item.id, source: .itemPhoto, sourceKey: Self.sourceKey(for: item))
    }

    /// Brings item-photo references in line with `items`, and re-embeds references
    /// left over from another model. Photos that can't be loaded right now
    /// (remote-only while offline) are skipped and retried on the next call.
    func syncItemPhotos(
        for items: [Item],
        loadImageData: @MainActor (Item) async -> Data? = ItemPhotoLoader.data(for:)
    ) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer {
            isSyncing = false
            syncProgress = nil
        }

        for item in items where !item.hasItemPhoto {
            removeItemPhotoReference(itemId: item.id)
        }

        let pending = items.filter { item in
            guard item.hasItemPhoto else { return false }
            let current = references.first {
                $0.itemId == item.id && $0.source == .itemPhoto && $0.modelID == embedder.modelID
            }
            return current?.sourceKey != Self.sourceKey(for: item)
        }
        let foreign = references.filter { $0.source != .itemPhoto && $0.modelID != embedder.modelID }
        guard !pending.isEmpty || !foreign.isEmpty else { return }

        syncProgress = SyncProgress(done: 0, total: pending.count + foreign.count)
        for item in pending {
            if let data = await loadImageData(item),
               let embedding = try? await embedder.embed(imageData: data) {
                add(embedding, to: item.id, source: .itemPhoto, sourceKey: Self.sourceKey(for: item))
            }
            syncProgress?.done += 1
        }
        for reference in foreign {
            await reembed(reference)
            syncProgress?.done += 1
        }
    }

    /// Moves a reference onto the current model using its stored thumbnail.
    /// A reference that can't be re-embedded is useless and is dropped.
    private func reembed(_ reference: ItemReference) async {
        guard let data = try? Data(contentsOf: thumbnailURL(for: reference)),
              let embedding = try? await embedder.embed(imageData: data),
              let index = references.firstIndex(where: { $0.id == reference.id })
        else {
            remove(reference)
            return
        }
        references[index].vector = embedding.vector
        references[index].modelID = embedder.modelID
        write(references[index])
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run the Test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add MyStuff/Services/RecognitionStore.swift MyStuff/Services/ItemPhotoLoader.swift MyStuffTests/RecognitionStoreTests.swift
git commit -m "feat: on-device recognition reference store

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `ScanSessionModel`

**Files:**
- Create: `MyStuff/ViewModels/ScanSessionModel.swift`
- Test: `MyStuffTests/ScanSessionModelTests.swift`

**Interfaces:**
- Consumes: `ImageEmbedder`, `Embedding`, `RecognitionStore.references`, `RecognitionStore.add`, `ItemMatcher.rank/classify`, `MatchOutcome`, `ItemMatch`, `AppLink.Target`, `ImageHelper.compress(_:)`.
- Produces, `@MainActor @Observable final class ScanSessionModel`:
  - `init(embedder: ImageEmbedder, store: RecognitionStore, destinationId: String? = nil, items: @escaping @MainActor () -> [Item], locations: @escaping @MainActor () -> [Location])`
  - `struct Capture: Identifiable` — `id: UUID`, `photo: Data?`, `embedding: Embedding?`, `candidates: [ItemMatch]`, `resolution: Resolution` (`.pending` / `.item(String)`), `origin: Origin` (`.camera` / `.code` / `.created`), `wasAutoAccepted: Bool`, `var itemId: String?`
  - `enum CodeResult: Equatable { case addedItem(String), alreadyInTray(String), setDestination(String), unknown }`
  - `var destinationId: String?`, `var pendingCaptureId: UUID?`, `private(set) var captures: [Capture]`, `private(set) var isProcessing: Bool`, `private(set) var lastError: String?`
  - `var trayItemIds: [String]`
  - `@discardableResult func capture(imageData: Data) async -> MatchOutcome?`
  - `func resolve(_ captureId: UUID, to itemId: String, origin: Capture.Origin? = nil)`
  - `func discard(_ captureId: UUID)`, `func closePending()`, `func removeFromTray(_ itemId: String)`
  - `func latestCaptureId(for itemId: String) -> UUID?`
  - `@discardableResult func handle(_ target: AppLink.Target) -> CodeResult`
  - `func saveLearnedReferences(selected: Set<String>)`

- [ ] **Step 1: Write the failing tests**

Create `MyStuffTests/ScanSessionModelTests.swift`:

```swift
import Foundation
import Testing
@testable import MyStuff

@MainActor
struct ScanSessionModelTests {
    /// Stand-in for `StuffViewModel`'s live lists.
    @MainActor
    final class World {
        var items: [Item] = []
        var locations: [Location] = []
    }

    let world: World
    let store: RecognitionStore
    let session: ScanSessionModel

    init() {
        let world = World()
        world.items = [Item(id: "a", name: "A"), Item(id: "b", name: "B")]
        world.locations = [Location(id: "shelf", name: "Shelf")]
        let embedder = FakeEmbedder()
        let store = RecognitionStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true),
            embedder: embedder
        )
        self.world = world
        self.store = store
        self.session = ScanSessionModel(
            embedder: embedder,
            store: store,
            items: { world.items },
            locations: { world.locations }
        )
    }

    // MARK: - Capture

    @Test func confidentCaptureIsAcceptedIntoTheTray() async {
        store.add(.fake([1, 0]), to: "a", source: .itemPhoto)
        store.add(.fake([0, 1]), to: "b", source: .itemPhoto)

        let outcome = await session.capture(imageData: .fakeImage([1, 0]))

        guard case .confident(let match, _) = outcome else {
            Issue.record("expected confident, got \(String(describing: outcome))")
            return
        }
        #expect(match.itemId == "a")
        #expect(session.trayItemIds == ["a"])
        #expect(session.pendingCaptureId == nil)
        #expect(session.captures.first?.wasAutoAccepted == true)
    }

    @Test func ambiguousCaptureWaitsForADecision() async {
        store.add(.fake([1, 0]), to: "a", source: .itemPhoto)
        store.add(.fake([1, 0.05]), to: "b", source: .itemPhoto)

        await session.capture(imageData: .fakeImage([1, 0]))

        #expect(session.trayItemIds.isEmpty)
        #expect(session.pendingCaptureId == session.captures.first?.id)
        #expect(session.captures.first?.candidates.map(\.itemId) == ["a", "b"])
    }

    @Test func firstUseWithAnEmptyLibraryStillAsksTheUser() async {
        let outcome = await session.capture(imageData: .fakeImage([1, 0]))

        #expect(outcome == .noMatch([]))
        #expect(session.captures.count == 1)
        #expect(session.pendingCaptureId == session.captures.first?.id)
        #expect(session.captures.first?.photo != nil)
    }

    @Test func unreadablePhotoReportsAnErrorAndAddsNothing() async {
        let outcome = await session.capture(imageData: Data("bad".utf8))

        #expect(outcome == nil)
        #expect(session.captures.isEmpty)
        #expect(session.lastError == "Couldn't read that photo")
        #expect(session.isProcessing == false)
    }

    // MARK: - Decisions

    @Test func resolvingAPendingCaptureAddsItToTheTray() async throws {
        await session.capture(imageData: .fakeImage([1, 0]))
        let id = try #require(session.pendingCaptureId)

        session.resolve(id, to: "b")

        #expect(session.trayItemIds == ["b"])
        #expect(session.pendingCaptureId == nil)
        #expect(session.captures.first?.wasAutoAccepted == false)
    }

    @Test func anAcceptedCaptureCanBeReassigned() async throws {
        store.add(.fake([1, 0]), to: "a", source: .itemPhoto)
        await session.capture(imageData: .fakeImage([1, 0]))
        let id = try #require(session.latestCaptureId(for: "a"))

        session.resolve(id, to: "b")

        #expect(session.trayItemIds == ["b"])
    }

    @Test func closingTheCardDropsAnUndecidedCapture() async {
        await session.capture(imageData: .fakeImage([1, 0]))

        session.closePending()

        #expect(session.captures.isEmpty)
        #expect(session.pendingCaptureId == nil)
    }

    @Test func closingTheCardKeepsADecidedCapture() async throws {
        store.add(.fake([1, 0]), to: "a", source: .itemPhoto)
        await session.capture(imageData: .fakeImage([1, 0]))
        session.pendingCaptureId = try #require(session.latestCaptureId(for: "a"))

        session.closePending()

        #expect(session.trayItemIds == ["a"])
        #expect(session.pendingCaptureId == nil)
    }

    @Test func discardRemovesTheCapture() async throws {
        await session.capture(imageData: .fakeImage([1, 0]))
        let id = try #require(session.pendingCaptureId)

        session.discard(id)

        #expect(session.captures.isEmpty)
        #expect(session.pendingCaptureId == nil)
    }

    @Test func sameItemCapturedTwiceIsOneTrayEntry() async throws {
        await session.capture(imageData: .fakeImage([1, 0]))
        session.resolve(try #require(session.pendingCaptureId), to: "a")
        await session.capture(imageData: .fakeImage([0, 1]))
        session.resolve(try #require(session.pendingCaptureId), to: "a")

        #expect(session.captures.count == 2)
        #expect(session.trayItemIds == ["a"])
    }

    @Test func removingFromTheTrayDropsEveryCaptureOfThatItem() async throws {
        await session.capture(imageData: .fakeImage([1, 0]))
        session.resolve(try #require(session.pendingCaptureId), to: "a")
        await session.capture(imageData: .fakeImage([0, 1]))
        session.resolve(try #require(session.pendingCaptureId), to: "a")
        session.handle(.item("b"))

        session.removeFromTray("a")

        #expect(session.trayItemIds == ["b"])
        #expect(session.captures.count == 1)
    }

    // MARK: - Codes

    @Test func itemCodeAddsTheItemOnce() {
        #expect(session.handle(.item("a")) == .addedItem("a"))
        #expect(session.handle(.item("a")) == .alreadyInTray("a"))
        #expect(session.trayItemIds == ["a"])
        #expect(session.captures.first?.origin == .code)
        #expect(session.captures.first?.embedding == nil)
    }

    @Test func locationCodeSetsTheDestination() {
        #expect(session.handle(.location("shelf")) == .setDestination("shelf"))
        #expect(session.destinationId == "shelf")
        #expect(session.trayItemIds.isEmpty)
    }

    @Test func codesForMissingEntitiesAreUnknown() {
        #expect(session.handle(.item("gone")) == .unknown)
        #expect(session.handle(.location("gone")) == .unknown)
        #expect(session.destinationId == nil)
        #expect(session.captures.isEmpty)
    }

    // MARK: - Live changes and learning

    @Test func itemDeletedMidSessionLeavesTheTray() {
        session.handle(.item("a"))
        session.handle(.item("b"))

        world.items.removeAll { $0.id == "a" }

        #expect(session.trayItemIds == ["b"])
    }

    @Test func learningCoversOnlySelectedExistingItemsWithAPhoto() async throws {
        world.items.append(Item(id: "c", name: "C"))
        await session.capture(imageData: .fakeImage([1, 0, 0]))
        session.resolve(try #require(session.pendingCaptureId), to: "a")
        await session.capture(imageData: .fakeImage([0, 1, 0]))
        session.resolve(try #require(session.pendingCaptureId), to: "b")
        await session.capture(imageData: .fakeImage([0, 0, 1]))
        session.resolve(try #require(session.pendingCaptureId), to: "c")
        session.handle(.item("b")) // already in tray; no extra capture
        world.items.removeAll { $0.id == "c" }

        session.saveLearnedReferences(selected: ["a", "c"])

        #expect(store.references.map(\.itemId) == ["a"])
        #expect(store.references.first?.source == .learned)
        #expect(store.references.first?.vector == [1, 0, 0])
    }

    @Test func codeScansTeachNothing() {
        session.handle(.item("a"))

        session.saveLearnedReferences(selected: ["a"])

        #expect(store.references.isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the Test command. Expected: build fails with `cannot find 'ScanSessionModel' in scope`.

- [ ] **Step 3: Implement `ScanSessionModel`**

Create `MyStuff/ViewModels/ScanSessionModel.swift`:

```swift
import Foundation
import Observation

/// State of one scan session: the destination, every capture, and what each
/// capture was resolved to. Holds no `StuffViewModel` — it reads items and
/// locations through closures and leaves Firestore writes to the views, so it
/// can be tested without Firebase.
@MainActor
@Observable
final class ScanSessionModel {

    /// One shutter tap or code scan.
    struct Capture: Identifiable {
        enum Resolution: Equatable {
            /// Waiting for the user to say which item this is.
            case pending
            case item(String)
        }

        enum Origin: Equatable {
            case camera
            /// Item QR / NFC — the fallback for near-identical items.
            case code
            /// The user created a new item from this capture.
            case created
        }

        let id = UUID()
        /// Compressed photo, kept so "New item" can use it as the item photo.
        var photo: Data?
        /// nil for code scans, which teach the matcher nothing.
        var embedding: Embedding?
        var candidates: [ItemMatch] = []
        var resolution: Resolution = .pending
        var origin: Origin = .camera
        var wasAutoAccepted = false

        var itemId: String? {
            if case .item(let id) = resolution { return id }
            return nil
        }
    }

    enum CodeResult: Equatable {
        case addedItem(String)
        case alreadyInTray(String)
        case setDestination(String)
        /// The code points at an item or location that no longer exists.
        case unknown
    }

    var destinationId: String?
    /// The capture whose match card is showing.
    var pendingCaptureId: UUID?
    private(set) var captures: [Capture] = []
    private(set) var isProcessing = false
    private(set) var lastError: String?

    private let embedder: ImageEmbedder
    private let store: RecognitionStore
    private let items: @MainActor () -> [Item]
    private let locations: @MainActor () -> [Location]

    init(
        embedder: ImageEmbedder,
        store: RecognitionStore,
        destinationId: String? = nil,
        items: @escaping @MainActor () -> [Item],
        locations: @escaping @MainActor () -> [Location]
    ) {
        self.embedder = embedder
        self.store = store
        self.destinationId = destinationId
        self.items = items
        self.locations = locations
    }

    /// Resolved item ids, unique, in first-seen order. Items deleted since they
    /// were captured (live sync) drop out.
    var trayItemIds: [String] {
        let known = Set(items().map(\.id))
        var seen: Set<String> = []
        return captures.compactMap(\.itemId).filter { known.contains($0) && seen.insert($0).inserted }
    }

    // MARK: - Capturing

    /// Embeds and matches one photo. A confident match goes straight into the
    /// tray; anything else becomes the pending capture. Returns nil when the
    /// photo couldn't be read, or when a capture is already in flight.
    @discardableResult
    func capture(imageData: Data) async -> MatchOutcome? {
        guard !isProcessing else { return nil }
        isProcessing = true
        defer { isProcessing = false }
        lastError = nil

        let photo = ImageHelper.compress(imageData) ?? imageData
        guard let embedding = try? await embedder.embed(imageData: photo) else {
            lastError = "Couldn't read that photo"
            return nil
        }

        let ranked = ItemMatcher.rank(
            embedding.vector,
            references: store.references,
            knownItemIds: Set(items().map(\.id)),
            modelID: embedder.modelID
        )
        let outcome = ItemMatcher.classify(ranked)

        var capture = Capture(photo: photo, embedding: embedding)
        switch outcome {
        case .confident(let best, let alternatives):
            capture.candidates = [best] + alternatives
            capture.resolution = .item(best.itemId)
            capture.wasAutoAccepted = true
        case .ambiguous(let candidates), .noMatch(let candidates):
            capture.candidates = candidates
        }
        captures.append(capture)
        if capture.itemId == nil { pendingCaptureId = capture.id }
        return outcome
    }

    // MARK: - Decisions

    func resolve(_ captureId: UUID, to itemId: String, origin: Capture.Origin? = nil) {
        guard let index = captures.firstIndex(where: { $0.id == captureId }) else { return }
        captures[index].resolution = .item(itemId)
        captures[index].wasAutoAccepted = false
        if let origin { captures[index].origin = origin }
        if pendingCaptureId == captureId { pendingCaptureId = nil }
    }

    func discard(_ captureId: UUID) {
        captures.removeAll { $0.id == captureId }
        if pendingCaptureId == captureId { pendingCaptureId = nil }
    }

    /// The match card was closed without a choice. An undecided capture is
    /// dropped; one that was already decided (reopened from the tray) stays.
    func closePending() {
        if let id = pendingCaptureId, captures.first(where: { $0.id == id })?.itemId == nil {
            captures.removeAll { $0.id == id }
        }
        pendingCaptureId = nil
    }

    func removeFromTray(_ itemId: String) {
        captures.removeAll { $0.itemId == itemId }
        if let id = pendingCaptureId, !captures.contains(where: { $0.id == id }) {
            pendingCaptureId = nil
        }
    }

    func latestCaptureId(for itemId: String) -> UUID? {
        captures.last { $0.itemId == itemId }?.id
    }

    // MARK: - Codes

    /// A QR or NFC code seen during the session: a location code sets the
    /// destination, an item code adds that item to the tray.
    @discardableResult
    func handle(_ target: AppLink.Target) -> CodeResult {
        switch target {
        case .location(let id):
            guard locations().contains(where: { $0.id == id }) else { return .unknown }
            destinationId = id
            return .setDestination(id)
        case .item(let id):
            guard items().contains(where: { $0.id == id }) else { return .unknown }
            guard !trayItemIds.contains(id) else { return .alreadyInTray(id) }
            captures.append(Capture(resolution: .item(id), origin: .code))
            return .addedItem(id)
        }
    }

    // MARK: - Learning

    /// Call after the move was confirmed: every photographed capture of a
    /// selected, still-existing item becomes a learned reference. Deselected and
    /// discarded captures teach nothing, so wrong matches never pollute the library.
    func saveLearnedReferences(selected: Set<String>) {
        let known = Set(items().map(\.id))
        for capture in captures {
            guard let embedding = capture.embedding,
                  let itemId = capture.itemId,
                  selected.contains(itemId),
                  known.contains(itemId)
            else { continue }
            store.add(embedding, to: itemId, source: .learned)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the Test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add MyStuff/ViewModels/ScanSessionModel.swift MyStuffTests/ScanSessionModelTests.swift
git commit -m "feat: scan session state model

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Wire the store into `StuffViewModel`; extract the move helper

**Files:**
- Modify: `MyStuff/ViewModels/StuffViewModel.swift` (properties near line 28–34; `deleteItem`; private `setPhoto(for:imageData:filename:)`; private `deletePhoto(for:filename:)`; `moveItems`)
- Modify: `MyStuff/Views/MoveItemsHereSheet.swift` (`confirmMove`)

**Interfaces:**
- Consumes: `RecognitionStore` (Task 3), `VisionFeaturePrintEmbedder` (Task 2).
- Produces on `StuffViewModel`:
  - `private(set) lazy var recognition: RecognitionStore`
  - `@discardableResult func moveItems(_ items: [Item], toLocationId: String?) async -> Bool`
  - `@discardableResult func moveItemsSharingDestination(_ items: [Item], to destination: Location) async -> Bool`

`StuffViewModel` hardcodes `FirebaseDataService`, so this task has no unit tests; it is verified by the build, the existing suite, and Task 10's walk-through.

- [ ] **Step 1: Add the store property**

In `StuffViewModel.swift`, directly below `private let storageService: StorageService = FirebaseStorageService()`:

```swift
    /// On-device recognition references for the signed-in user. Lazy: the uid is
    /// only known once `service` exists, and most launches never open the scanner.
    @ObservationIgnored
    private(set) lazy var recognition = RecognitionStore(
        directory: RecognitionStore.directory(forUid: service.currentUserId),
        embedder: VisionFeaturePrintEmbedder()
    )
```

- [ ] **Step 2: Hook item deletion**

In `deleteItem(_:)`, after the two `uploadManager.removeLocal` lines:

```swift
        recognition.removeAll(itemId: item.id)
```

- [ ] **Step 3: Hook item-photo changes**

In the private `setPhoto(for:imageData:filename:)`, replace the final line

```swift
        uploadManager.enqueueUpload(itemId: item.id, filename: filename, oldRemoteURL: oldRemote)
```

with

```swift
        uploadManager.enqueueUpload(itemId: item.id, filename: filename, oldRemoteURL: oldRemote)

        // Only the item photo feeds recognition; the location photo shows the place, not the thing.
        if filename == "item_photo" {
            await recognition.refreshItemPhoto(for: updated, imageData: pair.full)
        }
```

In the private `deletePhoto(for:filename:)`, after `uploadManager.removeLocal(itemId: item.id, filename: filename)`:

```swift
        if filename == "item_photo" {
            recognition.removeItemPhotoReference(itemId: item.id)
        }
```

- [ ] **Step 4: Make `moveItems` report success and add the sharing helper**

Replace the whole `moveItems` function with:

```swift
    /// Move several items to the same location in one pass. Unlike calling `moveItem`
    /// per item, this fires a single success haptic for the whole batch.
    /// Returns false when a write failed (`errorMessage` is set).
    @discardableResult
    func moveItems(_ items: [Item], toLocationId: String?) async -> Bool {
        guard !items.isEmpty else { return true }
        let ids = Set(items.map(\.id))
        do {
            for id in ids {
                guard var updated = self.items.first(where: { $0.id == id }) else { continue }
                updated.locationId = toLocationId
                updated.locationChangedAt = .now
                updated.updatedAt = .now
                try await service.updateItem(updated)
                if let index = self.items.firstIndex(where: { $0.id == id }) {
                    self.items[index] = updated
                }
            }
            HapticManager.success()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Bulk move that first shares `destination` with the moved items' collaborators
    /// (owner-managed only), so a shared item never lands somewhere its members can't see.
    @discardableResult
    func moveItemsSharingDestination(_ items: [Item], to destination: Location) async -> Bool {
        let dest = locations.first { $0.id == destination.id } ?? destination
        if canManageSharing(of: dest) {
            var missing: [String] = []
            for item in items where canManageSharing(of: item) {
                missing.append(contentsOf: membersMissing(from: dest, forItemMembers: sharedMembers(of: item)))
            }
            let union = Array(Set(missing))
            if !union.isEmpty {
                await addMembers(union, toLocation: dest)
            }
        }
        return await moveItems(items, toLocationId: dest.id)
    }
```

- [ ] **Step 5: Use the helper in `MoveItemsHereSheet`**

Replace the whole `confirmMove()` in `MyStuff/Views/MoveItemsHereSheet.swift` with:

```swift
    private func confirmMove() {
        let selectedItems = viewModel.items.filter { selected.contains($0.id) }
        Task {
            await viewModel.moveItemsSharingDestination(selectedItems, to: destination)
            dismiss()
        }
    }
```

- [ ] **Step 6: Build and run the suite**

Run the Build command. Expected: `** BUILD SUCCEEDED **`, no `error:` lines.
Run the Test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add MyStuff/ViewModels/StuffViewModel.swift MyStuff/Views/MoveItemsHereSheet.swift
git commit -m "feat: recognition store hooks, shared move helper

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Capture stage (viewfinder, shutter, library fallback)

**Files:**
- Modify: `MyStuff/Views/QRScannerView.swift` (struct `QRScannerView`, top of file)
- Create: `MyStuff/Views/Scan/ScanCaptureStage.swift`

**Interfaces:**
- Consumes: `QRScannerView` (existing).
- Produces:
  - `@MainActor final class ScanCameraController { weak var scanner: DataScannerViewController?; func capturePhoto() async -> Data? }`
  - `QRScannerView(controller: ScanCameraController? = nil, onScan: (String) -> Void)`
  - `struct ScanCaptureStage<Accessory: View>: View` — `init(isBusy: Bool, onCode: @escaping (String) -> Void = { _ in }, onPhoto: @escaping (Data) -> Void, @ViewBuilder accessory: @escaping () -> Accessory)`. `onPhoto` receives JPEG bytes.

- [ ] **Step 1: Let `QRScannerView` hand out stills**

In `MyStuff/Views/QRScannerView.swift`, change the top of `QRScannerView` from

```swift
/// VisionKit live QR scanner. Reports the first decoded barcode string via `onScan`.
struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
```

to

```swift
/// VisionKit live QR scanner. Reports the first decoded barcode string via `onScan`.
struct QRScannerView: UIViewControllerRepresentable {
    /// Set by screens that also need stills from the same camera (item scan).
    var controller: ScanCameraController? = nil
    let onScan: (String) -> Void
```

and in `makeUIViewController`, after `scanner.delegate = context.coordinator`:

```swift
        controller?.scanner = scanner
```

- [ ] **Step 2: Create the stage**

Create `MyStuff/Views/Scan/ScanCaptureStage.swift`:

```swift
import AVFoundation
import PhotosUI
import SwiftUI
import VisionKit

/// Handle on the live scanner so SwiftUI can ask it for a still.
@MainActor
final class ScanCameraController {
    weak var scanner: DataScannerViewController?

    /// A JPEG still from the running scanner; nil when no scanner is attached
    /// or the capture failed.
    func capturePhoto() async -> Data? {
        guard let scanner, let image = try? await scanner.capturePhoto() else { return nil }
        return image.jpegData(compressionQuality: 0.9)
    }
}

/// Camera viewfinder with a reticle and shutter, shared by the scan session and
/// "Add angles". Also reports QR payloads seen in frame. Where the live scanner
/// is unavailable (simulator, older hardware) it offers the photo library instead.
struct ScanCaptureStage<Accessory: View>: View {
    /// Disables the shutter while the caller is still working on the last photo.
    let isBusy: Bool
    var onCode: (String) -> Void = { _ in }
    /// Receives encoded image bytes for each shot.
    let onPhoto: (Data) -> Void
    /// Shown just above the shutter — status text, the tray.
    @ViewBuilder var accessory: () -> Accessory

    @State private var controller = ScanCameraController()
    @State private var authStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var isCapturing = false
    @State private var libraryPick: PhotosPickerItem?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !QRScannerView.isSupported {
                libraryFallback
            } else {
                switch authStatus {
                case .authorized:
                    camera
                case .notDetermined:
                    Color.clear.task { await requestAccess() }
                default:
                    cameraDenied
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .onChange(of: libraryPick) {
            guard let libraryPick else { return }
            Task {
                if let data = try? await libraryPick.loadTransferable(type: Data.self) {
                    onPhoto(data)
                }
                self.libraryPick = nil
            }
        }
    }

    private var camera: some View {
        QRScannerView(controller: controller, onScan: onCode)
            .ignoresSafeArea()
            .overlay { reticle }
            .overlay(alignment: .bottom) {
                VStack(spacing: 16) {
                    accessory()
                    shutter
                }
                .padding(.bottom, 24)
            }
    }

    /// Where to hold the item. Guidance only — the crop follows the detected subject.
    private var reticle: some View {
        RoundedRectangle(cornerRadius: 24)
            .strokeBorder(.white.opacity(0.8), lineWidth: 2)
            .aspectRatio(1, contentMode: .fit)
            .padding(48)
            .allowsHitTesting(false)
    }

    private var shutter: some View {
        Button {
            takePhoto()
        } label: {
            ZStack {
                Circle().fill(.white).frame(width: 66, height: 66)
                Circle().strokeBorder(.white, lineWidth: 3).frame(width: 78, height: 78)
            }
        }
        .disabled(isBusy || isCapturing)
        .opacity(isBusy || isCapturing ? 0.4 : 1)
        .accessibilityLabel("Capture item")
    }

    private var libraryFallback: some View {
        VStack(spacing: 20) {
            ContentUnavailableView(
                "Camera unavailable",
                systemImage: "camera",
                description: Text("Choose a photo of the item instead.")
            )
            .fixedSize(horizontal: false, vertical: true)
            accessory()
            PhotosPicker(selection: $libraryPick, matching: .images) {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)
        }
        .padding()
    }

    private var cameraDenied: some View {
        ContentUnavailableView {
            Label("Camera access needed", systemImage: "camera.fill")
        } description: {
            Text("Allow camera access in Settings to scan items.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func requestAccess() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        authStatus = granted ? .authorized : .denied
    }

    private func takePhoto() {
        isCapturing = true
        Task {
            if let data = await controller.capturePhoto() {
                onPhoto(data)
            }
            isCapturing = false
        }
    }
}
```

- [ ] **Step 3: Build**

Run the Build command. Expected: `** BUILD SUCCEEDED **`. (`QRScannerSheet`'s existing `QRScannerView { payload in … }` call still compiles: the trailing closure binds to `onScan`.)

- [ ] **Step 4: Commit**

```bash
git add MyStuff/Views/QRScannerView.swift MyStuff/Views/Scan/ScanCaptureStage.swift
git commit -m "feat: capture stage with shutter and library fallback

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Scan session screens

**Files:**
- Create: `MyStuff/Views/Scan/ScanMatchCard.swift`
- Create: `MyStuff/Views/Scan/ScanReviewSheet.swift`
- Create: `MyStuff/Views/Scan/ItemScanView.swift`

**Interfaces:**
- Consumes: `ScanSessionModel` (Task 4), `ScanCaptureStage` (Task 6), `StuffViewModel.recognition` / `moveItemsSharingDestination` (Task 5), existing `PhotoView`, `LocationSearchSheet`, `NFCScanButton`, `CoreNFCService.readingAvailable`, `AppLink.parse`, `HapticManager`, `StuffViewModel.addItem(id:name:notes:locationId:categoryId:)`, `setItemPhoto(for:imageData:)`, `displayPath(for:)`, `location(for:)`.
- Produces:
  - `struct ItemScanView: View` — `init(viewModel: StuffViewModel, destinationId: String? = nil)`
  - `struct ScanItemRow<Trailing: View>: View` — `init(item: Item, viewModel: StuffViewModel, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing)`
  - `struct ScanMatchCard: View`, `struct ScanReviewSheet: View`

- [ ] **Step 1: Create the match card**

Create `MyStuff/Views/Scan/ScanMatchCard.swift`:

```swift
import SwiftUI

/// Item row used across the scan screens: item photo, name, and where it is now.
struct ScanItemRow<Trailing: View>: View {
    let item: Item
    let viewModel: StuffViewModel
    /// Replaces the default "current location" caption.
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    private var place: String {
        viewModel.location(for: item).map { viewModel.displayPath(for: $0) } ?? "Unassigned"
    }

    var body: some View {
        HStack(spacing: 12) {
            PhotoView(item: item, kind: .item, size: .thumbnail(84)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "shippingbox.fill").foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 44)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).foregroundStyle(.primary)
                Text(subtitle ?? place)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing()
        }
        .contentShape(Rectangle())
    }
}

/// Asks which item a capture shows: the matcher's best guesses, any other item,
/// or a brand-new one. Also reached from the tray to reassign or remove an item.
struct ScanMatchCard: View {
    let capture: ScanSessionModel.Capture
    let viewModel: StuffViewModel
    let onPick: (String) -> Void
    /// Create a new item with this name from the captured photo.
    let onCreate: (String) -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showNamePrompt = false
    @State private var newName = ""

    private var candidates: [(match: ItemMatch, item: Item)] {
        capture.candidates.compactMap { match in
            viewModel.items.first { $0.id == match.itemId }.map { (match, $0) }
        }
    }

    private var title: String {
        if capture.itemId != nil { return "Change Item" }
        return candidates.isEmpty ? "Not Recognized" : "Which Item?"
    }

    var body: some View {
        NavigationStack {
            List {
                if let photo = capture.embedding?.thumbnail, let image = UIImage(data: photo) {
                    Section {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .listRowBackground(Color.clear)
                    }
                }

                if !candidates.isEmpty {
                    Section("Best guesses") {
                        ForEach(candidates, id: \.item.id) { candidate in
                            Button {
                                onPick(candidate.item.id)
                            } label: {
                                ScanItemRow(item: candidate.item, viewModel: viewModel) {
                                    #if DEBUG
                                    // Threshold tuning aid — see ItemMatcher's constants.
                                    Text(String(format: "%.2f", candidate.match.distance))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    #endif
                                    if capture.itemId == candidate.item.id {
                                        LocationPickerCheckmark()
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    NavigationLink {
                        ScanItemSearchList(viewModel: viewModel, onPick: onPick)
                    } label: {
                        Label("Other item…", systemImage: "magnifyingglass")
                    }
                    if capture.photo != nil {
                        Button {
                            newName = ""
                            showNamePrompt = true
                        } label: {
                            Label("New item", systemImage: "plus.circle")
                        }
                    }
                    Button(role: .destructive) {
                        onRemove()
                    } label: {
                        Label(capture.itemId == nil ? "Discard" : "Remove from scan", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("New item", isPresented: $showNamePrompt) {
                TextField("Name", text: $newName)
                Button("Create") {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { onCreate(name) }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The photo you just took becomes its item photo.")
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Every item, searchable — for when the right one isn't among the guesses.
private struct ScanItemSearchList: View {
    let viewModel: StuffViewModel
    let onPick: (String) -> Void
    @State private var searchText = ""

    private var results: [Item] {
        viewModel.items
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List(results) { item in
            Button {
                onPick(item.id)
            } label: {
                ScanItemRow(item: item, viewModel: viewModel) { EmptyView() }
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if results.isEmpty { ContentUnavailableView.search(text: searchText) }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search items")
        .navigationTitle("Choose Item")
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

- [ ] **Step 2: Create the review sheet**

Create `MyStuff/Views/Scan/ScanReviewSheet.swift`:

```swift
import SwiftUI

/// The one confirmation step of a scan session: every collected item with where
/// it is going. Nothing has been written before Confirm.
struct ScanReviewSheet: View {
    let session: ScanSessionModel
    let viewModel: StuffViewModel
    /// Called after a successful move so the presenter can close the whole session.
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    /// Tracks exclusions so every item starts selected.
    @State private var deselected: Set<String> = []
    @State private var showDestinationPicker = false
    @State private var isSaving = false
    @State private var moveFailed = false

    private var destination: Location? {
        viewModel.locations.first { $0.id == session.destinationId }
    }

    private var trayItems: [Item] {
        session.trayItemIds.compactMap { id in viewModel.items.first { $0.id == id } }
    }

    private var chosen: [Item] {
        trayItems.filter { !deselected.contains($0.id) }
    }

    /// Chosen items that aren't already directly in the destination.
    private var toMove: [Item] {
        guard let destination else { return [] }
        return chosen.filter { $0.locationId != destination.id }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Destination") {
                    Button {
                        showDestinationPicker = true
                    } label: {
                        HStack(spacing: 10) {
                            Text(destination?.emoji ?? "📍")
                            if let destination {
                                Text(viewModel.displayPath(for: destination))
                            } else {
                                Text("Choose location").foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .tint(.primary)
                }

                Section("Items") {
                    ForEach(trayItems) { item in
                        Button {
                            if !deselected.insert(item.id).inserted { deselected.remove(item.id) }
                        } label: {
                            ScanItemRow(item: item, viewModel: viewModel, subtitle: caption(for: item)) {
                                Image(systemName: deselected.contains(item.id) ? "circle" : "checkmark.circle.fill")
                                    .foregroundStyle(deselected.contains(item.id) ? Color.secondary : Color.accentColor)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(toMove.isEmpty ? "Done" : "Move (\(toMove.count))") { confirm() }
                        .disabled(destination == nil || chosen.isEmpty || isSaving)
                }
            }
            .sheet(isPresented: $showDestinationPicker) {
                LocationSearchSheet(
                    viewModel: viewModel,
                    title: "Destination",
                    selectedId: session.destinationId,
                    unassignedLabel: nil
                ) { session.destinationId = $0 }
            }
            .alert("Couldn't move items", isPresented: $moveFailed) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Nothing from this scan was lost. Try again.")
            }
        }
    }

    private func caption(for item: Item) -> String {
        let current = viewModel.location(for: item).map { viewModel.displayPath(for: $0) } ?? "Unassigned"
        guard let destination else { return current }
        if item.locationId == destination.id { return "Already here" }
        return "\(current) → \(destination.name)"
    }

    private func confirm() {
        guard let destination else { return }
        let chosenIds = Set(chosen.map(\.id))
        let moving = toMove
        isSaving = true
        Task {
            let moved = await viewModel.moveItemsSharingDestination(moving, to: destination)
            isSaving = false
            guard moved else {
                moveFailed = true
                return
            }
            // Items that were already here confirm the match just as well as moved ones.
            session.saveLearnedReferences(selected: chosenIds)
            if moving.isEmpty { HapticManager.success() }
            onFinished()
        }
    }
}
```

- [ ] **Step 3: Create the session screen**

Create `MyStuff/Views/Scan/ItemScanView.swift`:

```swift
import SwiftUI

/// Camera-driven bulk move: choose a destination, capture items one at a time,
/// then confirm a single review list. Item and location QR codes seen by the
/// camera count too. Nothing is written until the review sheet.
struct ItemScanView: View {
    let viewModel: StuffViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var session: ScanSessionModel
    @State private var showDestinationPicker = false
    @State private var showReview = false
    @State private var showDiscardConfirm = false
    /// Transient one-line message above the tray.
    @State private var banner: String?

    init(viewModel: StuffViewModel, destinationId: String? = nil) {
        self.viewModel = viewModel
        _session = State(initialValue: ScanSessionModel(
            embedder: viewModel.recognition.embedder,
            store: viewModel.recognition,
            destinationId: destinationId,
            items: { viewModel.items },
            locations: { viewModel.locations }
        ))
    }

    private var destination: Location? {
        viewModel.locations.first { $0.id == session.destinationId }
    }

    private var trayItems: [Item] {
        session.trayItemIds.compactMap { id in viewModel.items.first { $0.id == id } }
    }

    /// Drives the match card. Swiping the card away drops an undecided capture.
    private var pendingCapture: Binding<ScanSessionModel.Capture?> {
        Binding(
            get: { session.captures.first { $0.id == session.pendingCaptureId } },
            set: { if $0 == nil { session.closePending() } }
        )
    }

    var body: some View {
        NavigationStack {
            ScanCaptureStage(isBusy: session.isProcessing, onCode: handleCode, onPhoto: handlePhoto) {
                VStack(spacing: 10) {
                    statusLine
                    if !trayItems.isEmpty { tray }
                }
            }
            .safeAreaInset(edge: .top) { destinationBar }
            .navigationTitle("Scan Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if trayItems.isEmpty { dismiss() } else { showDiscardConfirm = true }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Review (\(trayItems.count))") { showReview = true }
                        .disabled(trayItems.isEmpty)
                }
            }
        }
        .task {
            await viewModel.recognition.syncItemPhotos(for: viewModel.items)
        }
        .sheet(isPresented: $showDestinationPicker) {
            LocationSearchSheet(
                viewModel: viewModel,
                title: "Destination",
                selectedId: session.destinationId,
                unassignedLabel: nil
            ) { session.destinationId = $0 }
        }
        .sheet(item: pendingCapture) { capture in
            ScanMatchCard(
                capture: capture,
                viewModel: viewModel,
                onPick: { session.resolve(capture.id, to: $0) },
                onCreate: { createItem(named: $0, from: capture) },
                onRemove: {
                    if let itemId = capture.itemId {
                        session.removeFromTray(itemId)
                    } else {
                        session.discard(capture.id)
                    }
                }
            )
        }
        .sheet(isPresented: $showReview) {
            ScanReviewSheet(session: session, viewModel: viewModel) { dismiss() }
        }
        .confirmationDialog("Discard this scan?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("Discard \(trayItems.count) item\(trayItems.count == 1 ? "" : "s")", role: .destructive) { dismiss() }
            Button("Keep Scanning", role: .cancel) { }
        }
    }

    // MARK: - Pieces

    private var destinationBar: some View {
        Button {
            showDestinationPicker = true
        } label: {
            HStack(spacing: 8) {
                Text(destination?.emoji ?? "📍")
                Text(destination.map { viewModel.displayPath(for: $0) } ?? "Choose location")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .tint(.primary)
        .padding(.top, 8)
    }

    private var statusText: String {
        if let banner { return banner }
        if let progress = viewModel.recognition.syncProgress {
            return "Preparing recognition \(progress.done)/\(progress.total)"
        }
        if session.isProcessing { return "Recognizing…" }
        return trayItems.isEmpty ? "Hold one item in the frame, then tap the shutter" : "Next item"
    }

    private var statusLine: some View {
        HStack(spacing: 10) {
            Text(statusText)
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
            if CoreNFCService.readingAvailable {
                NFCScanButton(accepts: .any) { target in
                    handleTarget(target)
                } label: { _ in
                    Image(systemName: "wave.3.right")
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .tint(.primary)
                .accessibilityLabel("Scan NFC tag")
            }
        }
        .padding(.horizontal)
    }

    private var tray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(trayItems) { item in
                    Button {
                        session.pendingCaptureId = session.latestCaptureId(for: item.id)
                    } label: {
                        HStack(spacing: 6) {
                            PhotoView(item: item, kind: .item, size: .thumbnail(84)) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Image(systemName: "shippingbox.fill").font(.caption)
                            }
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                            Text(item.name).font(.subheadline).lineLimit(1)
                        }
                        .padding(.leading, 6)
                        .padding(.trailing, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .tint(.primary)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Actions

    private func handlePhoto(_ data: Data) {
        Task {
            switch await session.capture(imageData: data) {
            case .confident(let match, let alternatives):
                HapticManager.success()
                showDistances(of: match, runnerUp: alternatives.first)
            case .ambiguous, .noMatch:
                HapticManager.light()
            case nil:
                if let error = session.lastError { show(error) }
            }
        }
    }

    /// Threshold tuning aid for DEBUG builds — see `ItemMatcher`'s constants.
    private func showDistances(of match: ItemMatch, runnerUp: ItemMatch?) {
        #if DEBUG
        let next = runnerUp.map { String(format: "%.2f", $0.distance) } ?? "–"
        show(String(format: "Matched at %.2f (next %@)", match.distance, next))
        #endif
    }

    private func handleCode(_ payload: String) {
        guard let url = URL(string: payload), let target = AppLink.parse(url) else {
            show("Not a MyStuff code")
            return
        }
        handleTarget(target)
    }

    private func handleTarget(_ target: AppLink.Target) {
        switch session.handle(target) {
        case .addedItem, .setDestination:
            HapticManager.success()
        case .alreadyInTray:
            show("Already scanned")
        case .unknown:
            show("That code points to something that no longer exists")
        }
    }

    /// Creates the item right away (not undone by cancelling the session) and
    /// uses the captured photo as its item photo.
    private func createItem(named name: String, from capture: ScanSessionModel.Capture) {
        Task {
            let id = UUID().uuidString
            await viewModel.addItem(id: id, name: name, notes: nil, locationId: session.destinationId, categoryId: nil)
            guard let item = viewModel.items.first(where: { $0.id == id }) else {
                show("Couldn't create the item")
                return
            }
            if let photo = capture.photo {
                await viewModel.setItemPhoto(for: item, imageData: photo)
            }
            session.resolve(capture.id, to: id, origin: .created)
        }
    }

    private func show(_ message: String) {
        banner = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if banner == message { banner = nil }
        }
    }
}
```

- [ ] **Step 4: Build**

Run the Build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add MyStuff/Views/Scan/ScanMatchCard.swift MyStuff/Views/Scan/ScanReviewSheet.swift MyStuff/Views/Scan/ItemScanView.swift
git commit -m "feat: item scan session screens

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Entry points and camera usage string

**Files:**
- Modify: `MyStuff/Views/LocationDetailView.swift` (state block near line 16; `actionsCard`; sheet chain near line 147)
- Modify: `MyStuff/Views/NFCTabView.swift` (state block; button stack near line 64; sheet chain near line 85)
- Modify: `MyStuff/Views/HomeView.swift` (state block; `.toolbar`; sheet chain near line 144)
- Modify: `MyStuff/Info.plist`

**Interfaces:**
- Consumes: `ItemScanView(viewModel:destinationId:)` (Task 7).
- Produces: nothing new.

- [ ] **Step 1: Location detail — "Scan items here"**

In `LocationDetailView.swift`, add below `@State private var showingMoveItemsHere = false`:

```swift
    @State private var showingItemScan = false
```

In `actionsCard`, after the "Move items here" `Button { … }` block (still inside `card { … }`):

```swift

            Divider().opacity(0.5)

            Button {
                showingItemScan = true
            } label: {
                Label("Scan items here", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
```

After the `.sheet(isPresented: $showingMoveItemsHere) { … }` modifier:

```swift
        .fullScreenCover(isPresented: $showingItemScan) {
            ItemScanView(viewModel: viewModel, destinationId: live.id)
        }
```

- [ ] **Step 2: NFC/QR tab — "Scan Items"**

In `NFCTabView.swift`, add below `@State private var showQRScanner = false`:

```swift
    @State private var showItemScan = false
```

After the `if QRScannerView.isSupported { … }` button block and before the final `Spacer()`:

```swift
                Button {
                    showItemScan = true
                } label: {
                    Label("Scan Items", systemImage: "camera.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(Color.appAccent)
                .controlSize(.large)
                .padding(.horizontal, 32)
```

After the `.sheet(isPresented: $showQRScanner) { … }` modifier:

```swift
            .fullScreenCover(isPresented: $showItemScan) {
                ItemScanView(viewModel: viewModel)
            }
```

- [ ] **Step 3: Home toolbar**

In `HomeView.swift`, add below `@State private var showFilters = false`:

```swift
    @State private var showItemScan = false
```

In `.toolbar { … }`, before the last `ToolbarItem(placement: .primaryAction)` (the list/gallery toggle):

```swift
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showItemScan = true
                    } label: {
                        Image(systemName: "camera.viewfinder")
                    }
                    .accessibilityLabel("Scan items")
                }
```

Directly before `.sheet(item: $selectedItem) { item in`:

```swift
            .fullScreenCover(isPresented: $showItemScan) {
                ItemScanView(viewModel: viewModel)
            }
```

- [ ] **Step 4: Camera usage string**

In `MyStuff/Info.plist`, change

```xml
	<string>Take photos of your items at their location</string>
```

to

```xml
	<string>Take photos of your items and scan them to recognize items and codes</string>
```

- [ ] **Step 5: Build**

Run the Build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add MyStuff/Views/LocationDetailView.swift MyStuff/Views/NFCTabView.swift MyStuff/Views/HomeView.swift MyStuff/Info.plist
git commit -m "feat: scan items entry points

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Enrollment in item detail

**Files:**
- Create: `MyStuff/Views/Scan/RecognitionPhotosSection.swift`
- Modify: `MyStuff/Views/ItemDetailSheet.swift` (the `VStack` in `body`, between the codes button and `privacySection`)

**Interfaces:**
- Consumes: `RecognitionStore.references(for:)`, `thumbnailURL(for:)`, `remove(_:)`, `enroll(imageData:itemId:)`, `maxEnrolled` (Task 3); `ScanCaptureStage` (Task 6); `StuffViewModel.recognition` (Task 5).
- Produces: `struct RecognitionPhotosSection: View` — `init(item: Item, viewModel: StuffViewModel)`.

- [ ] **Step 1: Create the section and the capture screen**

Create `MyStuff/Views/Scan/RecognitionPhotosSection.swift`:

```swift
import SwiftUI

/// Item-detail card listing the photos the scanner knows this item by, with a
/// way to add more angles by hand. References stay on this device.
struct RecognitionPhotosSection: View {
    let item: Item
    let viewModel: StuffViewModel

    @State private var showEnroll = false

    private var store: RecognitionStore { viewModel.recognition }
    private var references: [ItemReference] { store.references(for: item.id) }
    private var enrolledCount: Int { references.filter { $0.source == .enrolled }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recognition photos", systemImage: "camera.viewfinder")
                .font(.headline)

            if references.isEmpty {
                Text("None yet. Scanning learns this item as you confirm matches, or add a few angles now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(references) { reference in
                            thumbnail(reference)
                        }
                    }
                }
            }

            Button {
                showEnroll = true
            } label: {
                Label("Add angles", systemImage: "plus.viewfinder")
            }
            .disabled(enrolledCount >= RecognitionStore.maxEnrolled)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .fullScreenCover(isPresented: $showEnroll) {
            EnrollCaptureView(item: item, store: store)
        }
    }

    private func thumbnail(_ reference: ItemReference) -> some View {
        ReferenceThumbnail(url: store.thumbnailURL(for: reference))
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: icon(for: reference.source))
                    .font(.caption2)
                    .padding(3)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(3)
            }
            .contextMenu {
                // The item-photo reference follows the item photo; change that instead.
                if reference.source != .itemPhoto {
                    Button(role: .destructive) {
                        store.remove(reference)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .accessibilityLabel(label(for: reference.source))
    }

    private func icon(for source: ItemReference.Source) -> String {
        switch source {
        case .itemPhoto: return "photo"
        case .enrolled: return "camera"
        case .learned: return "sparkles"
        }
    }

    private func label(for source: ItemReference.Source) -> String {
        switch source {
        case .itemPhoto: return "From item photo"
        case .enrolled: return "Added angle"
        case .learned: return "Learned from a scan"
        }
    }
}

/// A reference thumbnail loaded from its file on disk.
private struct ReferenceThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .task(id: url) {
            image = UIImage(contentsOfFile: url.path)
        }
    }
}

/// Multi-shot capture for "Add angles": every shutter tap stores one enrolled reference.
private struct EnrollCaptureView: View {
    let item: Item
    let store: RecognitionStore

    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false
    @State private var lastFailed = false

    private var count: Int {
        store.references(for: item.id).filter { $0.source == .enrolled }.count
    }

    private var isFull: Bool { count >= RecognitionStore.maxEnrolled }

    private var status: String {
        if isFull { return "All \(RecognitionStore.maxEnrolled) angles saved" }
        if lastFailed { return "Couldn't read that photo — try again" }
        return "Turn the item between shots · \(count)/\(RecognitionStore.maxEnrolled)"
    }

    var body: some View {
        NavigationStack {
            ScanCaptureStage(isBusy: isWorking || isFull, onPhoto: add) {
                Text(status)
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func add(_ data: Data) {
        isWorking = true
        Task {
            let saved = await store.enroll(imageData: data, itemId: item.id)
            lastFailed = !saved
            isWorking = false
            if saved { HapticManager.success() }
        }
    }
}
```

- [ ] **Step 2: Show the section in item detail**

In `ItemDetailSheet.swift`, inside the `VStack(spacing: 20)` of `body`, change

```swift
                    .tint(.primary)
                    privacySection
```

to

```swift
                    .tint(.primary)
                    RecognitionPhotosSection(item: liveItem, viewModel: viewModel)
                    privacySection
```

- [ ] **Step 3: Build**

Run the Build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add MyStuff/Views/Scan/RecognitionPhotosSection.swift MyStuff/Views/ItemDetailSheet.swift
git commit -m "feat: recognition photos + add angles in item detail

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Docs and final verification

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: everything above.
- Produces: nothing.

- [ ] **Step 1: Update `CLAUDE.md`**

Replace the line `- No test target exists yet.` with:

```markdown
- Unit tests: `MyStuffTests` (Swift Testing, hosted in the app). Run with
  `xcodebuild test -project MyStuff.xcodeproj -scheme MyStuff -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -only-testing:MyStuffTests`.
  `StuffViewModel` hardcodes Firebase and is not unit-tested; put testable logic in types that don't need it.
```

At the end of the `## Architecture` section, add:

```markdown
**Item recognition:** `ItemScanView` runs a scan session (`ScanSessionModel`): capture → `ImageEmbedder` (Vision feature print over the foreground subject) → `ItemMatcher` nearest-neighbour over `RecognitionStore` references → review sheet → `moveItemsSharingDestination`. References (item photo / enrolled / learned) are on-device only, under `Application Support/Recognition/<uid>/` — nothing recognition-related is in Firestore. Thresholds in `ItemMatcher` are estimates; DEBUG builds show distances on the match card.
```

- [ ] **Step 2: Full build and test run**

Run the Build command. Expected: `** BUILD SUCCEEDED **`, no `error:` lines.
Run the Test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Simulator walk-through (photo-library fallback)**

Boot the iOS 27.0 "iPhone 17" simulator, install and launch the Debug build. The simulator has no camera, so the capture stage shows "Choose Photo". Requires a simulator that is already signed in — if the sign-in screen appears, stop here and report that the walk-through is handed to the user.

Check, in order:
1. Home toolbar shows the `camera.viewfinder` button; it opens "Scan Items" with "Choose location" at the top.
2. Tapping the destination bar opens the location picker; choosing one shows its path in the bar.
3. "Choose Photo" with a photo of an item that has an item photo: either it lands in the tray, or the match card opens with guesses (and distances, DEBUG).
4. From the card: pick a guess → tray chip appears. "Other item…" → searchable list → pick → chip. "New item" → name → chip, and the item exists afterwards with the photo.
5. Tapping a tray chip reopens the card titled "Change Item"; "Remove from scan" removes the chip.
6. "Review (n)": rows show `from → to`, an item already in the destination shows "Already here", toggling a row changes the Move count. Confirm closes the session; the items are in the destination.
7. Item detail of a confirmed item shows "Recognition photos" with a `sparkles` thumbnail; "Add angles" opens the capture screen with an `n/5` counter.
8. Location detail shows "Scan items here" and opens the session with that location preset.
9. Cancel with a non-empty tray asks "Discard this scan?".

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: item recognition architecture + test command

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Hand off the device-only checks**

Report to the user, as not yet verified (needs a physical iPhone):
- live camera capture and subject cropping on real shelves;
- item QR / location QR recognized inside the session viewfinder;
- NFC button in the session (location tag → destination, item tag → tray);
- threshold tuning: note the DEBUG distances for right and wrong matches and adjust `ItemMatcher.acceptDistance`, `acceptMargin`, `rejectDistance`.
