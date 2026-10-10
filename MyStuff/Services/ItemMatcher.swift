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
