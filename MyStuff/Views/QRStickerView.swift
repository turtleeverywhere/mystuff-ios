import SwiftUI

/// Printable sticker: QR code with an optional emoji icon + name caption, on a
/// white card. Icon and name each default to shown but can be toggled off.
/// Deliberately white-on-black regardless of app theme for print contrast.
/// Rendered on-screen and via `ImageRenderer` for PNG/PDF export, so its layout
/// is fixed-size and self-contained.
struct QRStickerView: View {
    let location: Location
    let qrImage: UIImage
    var showIcon: Bool = true
    var showName: Bool = true

    private var showsCaption: Bool { showIcon || showName }

    var body: some View {
        VStack(spacing: showsCaption ? 16 : 0) {
            Image(uiImage: qrImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 240, height: 240)

            if showsCaption {
                HStack(spacing: 8) {
                    if showIcon {
                        Text(location.emoji ?? "📍")
                            .font(.title)
                    }
                    if showName {
                        Text(location.name)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.black)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .padding(28)
        .frame(width: 320)
        .background(Color.white)
    }
}

#Preview {
    QRStickerView(
        location: Location(name: "Garage", emoji: "🚗"),
        qrImage: QRCodeGenerator.image(for: "https://mystuff.coding-turtle.org/location/demo") ?? UIImage()
    )
}
