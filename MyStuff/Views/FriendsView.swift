import SwiftUI

struct FriendsView: View {
    @Bindable var social: SocialViewModel
    @State private var showAdd = false

    var body: some View {
        List {
            if !social.incomingRequests.isEmpty {
                Section("Requests") {
                    ForEach(social.incomingRequests) { request in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(request.fromName).font(.subheadline)
                                Text(request.fromEmail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                Task { await social.respond(to: request, accept: true) }
                            } label: {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                            .buttonStyle(.plain)
                            Button {
                                Task { await social.respond(to: request, accept: false) }
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if !social.outgoingRequests.isEmpty {
                Section("Pending") {
                    ForEach(social.outgoingRequests) { request in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(request.toName).font(.subheadline)
                            Text("Waiting for response").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Friends") {
                if social.friends.isEmpty {
                    Text("No friends yet")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(social.friends) { friend in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(friend.displayName).font(.subheadline)
                            Text(friend.email).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { indexSet in
                        let toRemove = indexSet.map { social.friends[$0] }
                        Task { for friend in toRemove { await social.removeFriend(friend) } }
                    }
                }
            }
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: {
                    Image(systemName: "person.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddFriendSheet(social: social)
                .presentationDetents([.height(220)])
        }
        .task { await social.load() }
    }
}

private struct AddFriendSheet: View {
    @Bindable var social: SocialViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("friend@email.com", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                }
                if let error = social.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .navigationTitle("Add Friend")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { social.errorMessage = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        sending = true
                        Task {
                            let ok = await social.addFriend(email: email)
                            sending = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(email.isEmpty || sending)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        FriendsView(social: SocialViewModel())
    }
}
