import SwiftUI

/// The "are you sure?" step for the two irreversible deletes. Shared so every
/// entry point — swipe, long-press, detail screen — asks the same question.
extension View {
    /// Asks before deleting the bound item, then deletes it. `onDeleted` runs once
    /// the delete is under way; detail screens use it to close themselves.
    func confirmItemDeletion(
        _ item: Binding<Item?>,
        viewModel: StuffViewModel,
        onDeleted: @escaping () -> Void = {}
    ) -> some View {
        alert(
            "Delete Item?",
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            ),
            presenting: item.wrappedValue
        ) { target in
            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteItem(target) }
                onDeleted()
            }
            Button("Cancel", role: .cancel) { }
        } message: { target in
            Text("\"\(target.name)\" and its photos will be deleted. This can't be undone.")
        }
    }

    /// Asks before deleting the bound location, then deletes it. `onDeleted` runs
    /// once the delete is under way; the location's own screen uses it to close.
    func confirmLocationDeletion(
        _ location: Binding<Location?>,
        viewModel: StuffViewModel,
        onDeleted: @escaping () -> Void = {}
    ) -> some View {
        alert(
            "Delete Location?",
            isPresented: Binding(
                get: { location.wrappedValue != nil },
                set: { if !$0 { location.wrappedValue = nil } }
            ),
            presenting: location.wrappedValue
        ) { target in
            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteLocation(target) }
                onDeleted()
            }
            Button("Cancel", role: .cancel) { }
        } message: { target in
            if viewModel.childLocations(for: target).isEmpty {
                Text("Items at this location will be unassigned.")
            } else {
                Text("Sub-locations will be moved up one level. Items at this location will be unassigned.")
            }
        }
    }
}
