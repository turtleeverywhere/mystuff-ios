import SwiftUI

/// Printable sticker: QR code above the location's emoji + name, on a white card.
/// Deliberately white-on-black regardless of app theme for print contrast.
/// Rendered on-screen and via `ImageRenderer` for PNG/PDF export, so its layout
/// is fixed-size and self-contained.
struct QRStickerView: View {
    let location: Location
    let qrImage: UIImage

    var body: some View {
        VStack(spacing: 16) {
            Image(uiImage: qrImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 240, height: 240)

            HStack(spacing: 8) {
                Text(location.emoji ?? "📍")
                    .font(.title)
                Text(location.name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
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
