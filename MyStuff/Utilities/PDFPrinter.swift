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

/// Presents the system share sheet for a file URL, anchored for iPad, from the
/// topmost presented view controller (so it works from within a SwiftUI sheet).
enum PDFShare {
    @MainActor
    static func present(url: URL) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first else { return }

        var top = window.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        guard let presenter = top else { return }

        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let pop = activity.popoverPresentationController {
            pop.sourceView = presenter.view
            pop.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        presenter.present(activity, animated: true)
    }
}
