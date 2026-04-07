import SwiftUI

struct PhotoSourceSheet: View {
    let onCamera: () -> Void
    let onLibrary: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Photo")
                .font(.headline)
                .padding(.top, 20)

            Button {
                dismiss()
                onCamera()
            } label: {
                Label("Take Photo", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                dismiss()
                onLibrary()
            } label: {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .padding(.top, 4)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
        .presentationDetents([.height(260)])
    }
}
