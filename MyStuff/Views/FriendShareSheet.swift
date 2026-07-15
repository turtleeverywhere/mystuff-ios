import SwiftUI

/// Toggle which friends an item or location is shared with. Owner-only (caller gates).
struct FriendShareSheet: View {
    let title: String
    let friends: [Friend]
    let sharedWith: Set<String>
    let onToggle: (String, Bool) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var shared: Set<String>
    @State private var busy = false

    init(title: String, friends: [Friend], sharedWith: Set<String>, onToggle: @escaping (String, Bool) async -> Void) {
        self.title = title
        self.friends = friends
        self.sharedWith = sharedWith
        self.onToggle = onToggle
        _shared = State(initialValue: sharedWith)
    }

    var body: some View {
        NavigationStack {
            List {
                if friends.isEmpty {
                    ContentUnavailableView {
                        Label("No Friends Yet", systemImage: "person.2")
                    } description: {
                        Text("Add friends from your account menu to share with them.")
                    }
                } else {
                    Section(title) {
                        ForEach(friends) { friend in
                            Button {
                                let willShare = !shared.contains(friend.uid)
                                if willShare { shared.insert(friend.uid) } else { shared.remove(friend.uid) }
                                busy = true
                                Task {
                                    await onToggle(friend.uid, willShare)
                                    busy = false
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(friend.displayName).foregroundStyle(.primary)
                                        Text(friend.email).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if shared.contains(friend.uid) {
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
