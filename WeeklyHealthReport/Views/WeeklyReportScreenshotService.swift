import CoreGraphics
import SwiftUI
import UIKit

@MainActor
protocol ScreenshotServiceRegistering: AnyObject {
    var delegate: (any UIScreenshotServiceDelegate)? { get set }
}

extension UIScreenshotService: ScreenshotServiceRegistering {}

enum WeeklyReportScreenshotEligibility {
    static func isEligible(
        navigationPath: [WeeklyReportRoute],
        isTransientUIPresented: Bool
    ) -> Bool {
        navigationPath.isEmpty && !isTransientUIPresented
    }
}

@MainActor
protocol WeeklyReportPDFRendering {
    func pdfData(for document: WeeklyReportPDFDocument) -> Data?
}

@MainActor
struct WeeklyReportPDFRenderer: WeeklyReportPDFRendering {
    private let pageWidth: CGFloat = 612

    func pdfData(for document: WeeklyReportPDFDocument) -> Data? {
        let imageRenderer = ImageRenderer(
            content: WeeklyReportPDFView(document: document)
                .frame(width: pageWidth)
                .fixedSize(horizontal: false, vertical: true)
        )
        imageRenderer.proposedSize = ProposedViewSize(width: pageWidth, height: nil)
        imageRenderer.scale = 1

        var result: Data?
        imageRenderer.render { size, render in
            guard size.width.isFinite,
                  size.height.isFinite,
                  size.width > 0,
                  size.height > 0 else {
                return
            }

            let bounds = CGRect(origin: .zero, size: size)
            let renderer = UIGraphicsPDFRenderer(bounds: bounds)
            let data = renderer.pdfData { context in
                context.beginPage()
                context.cgContext.translateBy(x: 0, y: size.height)
                context.cgContext.scaleBy(x: 1, y: -1)
                render(context.cgContext)
            }

            guard !data.isEmpty,
                  let provider = CGDataProvider(data: data as CFData),
                  let pdf = CGPDFDocument(provider),
                  pdf.numberOfPages == 1 else {
                return
            }
            result = data
        }
        return result
    }
}

@MainActor
final class WeeklyReportScreenshotDelegate: NSObject, UIScreenshotServiceDelegate {
    typealias RequestProvider = () -> WeeklyReportPDFDocument?

    private let renderer: any WeeklyReportPDFRendering
    private var requestProvider: RequestProvider?

    init(renderer: (any WeeklyReportPDFRendering)? = nil) {
        self.renderer = renderer ?? WeeklyReportPDFRenderer()
    }

    func setRequestProvider(_ provider: @escaping RequestProvider) {
        requestProvider = provider
    }

    func representationForCurrentRequest() -> Data? {
        guard let document = requestProvider?() else { return nil }
        return renderer.pdfData(for: document)
    }

    func screenshotService(
        _ screenshotService: UIScreenshotService,
        generatePDFRepresentationWithCompletion completionHandler: @escaping (
            Data?,
            Int,
            CGRect
        ) -> Void
    ) {
        // This report is one continuous PDF page. Apple's documented zero-rect
        // fallback opens it at the top when the Form's viewport cannot be mapped
        // reliably into the separate report layout.
        completionHandler(representationForCurrentRequest(), 0, .zero)
    }
}

@MainActor
final class WeeklyReportScreenshotController: ObservableObject {
    let delegate: WeeklyReportScreenshotDelegate
    private weak var registeredService: (any ScreenshotServiceRegistering)?

    init(renderer: (any WeeklyReportPDFRendering)? = nil) {
        delegate = WeeklyReportScreenshotDelegate(renderer: renderer)
    }

    func setRequestProvider(_ provider: @escaping WeeklyReportScreenshotDelegate.RequestProvider) {
        delegate.setRequestProvider(provider)
    }

    func register(with service: (any ScreenshotServiceRegistering)?) {
        guard registeredService !== service else { return }
        registeredService?.delegate = nil
        registeredService = service
        service?.delegate = delegate
    }

    func unregister() {
        registeredService?.delegate = nil
        registeredService = nil
    }
}

struct WeeklyReportScreenshotSceneRegistration: UIViewRepresentable {
    let controller: WeeklyReportScreenshotController

    func makeUIView(context: Context) -> SceneRegistrationView {
        let view = SceneRegistrationView()
        view.controller = controller
        view.sceneDidChange = { [weak controller] scene in
            controller?.register(with: scene?.screenshotService)
        }
        return view
    }

    func updateUIView(_ view: SceneRegistrationView, context: Context) {
        controller.register(with: view.window?.windowScene?.screenshotService)
    }

    static func dismantleUIView(
        _ view: SceneRegistrationView,
        coordinator: Void
    ) {
        view.controller?.unregister()
        view.sceneDidChange = nil
    }

    final class SceneRegistrationView: UIView {
        weak var controller: WeeklyReportScreenshotController?
        var sceneDidChange: ((UIWindowScene?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            sceneDidChange?(window?.windowScene)
        }
    }
}
