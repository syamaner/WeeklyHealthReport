import CoreGraphics
import SwiftUI
import UIKit

@MainActor
protocol ScreenshotServiceRegistering: AnyObject {
    var delegate: (any UIScreenshotServiceDelegate)? { get set }
}

extension UIScreenshotService: ScreenshotServiceRegistering {}

/// The screens that offer Full Page.
enum FullPageScreen: Equatable {
    case today
    case healthReport
}

/// What Full Page renders: the Health report document or Today's cards.
enum FullPageDocument: Equatable {
    case healthReport(ReportDocument)
    case today(TodayFullPageDocument)
}

enum WeeklyReportScreenshotEligibility {
    /// Health: exactly `[.healthReport]` with no transient UI (unchanged).
    /// Today: the empty path with no transient UI, while Home itself is on
    /// screen (not covered by a sheet or a pushed confirmation).
    static func screen(
        navigationPath: [AppRoute],
        isTransientUIPresented: Bool,
        isTodayOnScreen: Bool = true
    ) -> FullPageScreen? {
        guard !isTransientUIPresented else { return nil }
        if navigationPath == [.healthReport] { return .healthReport }
        if navigationPath.isEmpty && isTodayOnScreen { return .today }
        return nil
    }

    static func isEligible(
        navigationPath: [AppRoute],
        isTransientUIPresented: Bool,
        isTodayOnScreen: Bool = true
    ) -> Bool {
        screen(
            navigationPath: navigationPath,
            isTransientUIPresented: isTransientUIPresented,
            isTodayOnScreen: isTodayOnScreen
        ) != nil
    }
}

@MainActor
protocol WeeklyReportPDFRendering {
    func pdfData(for document: FullPageDocument) -> Data?
}

@MainActor
struct WeeklyReportPDFRenderer: WeeklyReportPDFRendering {
    private let pageWidth: CGFloat = 612

    func pdfData(for document: FullPageDocument) -> Data? {
        switch document {
        case .healthReport(let report): pdfData(for: report)
        case .today(let today): pdfData(for: today)
        }
    }

    func pdfData(for document: ReportDocument) -> Data? {
        pdfData(rendering: WeeklyReportPDFView(document: document))
    }

    func pdfData(for document: TodayFullPageDocument) -> Data? {
        pdfData(rendering: TodayFullPagePDFView(document: document))
    }

    private func pdfData(rendering content: some View) -> Data? {
        let imageRenderer = ImageRenderer(
            content: content
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
    typealias RequestProvider = () -> FullPageDocument?

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
        // Each Full Page document is one continuous PDF page. Apple's documented zero-rect
        // fallback opens it at the top when the Form's viewport cannot be mapped
        // reliably into the separate report layout.
        let data = representationForCurrentRequest()
        #if DEBUG
        FullPageDiagnostics.logger.debug(
            "iOS requested Full Page: pdfBytes=\(data.map { String($0.count) } ?? "nil", privacy: .public)")
        #endif
        completionHandler(data, 0, .zero)
    }
}

@MainActor
final class WeeklyReportScreenshotController: ObservableObject {
    let delegate: WeeklyReportScreenshotDelegate
    /// Set while Home is the visible root of the stack; a pushed Confirm from
    /// quick add leaves the path empty but hides Home.
    var isTodayOnScreen = false
    /// The window hosting the app's stack, used to detect a presented sheet,
    /// alert or system sheet over Home.
    weak var hostWindow: UIWindow?
    private weak var registeredService: (any ScreenshotServiceRegistering)?

    var isPresentingModally: Bool {
        hostWindow?.rootViewController?.presentedViewController != nil
    }

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

    #if DEBUG
    /// DEBUG-only Full Page diagnostics: whether the active scene's screenshot
    /// service points at this delegate, and what the delegate would return now.
    func logDiagnostics(_ reason: String, details: String) {
        let scene = hostWindow?.windowScene
        let service = scene?.screenshotService
        let bytes = delegate.representationForCurrentRequest()?.count
        FullPageDiagnostics.logger.debug("""
            \(reason, privacy: .public): \(details, privacy: .public) \
            window=\(self.hostWindow != nil, privacy: .public) \
            sceneState=\(scene?.activationState.rawValue ?? -9, privacy: .public) \
            service=\(service != nil, privacy: .public) \
            delegateIsOurs=\(service?.delegate === self.delegate, privacy: .public) \
            modal=\(self.isPresentingModally, privacy: .public) \
            todayOnScreen=\(self.isTodayOnScreen, privacy: .public) \
            pdfBytes=\(bytes.map(String.init) ?? "nil", privacy: .public)
            """)
    }
    #endif
}

#if DEBUG
import os

enum FullPageDiagnostics {
    static let logger = Logger(subsystem: "WeeklyHealthReport", category: "FullPage")
}
#endif

struct WeeklyReportScreenshotSceneRegistration: UIViewRepresentable {
    let controller: WeeklyReportScreenshotController

    func makeUIView(context: Context) -> SceneRegistrationView {
        let view = SceneRegistrationView()
        view.controller = controller
        view.sceneDidChange = { [weak controller, weak view] scene in
            controller?.hostWindow = view?.window
            controller?.register(with: scene?.screenshotService)
        }
        return view
    }

    func updateUIView(_ view: SceneRegistrationView, context: Context) {
        controller.hostWindow = view.window
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
