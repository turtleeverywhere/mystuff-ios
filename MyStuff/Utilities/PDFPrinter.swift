import UIKit

/// Presents the system AirPrint sheet for a PDF, anchored to the key window so
/// it works on both iPhone and iPad (the un-anchored overload fails on iPad).
enum PDFPrinter {
    @MainActor
    static func print(_ data: Data, jobName: String) {
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = jobName
        info.outputType = .general

        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = data

        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) {
            controller.present(from: window.bounds, in: window, animated: true, completionHandler: nil)
        } else {
            controller.present(animated: true, completionHandler: nil)
        }
    }
}
