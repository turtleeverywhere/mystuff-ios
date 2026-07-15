import SwiftUI

struct ContentView: View {
    @Bindable var authService: AuthService
    @State private var viewModel = StuffViewModel()
    @State private var social = SocialViewModel()
    @State private var selectedTab = 0
    @State private var showingProfile = false
    @State private var pendingNFCItemId: String?
    @State private var deepLinkedItem: Item?
    @State private var pendingLocationId: String?
    @State private var deepLinkedLocation: Location?

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: 0) {
                HomeView(viewModel: viewModel, onProfileTap: { showingProfile = true }, pendingRequestCount: social.incomingPendingCount)
            }

            Tab("Items", systemImage: "shippingbox.fill", value: 1) {
                ItemsView(viewModel: viewModel)
            }

            Tab("Locations", systemImage: "mappin.circle.fill", value: 2) {
                LocationsView(viewModel: viewModel)
            }

            if CoreNFCService.readingAvailable {
                Tab("NFC/QR", systemImage: "wave.3.right.circle.fill", value: 3) {
                    NFCTabView(viewModel: viewModel)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .background(LinearGradient.appBackground.ignoresSafeArea())
        .task {
            await viewModel.loadData()
        }
        .task {
            PushNotificationManager.shared.requestAuthorization()
            PushNotificationManager.shared.saveTokenIfPossible()
        }
        .task {
            social.onUnfriend = { friendUid in
                await viewModel.unshareEverything(withFriend: friendUid)
            }
            await social.load()
            viewModel.friends = social.friends
        }
        .onChange(of: social.friends) {
            viewModel.friends = social.friends
        }
        .sheet(isPresented: $showingProfile) {
            ProfileSheet(authService: authService, social: social)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $deepLinkedItem) { item in
            NFCUpdateSheet(item: item, viewModel: viewModel)
        }
        .sheet(item: $deepLinkedLocation) { location in
            NavigationStack {
                LocationDetailView(location: location, viewModel: viewModel)
            }
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { handleDeepLink(url) }
        }
        .onOpenURL { url in handleDeepLink(url) }
        .onChange(of: viewModel.items) { resolvePendingDeepLink() }
        .onChange(of: viewModel.locations) { resolvePendingDeepLink() }
        .onChange(of: pendingNFCItemId) { resolvePendingDeepLink() }
        .onChange(of: pendingLocationId) { resolvePendingDeepLink() }
    }

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
}

// MARK: - Profile / Sign Out Sheet

struct ProfileSheet: View {
    @Bindable var authService: AuthService
    @Bindable var social: SocialViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(authService.currentUser?.displayName ?? "User")
                                .font(.headline)
                            Text(authService.currentUser?.email ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    NavigationLink {
                        FriendsView(social: social)
                    } label: {
                        HStack {
                            Label("Friends", systemImage: "person.2.fill")
                            Spacer()
                            if social.incomingPendingCount > 0 {
                                Text("\(social.incomingPendingCount)")
                                    .font(.caption2).bold()
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.red, in: Capsule())
                            }
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        authService.signOut()
                        dismiss()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ContentView(authService: AuthService())
}
