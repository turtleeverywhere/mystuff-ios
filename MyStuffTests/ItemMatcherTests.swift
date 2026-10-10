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
