import SwiftUI

/// Share a location with friends, scoping which sublocations are included.
/// Owner-only (the caller gates presentation). Coalesces notifications via the view model.
struct LocationShareSheet: View {
    let location: Location
    let viewModel: StuffViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var scopeMode: ScopeMode = .locationOnly
    @State private var selected: Set<String> = []
    @State private var busy = false

    enum ScopeMode: Hashable { case locationOnly, all, choose }

    private var descendants: [(location: Location, depth: Int)] {
        viewModel.flattenedDescendantLocations(of: location)
    }

    private var hasSublocations: Bool { !descendants.isEmpty }

    private var sharedUids: Set<String> {
        let live = viewModel.locations.first { $0.id == location.id } ?? location
        return Set(viewModel.sharedMembers(of: live))
    }

    private var scope: StuffViewModel.SublocationScope {
        switch scopeMode {
        case .locationOnly: return .locationOnly
        case .all: return .all
        case .choose: return .selected(selected)
        }
    }

    /// What the current scope would still add for people this is already shared with.
    private var pending: (sublocations: Int, items: Int) {
        viewModel.pendingShareAdditions(of: location, scope: scope)
    }

    private var pendingSummary: String {
        let p = pending
        var parts: [String] = []
        if p.sublocations > 0 { parts.append("\(p.sublocations) sublocation\(p.sublocations == 1 ? "" : "s")") }
        if p.items > 0 { parts.append("\(p.items) item\(p.items == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        NavigationStack {
            List {
                if hasSublocations {
                    Section("Sublocations") {
                        Picker("Include", selection: $scopeMode) {
                            Text("This location only").tag(ScopeMode.locationOnly)
                            Text("All sublocations").tag(ScopeMode.all)
                            Text("Choose…").tag(ScopeMode.choose)
                        }
                        if scopeMode == .choose {
                            ForEach(descendants, id: \.location.id) { entry in
                                Button {
                                    if selected.contains(entry.location.id) {
                                        selected.remove(entry.location.id)
                                    } else {
                                        selected.insert(entry.location.id)
                                    }
                                } label: {
                                    HStack {
                                        Text(entry.location.name)
                                            .foregroundStyle(.primary)
                                            .padding(.leading, CGFloat(entry.depth) * 16)
                                        Spacer()
                                        Image(systemName: selected.contains(entry.location.id) ? "checkmark.square.fill" : "square")
                                            .foregroundStyle(selected.contains(entry.location.id) ? .green : .secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // The friend toggle only applies a scope when switching sharing ON, so
                        // widening the scope afterwards would otherwise do nothing at all.
                        if !sharedUids.isEmpty {
                            if pending.sublocations > 0 || pending.items > 0 {
                                Button {
                                    busy = true
                                    Task {
                                        await viewModel.extendShare(of: location, scope: scope)
                                        busy = false
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Apply to people it's already shared with")
                                            .foregroundStyle(.primary)
                                        Text("Adds \(pendingSummary)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .disabled(busy)
                            } else {
                                Text("Everyone it's shared with already has these sublocations.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if viewModel.friends.isEmpty {
                    ContentUnavailableView {
                        Label("No Friends Yet", systemImage: "person.2")
                    } description: {
                        Text("Add friends from your account menu to share with them.")
                    }
                } else {
                    Section("Share \"\(location.name)\" with") {
                        ForEach(viewModel.friends) { friend in
                            Button {
                                let isShared = sharedUids.contains(friend.uid)
                                busy = true
                                Task {
                                    if isShared {
                                        await viewModel.unshareLocationTree(location, fromFriend: friend.uid)
                                    } else {
                                        await viewModel.shareLocationTree(location, withFriend: friend.uid, scope: scope)
                                    }
                                    busy = false
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(friend.displayName).foregroundStyle(.primary)
                                        Text(friend.email).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if sharedUids.contains(friend.uid) {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    } else {
                                        Image(systemName: "circle").foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(busy)
                        }
                    }
                }
            }
            .onAppear {
                // Reflect reality on reopen: if the whole subtree is already shared with
                // everyone, don't show "This location only" as if nothing were included.
                guard hasSublocations, !sharedUids.isEmpty else { return }
                let covered = descendants.allSatisfy { sharedUids.isSubset(of: Set($0.location.members)) }
                if covered { scopeMode = .all }
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
