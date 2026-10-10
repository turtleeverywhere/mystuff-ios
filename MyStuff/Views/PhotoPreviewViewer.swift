import SwiftUI

/// Full-screen photo viewer: pinch to zoom, drag to pan, swipe down to dismiss.
/// Reached by double-tapping an item row or gallery tile, or by tapping a row's
/// photo thumbnail.
struct PhotoPreviewViewer: View {
    let item: Item
    let kind: PhotoKind
    @Bindable var viewModel: StuffViewModel

    @Environment(\.dismiss) private var dismiss

    /// Resolution outcome reported by `PhotoView` — nil while still resolving.
    @State private var didResolve: Bool?
    /// Committed zoom, and the live delta from an in-flight pinch.
    @State private var zoom: CGFloat = 1
    @State private var gestureZoom: CGFloat = 1
    /// Committed pan, and the live delta from an in-flight drag.
    @State private var offset: CGSize = .zero
    @State private var gestureOffset: CGSize = .zero
    /// Vertical travel of a swipe-to-dismiss drag. Only ever non-zero at 1x.
    @State private var dismissDrag: CGFloat = 0

    private let maxZoom: CGFloat = 5
    private let doubleTapZoom: CGFloat = 2.5
    private let dismissThreshold: CGFloat = 150

    /// Follow the view model so a photo swapped underneath the viewer redraws.
    private var liveItem: Item {
        viewModel.items.first(where: { $0.id == item.id }) ?? item
    }

    private var hasPhoto: Bool {
        kind == .item ? liveItem.hasItemPhoto : liveItem.hasLocationPhoto
    }

    private var currentZoom: CGFloat { zoom * gestureZoom }

    /// Slack of 0.01 keeps float noise from reading as "zoomed".
    private var isZoomed: Bool { currentZoom > 1.01 }

    private var backdropOpacity: Double {
        max(0, 1 - Double(abs(dismissDrag) / (dismissThreshold * 3)))
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backdropOpacity)
                .ignoresSafeArea()

            photoLayer
                .scaleEffect(currentZoom)
                .offset(
                    x: offset.width + gestureOffset.width,
                    y: offset.height + gestureOffset.height + dismissDrag
                )
        }
        .contentShape(Rectangle())
        .gesture(magnifyGesture)
        .simultaneousGesture(dragGesture)
        .onTapGesture(count: 2) { toggleZoom() }
        .overlay(alignment: .topLeading) { caption }
        .overlay(alignment: .topTrailing) { closeButton }
        .statusBarHidden()
    }

    // MARK: - Photo

    @ViewBuilder
    private var photoLayer: some View {
        if hasPhoto {
            PhotoView(
                item: liveItem,
                kind: kind,
                size: .full,
                onResolve: { didResolve = $0 }
            ) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                if didResolve == false {
                    unavailableState
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
        } else {
            unavailableState
        }
    }

    private var unavailableState: some View {
        ContentUnavailableView {
            Label("Photo Unavailable", systemImage: "photo.badge.exclamationmark")
        } description: {
            Text("Couldn't load this photo. Check your connection.")
        }
        .foregroundStyle(.white)
    }

    // MARK: - Chrome

    private var caption: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(liveItem.name)
                .font(.headline)
                .foregroundStyle(.white)
            if let location = viewModel.location(for: liveItem) {
                HStack(spacing: 4) {
                    Text(location.emoji ?? "📍")
                    Text(location.name)
                }
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding()
        .opacity(isZoomed ? 0 : 1)
        .animation(.easeInOut(duration: 0.2), value: isZoomed)
        .allowsHitTesting(false)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
        }
        .padding()
        .accessibilityLabel("Close")
    }

    // MARK: - Gestures

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                gestureZoom = value.magnification
            }
            .onEnded { _ in
                let combined = zoom * gestureZoom
                let settled = combined <= 1.01 ? 1 : min(combined, maxZoom)

                // Hand the live delta over to the committed value in one
                // unanimated step. The photo is already drawn at `combined`, so
                // clearing `gestureZoom` while animating `zoom` would render
                // their product as 1x for a frame — a zoom-out bounce on release.
                gestureZoom = 1
                zoom = combined

                // Only a clamp — pinched past the limits — is worth animating.
                guard settled != combined else { return }
                withAnimation(.spring(duration: 0.25)) {
                    zoom = settled
                    if settled == 1 { offset = .zero }
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if isZoomed {
                    gestureOffset = value.translation
                } else if value.translation.height > 0 {
                    dismissDrag = value.translation.height
                }
            }
            .onEnded { value in
                gestureOffset = .zero
                if isZoomed {
                    offset.width += value.translation.width
                    offset.height += value.translation.height
                    dismissDrag = 0
                } else if value.translation.height > dismissThreshold {
                    dismiss()
                } else {
                    withAnimation(.spring(duration: 0.25)) { dismissDrag = 0 }
                }
            }
    }

    private func toggleZoom() {
        withAnimation(.spring(duration: 0.25)) {
            if isZoomed {
                zoom = 1
                offset = .zero
            } else {
                zoom = doubleTapZoom
            }
        }
    }
}

// MARK: - Row & Tile Gestures

extension View {
    /// Single tap opens the row's usual destination; double tap previews the photo.
    ///
    /// The double-tap recognizer is attached only when there is a photo to
    /// preview. That is deliberate: an attached recognizer makes SwiftUI hold
    /// every single tap back to see whether a second one lands, so rows without
    /// a photo would pay a delay for a gesture that does nothing.
    @ViewBuilder
    func itemTapGestures(
        previewEnabled: Bool,
        onPreview: @escaping () -> Void,
        onOpen: @escaping () -> Void
    ) -> some View {
        if previewEnabled {
            self
                .accessibilityAction { onOpen() }
                .accessibilityAction(named: Text("Preview photo")) { onPreview() }
                .onTapGesture(count: 2, perform: onPreview)
                .onTapGesture(perform: onOpen)
        } else {
            self.accessibilityAction { onOpen() }.onTapGesture(perform: onOpen)
        }
    }
}
