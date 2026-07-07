import SwiftUI

struct ContentView: View {
    @Bindable var authService: AuthService
    @State private var viewModel = StuffViewModel()
    @State private var selectedTab = 0
    @State private var showingProfile = false
    @State private var pendingNFCItemId: String?
    @State private var deepLinkedItem: Item?

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: 0) {
                HomeView(viewModel: viewModel, onProfileTap: { showingProfile = true })
            }

            Tab("Items", systemImage: "shippingbox.fill", value: 1) {
                ItemsView(viewModel: viewModel)
            }

            Tab("Locations", systemImage: "mappin.circle.fill", value: 2) {
                LocationsView(viewModel: viewModel)
            }

            if CoreNFCService.readingAvailable {
                Tab("NFC", systemImage: "wave.3.right.circle.fill", value: 3) {
                    NFCTabView(viewModel: viewModel)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .background(LinearGradient.appBackground.ignoresSafeArea())
        .task {
            await viewModel.loadData()
        }
        .sheet(isPresented: $showingProfile) {
            ProfileSheet(authService: authService)
                .presentationDetents([.medium])
        }
        .sheet(item: $deepLinkedItem) { item in
            NFCUpdateSheet(item: item, viewModel: viewModel)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { handleDeepLink(url) }
        }
        .onOpenURL { url in handleDeepLink(url) }
        .onChange(of: viewModel.items) { resolvePendingDeepLink() }
        .onChange(of: pendingNFCItemId) { resolvePendingDeepLink() }
    }

    private func handleDeepLink(_ url: URL) {
        guard let id = NFCLink.itemId(from: url) else { return }
        pendingNFCItemId = id
    }

    private func resolvePendingDeepLink() {
        guard let id = pendingNFCItemId else { return }
        if let item = viewModel.items.first(where: { $0.id == id }) {
            pendingNFCItemId = nil
            deepLinkedItem = item
            HapticManager.success()
        }
    }
}

// MARK: - Profile / Sign Out Sheet

struct ProfileSheet: View {
    @Bindable var authService: AuthService
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
