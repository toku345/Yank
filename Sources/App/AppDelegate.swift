import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum TerminationPhase: Equatable {
        case running
        case draining
        case replied
    }

    let coordinator: AppCoordinator
    private let beginShutdown: @MainActor () -> Void
    private let finishShutdown: @MainActor () async -> Void
    private let replyToTermination: @MainActor (NSApplication, Bool) -> Void

    private var terminationPhase = TerminationPhase.running
    private var terminationTask: Task<Void, Never>?

    override convenience init() {
        let coordinator = AppCoordinator()
        self.init(
            coordinator: coordinator,
            beginShutdown: { coordinator.beginShutdown() },
            finishShutdown: { await coordinator.finishShutdown() },
            replyToTermination: { application, shouldTerminate in
                application.reply(toApplicationShouldTerminate: shouldTerminate)
            }
        )
    }

    init(
        coordinator: AppCoordinator,
        beginShutdown: @escaping @MainActor () -> Void,
        finishShutdown: @escaping @MainActor () async -> Void,
        replyToTermination: @escaping @MainActor (NSApplication, Bool) -> Void
    ) {
        self.coordinator = coordinator
        self.beginShutdown = beginShutdown
        self.finishShutdown = finishShutdown
        self.replyToTermination = replyToTermination
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Under XCTest the app runs only as a test host: skip real coordinator
        // startup (clipboard monitor / global hotkeys) so tests stay hermetic and
        // don't touch the on-disk Yank.store. Load-bearing — do not remove.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        coordinator.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        switch terminationPhase {
        case .running:
            terminationPhase = .draining
            beginShutdown()
            let finishShutdown = finishShutdown
            let replyToTermination = replyToTermination
            terminationTask = Task { @MainActor [self, sender] in
                await finishShutdown()
                guard terminationPhase == .draining else { return }
                terminationPhase = .replied
                terminationTask = nil
                replyToTermination(sender, true)
            }
            return .terminateLater
        case .draining:
            return .terminateLater
        case .replied:
            return .terminateNow
        }
    }
}
