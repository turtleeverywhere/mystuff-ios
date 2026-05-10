# Item Categories Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add managed categories to items with a Home tab grouping toggle (location vs category).

**Architecture:** New `Category` model + DataService CRUD, `categoryId` on Item, `GroupingMode` enum on ViewModel, segmented control in HomeView, category picker in ItemFormSheet, CategoryManagementView accessible from Items tab toolbar.

**Tech Stack:** Swift 6.0, SwiftUI, Firebase Firestore, iOS 26

**Note:** No test target exists. Each task ends with an Xcode build verification instead of automated tests.

---

### Task 1: Category Model

**Files:**
- Create: `MyStuff/Models/Category.swift`

- [ ] **Step 1: Create Category.swift**

```swift
import Foundation

struct Category: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 2: Add categoryId to Item**

Modify `MyStuff/Models/Item.swift`. Add `var categoryId: String?` after `locationId`, and add `categoryId: String? = nil` parameter to init between `locationId` and `createdAt`.

Updated file:

```swift
import Foundation

struct Item: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var notes: String?
    var locationId: String?
    var categoryId: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        notes: String? = nil,
        locationId: String? = nil,
        categoryId: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.locationId = locationId
        self.categoryId = categoryId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

- [ ] **Step 3: Build in Xcode to verify**

Build the project. Expect success (categoryId is optional so all existing call sites still compile).

- [ ] **Step 4: Commit**

```bash
git add MyStuff/Models/Category.swift MyStuff/Models/Item.swift
git commit -m "Add Category model and categoryId to Item"
```

---

### Task 2: DataService Protocol + Implementations

**Files:**
- Modify: `MyStuff/Services/DataService.swift`
- Modify: `MyStuff/Services/FirebaseDataService.swift`
- Modify: `MyStuff/Services/MockDataService.swift`

- [ ] **Step 1: Add category methods to DataService protocol**

Add after the Locations section in `MyStuff/Services/DataService.swift`:

```swift
    // MARK: - Categories

    func fetchCategories() async throws -> [Category]
    func addCategory(_ category: Category) async throws
    func updateCategory(_ category: Category) async throws
    func deleteCategory(_ category: Category) async throws
```

- [ ] **Step 2: Add Firestore implementation**

Add to `MyStuff/Services/FirebaseDataService.swift`:

Add computed property after `locationsCollection`:

```swift
    private var categoriesCollection: CollectionReference { userDoc.collection("categories") }
```

Add methods at the end of the class before the closing brace:

```swift
    // MARK: - Categories

    func fetchCategories() async throws -> [Category] {
        let snapshot = try await categoriesCollection.order(by: "createdAt", descending: true).getDocuments()
        return try snapshot.documents.map { try $0.data(as: Category.self) }
    }

    func addCategory(_ category: Category) async throws {
        try categoriesCollection.document(category.id).setData(from: category)
    }

    func updateCategory(_ category: Category) async throws {
        try categoriesCollection.document(category.id).setData(from: category, merge: true)
    }

    func deleteCategory(_ category: Category) async throws {
        try await categoriesCollection.document(category.id).delete()
    }
```

- [ ] **Step 3: Add Mock implementation**

In `MyStuff/Services/MockDataService.swift`:

Add `private var categories: [Category]` property alongside existing `items` and `locations`.

In `init()`, add sample categories before the items array and assign categoryIds to some items:

```swift
        let electronics = Category(id: "cat-1", name: "Electronics")
        let tools = Category(id: "cat-2", name: "Tools")
        let documents = Category(id: "cat-3", name: "Documents")
        let seasonal = Category(id: "cat-4", name: "Seasonal")

        self.categories = [electronics, tools, documents, seasonal]
```

Update item initializers to include categoryId:

```swift
        self.items = [
            Item(id: "item-1", name: "TV Remote", notes: "Samsung remote, silver", locationId: "loc-1", categoryId: "cat-1"),
            Item(id: "item-2", name: "Drill", notes: "Bosch cordless", locationId: "loc-2", categoryId: "cat-2"),
            Item(id: "item-3", name: "Passport", notes: "Expires 2028", locationId: "loc-3", categoryId: "cat-3"),
            Item(id: "item-4", name: "Christmas Decorations", notes: "3 boxes", locationId: "loc-4", categoryId: "cat-4"),
            Item(id: "item-5", name: "Umbrella", locationId: "loc-5"),
            Item(id: "item-6", name: "Spare Keys", notes: "Front door + mailbox"),
            Item(id: "item-7", name: "Camping Tent", notes: "4-person tent", categoryId: "cat-4"),
            Item(id: "item-8", name: "Headphones", notes: "AirPods Max", locationId: "loc-3", categoryId: "cat-1"),
            Item(id: "item-9", name: "Board Games", notes: "Catan, Ticket to Ride", locationId: "loc-1"),
            Item(id: "item-10", name: "Winter Tires", locationId: "loc-2", categoryId: "cat-4"),
        ]
```

Add CRUD methods at the end of MockDataService:

```swift
    // MARK: - Categories

    func fetchCategories() async throws -> [Category] {
        categories
    }

    func addCategory(_ category: Category) async throws {
        categories.append(category)
    }

    func updateCategory(_ category: Category) async throws {
        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            categories[index] = category
        }
    }

    func deleteCategory(_ category: Category) async throws {
        categories.removeAll { $0.id == category.id }
    }
```

- [ ] **Step 4: Build in Xcode to verify**

- [ ] **Step 5: Commit**

```bash
git add MyStuff/Services/DataService.swift MyStuff/Services/FirebaseDataService.swift MyStuff/Services/MockDataService.swift
git commit -m "Add category CRUD to DataService, Firebase, and Mock"
```

---

### Task 3: ViewModel — Category State + CRUD

**Files:**
- Modify: `MyStuff/ViewModels/StuffViewModel.swift`

- [ ] **Step 1: Add GroupingMode enum and category state**

Add at the top of StuffViewModel, after the `Published State` mark and the existing properties:

```swift
    var categories: [Category] = []
    var selectedGrouping: GroupingMode = .location

    enum GroupingMode: String, CaseIterable {
        case location = "Location"
        case category = "Category"
    }
```

- [ ] **Step 2: Add category computed properties**

Add after the existing `itemCount(for location:)` method:

```swift
    // MARK: - Category Computed

    var uncategorizedItems: [Item] {
        items.filter { $0.categoryId == nil }
    }

    func items(for category: Category) -> [Item] {
        items.filter { $0.categoryId == category.id }
    }

    func category(for item: Item) -> Category? {
        guard let categoryId = item.categoryId else { return nil }
        return categories.first { $0.id == categoryId }
    }

    func itemCount(for category: Category) -> Int {
        items.filter { $0.categoryId == category.id }.count
    }
```

- [ ] **Step 3: Update loadData to fetch categories**

Replace `loadData()` with:

```swift
    func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            async let fetchedItems = service.fetchItems()
            async let fetchedLocations = service.fetchLocations()
            async let fetchedCategories = service.fetchCategories()
            items = try await fetchedItems
            locations = try await fetchedLocations
            categories = try await fetchedCategories
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
```

- [ ] **Step 4: Update addItem to accept categoryId**

Replace `addItem(name:notes:locationId:)` with:

```swift
    func addItem(name: String, notes: String?, locationId: String?, categoryId: String?) async {
        let item = Item(name: name, notes: notes, locationId: locationId, categoryId: categoryId)
        do {
            try await service.addItem(item)
            items.append(item)
            HapticManager.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
```

- [ ] **Step 5: Add category CRUD methods**

Add after the Location CRUD section:

```swift
    // MARK: - Category CRUD

    func addCategory(name: String) async {
        let category = Category(name: name)
        do {
            try await service.addCategory(category)
            categories.append(category)
            HapticManager.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateCategory(_ category: Category) async {
        do {
            try await service.updateCategory(category)
            if let index = categories.firstIndex(where: { $0.id == category.id }) {
                categories[index] = category
            }
            HapticManager.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteCategory(_ category: Category) async {
        do {
            try await service.deleteCategory(category)
            categories.removeAll { $0.id == category.id }
            for i in items.indices where items[i].categoryId == category.id {
                items[i].categoryId = nil
                items[i].updatedAt = .now
            }
            HapticManager.impact()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
```

- [ ] **Step 6: Build in Xcode to verify**

Expect build failure — `addItem` call sites in ItemsView.swift don't pass `categoryId` yet. That's expected; fixed in Task 5.

- [ ] **Step 7: Commit**

```bash
git add MyStuff/ViewModels/StuffViewModel.swift
git commit -m "Add category state, computed props, and CRUD to StuffViewModel"
```

---

### Task 4: HomeView — Grouping Toggle + Category Cards

**Files:**
- Modify: `MyStuff/Views/HomeView.swift`

- [ ] **Step 1: Add segmented control and category grouping**

Replace the entire `HomeView` struct (lines 1–146, keeping MoveItemSheet and #Preview intact) with:

```swift
import SwiftUI

struct HomeView: View {
    @Bindable var viewModel: StuffViewModel
    @State private var selectedItem: Item?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.items.isEmpty && viewModel.locations.isEmpty && viewModel.categories.isEmpty {
                    emptyState
                } else {
                    mainContent
                }
            }
            .navigationTitle("My Stuff")
            .sheet(item: $selectedItem) { item in
                MoveItemSheet(
                    item: item,
                    locations: viewModel.locations,
                    onMove: { locationId in
                        Task { await viewModel.moveItem(item, toLocationId: locationId) }
                    }
                )
                .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Grouping picker
                Picker("Group by", selection: $viewModel.selectedGrouping) {
                    ForEach(StuffViewModel.GroupingMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                switch viewModel.selectedGrouping {
                case .location:
                    locationGrouping
                case .category:
                    categoryGrouping
                }
            }
            .padding()
        }
    }

    // MARK: - Location Grouping (existing behavior)

    private var locationGrouping: some View {
        Group {
            ForEach(viewModel.locations) { location in
                locationCard(location)
            }
            if !viewModel.unassignedItems.isEmpty {
                unassignedLocationCard
            }
        }
    }

    // MARK: - Category Grouping

    private var categoryGrouping: some View {
        Group {
            ForEach(viewModel.categories) { category in
                categoryCard(category)
            }
            if !viewModel.uncategorizedItems.isEmpty {
                uncategorizedCard
            }
        }
    }

    // MARK: - Location Card

    private func locationCard(_ location: Location) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(location.emoji ?? "📍")
                    .font(.title2)
                Text(location.name)
                    .font(.headline)
                Spacer()
                Text("\(viewModel.itemCount(for: location))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            let locationItems = viewModel.items(for: location)
            if locationItems.isEmpty {
                Text("No items here")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(locationItems) { item in
                    itemRow(item, tag: categoryTag(for: item))
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Unassigned Location Card

    private var unassignedLocationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("❓")
                    .font(.title2)
                Text("Unassigned")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.unassignedItems.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            ForEach(viewModel.unassignedItems) { item in
                itemRow(item, tag: categoryTag(for: item))
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Category Card

    private func categoryCard(_ category: Category) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(category.name)
                    .font(.headline)
                Spacer()
                Text("\(viewModel.itemCount(for: category))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            let categoryItems = viewModel.items(for: category)
            if categoryItems.isEmpty {
                Text("No items here")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(categoryItems) { item in
                    itemRow(item, tag: locationTag(for: item))
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Uncategorized Card

    private var uncategorizedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Uncategorized")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.uncategorizedItems.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            ForEach(viewModel.uncategorizedItems) { item in
                itemRow(item, tag: locationTag(for: item))
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Item Row

    private func itemRow(_ item: Item, tag: some View) -> some View {
        Button {
            selectedItem = item
        } label: {
            HStack {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    Text(item.name)
                        .font(.subheadline)
                    if let notes = item.notes {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                tag
                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tags

    private func categoryTag(for item: Item) -> some View {
        Group {
            if let category = viewModel.category(for: item) {
                Text(category.name)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }

    private func locationTag(for item: Item) -> some View {
        Group {
            if let location = viewModel.location(for: item) {
                HStack(spacing: 4) {
                    Text(location.emoji ?? "📍")
                        .font(.caption)
                    Text(location.name)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Welcome to MyStuff", systemImage: "shippingbox.fill")
        } description: {
            Text("Start by adding some locations and items.\nYou'll never lose track of your stuff again!")
        }
    }
}
```

Keep the existing `MoveItemSheet` and `#Preview` unchanged after the HomeView struct.

- [ ] **Step 2: Build in Xcode to verify**

Expect build failure still (ItemsView `addItem` call site). That's fine.

- [ ] **Step 3: Commit**

```bash
git add MyStuff/Views/HomeView.swift
git commit -m "Add grouping toggle and category cards to HomeView"
```

---

### Task 5: ItemFormSheet — Category Picker + Inline Creation

**Files:**
- Modify: `MyStuff/Views/ItemsView.swift`

- [ ] **Step 1: Update ItemsView call sites**

In `ItemsView`, update both `.sheet` closures to pass categories and handle the new `categoryId` parameter.

Replace the `showingAddSheet` sheet modifier (lines 28–35):

```swift
            .sheet(isPresented: $showingAddSheet) {
                ItemFormSheet(
                    locations: viewModel.locations,
                    categories: viewModel.categories,
                    onSave: { name, notes, locationId, categoryId in
                        Task { await viewModel.addItem(name: name, notes: notes, locationId: locationId, categoryId: categoryId) }
                    },
                    onCreateCategory: { name in
                        Task { await viewModel.addCategory(name: name) }
                    }
                )
            }
```

Replace the `editingItem` sheet modifier (lines 36–48):

```swift
            .sheet(item: $editingItem) { item in
                ItemFormSheet(
                    item: item,
                    locations: viewModel.locations,
                    categories: viewModel.categories,
                    onSave: { name, notes, locationId, categoryId in
                        var updated = item
                        updated.name = name
                        updated.notes = notes
                        updated.locationId = locationId
                        updated.categoryId = categoryId
                        Task { await viewModel.updateItem(updated) }
                    },
                    onCreateCategory: { name in
                        Task { await viewModel.addCategory(name: name) }
                    }
                )
            }
```

- [ ] **Step 2: Add Categories toolbar button**

Add a second `ToolbarItem` inside the existing `.toolbar` block, before the closing brace of the toolbar:

```swift
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        CategoryManagementView(viewModel: viewModel)
                    } label: {
                        Image(systemName: "folder")
                    }
                }
```

- [ ] **Step 3: Replace ItemFormSheet**

Replace the entire `ItemFormSheet` struct (lines 132–193) with:

```swift
struct ItemFormSheet: View {
    let item: Item?
    let locations: [Location]
    let categories: [Category]
    let onSave: (String, String?, String?, String?) -> Void
    let onCreateCategory: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var notes: String
    @State private var selectedLocationId: String
    @State private var selectedCategoryId: String
    @State private var showingNewCategory = false
    @State private var newCategoryName = ""

    private let unassignedSentinel = "__unassigned__"
    private let uncategorizedSentinel = "__uncategorized__"

    init(
        item: Item? = nil,
        locations: [Location],
        categories: [Category],
        onSave: @escaping (String, String?, String?, String?) -> Void,
        onCreateCategory: @escaping (String) -> Void
    ) {
        self.item = item
        self.locations = locations
        self.categories = categories
        self.onSave = onSave
        self.onCreateCategory = onCreateCategory
        _name = State(initialValue: item?.name ?? "")
        _notes = State(initialValue: item?.notes ?? "")
        _selectedLocationId = State(initialValue: item?.locationId ?? "__unassigned__")
        _selectedCategoryId = State(initialValue: item?.categoryId ?? "__uncategorized__")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Item name", text: $name)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Location") {
                    Picker("Location", selection: $selectedLocationId) {
                        Text("Unassigned").tag(unassignedSentinel)
                        ForEach(locations) { location in
                            Label {
                                Text(location.name)
                            } icon: {
                                Text(location.emoji ?? "📍")
                            }
                            .tag(location.id)
                        }
                    }
                }

                Section("Category") {
                    Picker("Category", selection: $selectedCategoryId) {
                        Text("Uncategorized").tag(uncategorizedSentinel)
                        ForEach(categories) { category in
                            Text(category.name).tag(category.id)
                        }
                    }

                    Button("New Category...") {
                        showingNewCategory = true
                    }
                }
            }
            .navigationTitle(item == nil ? "New Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let locationId = selectedLocationId == unassignedSentinel ? nil : selectedLocationId
                        let categoryId = selectedCategoryId == uncategorizedSentinel ? nil : selectedCategoryId
                        onSave(name, notes.isEmpty ? nil : notes, locationId, categoryId)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("New Category", isPresented: $showingNewCategory) {
                TextField("Category name", text: $newCategoryName)
                Button("Add") {
                    let trimmed = newCategoryName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        onCreateCategory(trimmed)
                        newCategoryName = ""
                    }
                }
                Button("Cancel", role: .cancel) {
                    newCategoryName = ""
                }
            }
        }
    }
}
```

- [ ] **Step 4: Build in Xcode to verify**

Expect build failure — `CategoryManagementView` doesn't exist yet. That's expected; fixed in Task 6.

- [ ] **Step 5: Commit**

```bash
git add MyStuff/Views/ItemsView.swift
git commit -m "Add category picker and inline creation to ItemFormSheet"
```

---

### Task 6: CategoryManagementView

**Files:**
- Create: `MyStuff/Views/CategoryManagementView.swift`

- [ ] **Step 1: Create CategoryManagementView.swift**

```swift
import SwiftUI

struct CategoryManagementView: View {
    @Bindable var viewModel: StuffViewModel
    @State private var showingAddAlert = false
    @State private var newCategoryName = ""
    @State private var editingCategory: Category?
    @State private var editName = ""

    var body: some View {
        Group {
            if viewModel.categories.isEmpty {
                emptyState
            } else {
                categoryList
            }
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddAlert = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New Category", isPresented: $showingAddAlert) {
            TextField("Category name", text: $newCategoryName)
            Button("Add") {
                let trimmed = newCategoryName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    Task { await viewModel.addCategory(name: trimmed) }
                    newCategoryName = ""
                }
            }
            Button("Cancel", role: .cancel) {
                newCategoryName = ""
            }
        }
        .alert("Rename Category", isPresented: Binding(
            get: { editingCategory != nil },
            set: { if !$0 { editingCategory = nil } }
        )) {
            TextField("Category name", text: $editName)
            Button("Save") {
                if var category = editingCategory {
                    let trimmed = editName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        category.name = trimmed
                        Task { await viewModel.updateCategory(category) }
                    }
                }
                editingCategory = nil
            }
            Button("Cancel", role: .cancel) {
                editingCategory = nil
            }
        }
    }

    private var categoryList: some View {
        List {
            ForEach(viewModel.categories) { category in
                Button {
                    editingCategory = category
                    editName = category.name
                } label: {
                    HStack {
                        Text(category.name)
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(viewModel.itemCount(for: category)) items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await viewModel.deleteCategory(category) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Categories Yet", systemImage: "folder")
        } description: {
            Text("Tap + to create your first category.")
        } actions: {
            Button("Add Category") {
                showingAddAlert = true
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
```

- [ ] **Step 2: Build in Xcode to verify**

Expect full build success. All call sites are now satisfied.

- [ ] **Step 3: Commit**

```bash
git add MyStuff/Views/CategoryManagementView.swift
git commit -m "Add CategoryManagementView for managing categories"
```

---

### Task 7: Final Verification

- [ ] **Step 1: Build and run in Xcode**

Run on iOS 26 simulator. Verify:
- Home tab shows segmented control (Location / Category)
- Location grouping shows category tags on items
- Category grouping shows location tags on items
- Items tab: add/edit shows category picker with "New Category..." button
- Items tab: folder button in toolbar navigates to CategoryManagementView
- Categories can be created, renamed, and deleted
- Deleting a category uncategorizes its items

- [ ] **Step 2: Final commit if any adjustments needed**
