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
        FullPageDiagnostics.log("iOS requested Full Page: pdfBytes=\(data.map { String($0.count) } ?? "nil")")
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
    /// The scene's key window, used to detect a presented sheet, alert or
    /// system sheet over Home.
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

    /// Sets this delegate on the service every time, even when the service is
    /// unchanged, so a delegate cleared or replaced elsewhere is restored.
    func register(with service: (any ScreenshotServiceRegistering)?) {
        if registeredService !== service, registeredService?.delegate === delegate {
            registeredService?.delegate = nil
        }
        registeredService = service
        service?.delegate = delegate
    }

    func unregister() {
        if registeredService?.delegate === delegate {
            registeredService?.delegate = nil
        }
        registeredService = nil
    }

    var isRegistered: Bool {
        registeredService != nil && registeredService?.delegate === delegate
    }

    #if DEBUG
    /// DEBUG-only Full Page diagnostics: whether the scene's screenshot service
    /// points at this delegate, and what the delegate would return now.
    func logDiagnostics(_ reason: String, details: String) {
        let scene = hostWindow?.windowScene
        let bytes = delegate.representationForCurrentRequest()?.count
        FullPageDiagnostics.log(
            "\(reason): \(details) window=\(hostWindow != nil) "
                + "sceneState=\(scene?.activationState.rawValue ?? -9) "
                + "service=\(registeredService != nil) delegateIsOurs=\(isRegistered) "
                + "modal=\(isPresentingModally) todayOnScreen=\(isTodayOnScreen) "
                + "pdfBytes=\(bytes.map(String.init) ?? "nil")"
        )
    }
    #endif
}

/// Registers Full Page at scene level. The app has one window scene
/// (multiple scenes are off), and the screenshot service only asks a delegate
/// set on that scene's `screenshotService`. The old registration view sat on
/// Home, the stack's root: pushing Health took Home's view out of the window,
/// `didMoveToWindow` reported no window, and it cleared the service's delegate,
/// so iOS never asked on Health (and a launch restored to Health never
/// registered at all). This resolves the scene from the
/// application, re-registers on every scene activation and foreground entry,
/// and keeps the controller (and so the delegate the service holds weakly)
/// alive for the app's lifetime.
@MainActor
final class FullPageSceneRegistry {
    struct Target {
        let service: (any ScreenshotServiceRegistering)?
        let window: UIWindow?
    }

    static let shared = FullPageSceneRegistry()

    private let resolve: @MainActor () -> Target?
    private var controller: WeeklyReportScreenshotController?
    private var observers: [NSObjectProtocol] = []

    init(
        notificationCenter: NotificationCenter = .default,
        resolve: @escaping @MainActor () -> Target? = FullPageSceneRegistry.applicationWindowScene
    ) {
        self.resolve = resolve
        let names: [(Notification.Name, String)] = [
            (UIScene.willConnectNotification, "scene connected"),
            (UIScene.didActivateNotification, "scene activated"),
            (UIScene.willEnterForegroundNotification, "scene entering foreground")
        ]
        observers = names.map { name, reason in
            notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh(reason) }
            }
        }
    }

    /// Called by the shell when it appears; safe to call repeatedly.
    func attach(_ controller: WeeklyReportScreenshotController) {
        self.controller = controller
        refresh("shell appeared")
    }

    func refresh(_ reason: String) {
        guard let controller else { return }
        let target = resolve()
        // Never unregister on a failed lookup or a detached window: the scene's
        // service stays registered for the scene's lifetime.
        if let window = target?.window { controller.hostWindow = window }
        if let service = target?.service { controller.register(with: service) }
        #if DEBUG
        FullPageDiagnostics.log(
            "registered (\(reason)): scene=\(target != nil) service=\(target?.service != nil) "
                + "window=\(target?.window != nil) delegateIsOurs=\(controller.isRegistered)"
        )
        #endif
    }

    /// The foreground-active window scene, else any connected window scene.
    static func applicationWindowScene() -> Target? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive })
            ?? scenes.first else {
            return nil
        }
        return Target(service: scene.screenshotService, window: scene.keyWindow ?? scene.windows.first)
    }
}

#if DEBUG
/// DEBUG-only: appends Full Page diagnostics to Documents/fullpage-diagnostics.log
/// for a device check. Temporary; remove before #228 is ready.
enum FullPageDiagnostics {
    static func log(_ line: String) {
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let url = directory.appendingPathComponent("fullpage-diagnostics.log")
        let data = Data((ISO8601DateFormatter().string(from: Date()) + " " + line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
#endif
