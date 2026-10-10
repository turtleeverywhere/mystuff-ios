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
        let reopened = try #require(session.latestCaptureId(for: "a"))
        session.pendingCaptureId = reopened

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
