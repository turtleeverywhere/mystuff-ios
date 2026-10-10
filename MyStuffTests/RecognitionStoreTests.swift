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
