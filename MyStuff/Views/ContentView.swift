import SwiftUI

struct ContentView: View {
    @Bindable var authService: AuthService
    @State private var viewModel = StuffViewModel()
    @State private var selectedTab = 0
    @State private var showingProfile = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: 0) {
                HomeView(viewModel: viewModel)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            profileButton
                        }
                    }
            }

            Tab("Items", systemImage: "shippingbox.fill", value: 1) {
                ItemsView(viewModel: viewModel)
            }

            Tab("Locations", systemImage: "mappin.circle.fill", value: 2) {
                LocationsView(viewModel: viewModel)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .task {
            await viewModel.loadData()
        }
        .sheet(isPresented: $showingProfile) {
            ProfileSheet(authService: authService)
                .presentationDetents([.medium])
        }
    }

    private var profileButton: some View {
        Button {
            showingProfile = true
        } label: {
            Image(systemName: "person.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
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
