import SwiftUI

/// Toolbar slider controlling the shared gallery column count (iPad only).
struct GalleryColumnSlider: View {
    @AppStorage("galleryColumns") private var galleryColumns = 2

    var body: some View {
        Slider(
            value: Binding(
                get: { Double(galleryColumns) },
                set: { newValue in
                    withAnimation { galleryColumns = Int(newValue.rounded()) }
                }
            ),
            in: 2...4,
            step: 1
        )
        .frame(width: 140)
        .accessibilityLabel("Gallery columns")
        .accessibilityValue("\(galleryColumns) columns")
    }
}

#Preview {
    GalleryColumnSlider()
        .padding()
}
