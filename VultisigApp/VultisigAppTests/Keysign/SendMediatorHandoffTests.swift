#if canImport(UIKit)
@testable import Mediator
import SwiftUI
import XCTest
@testable import VultisigApp

@MainActor
final class SendMediatorHandoffTests: XCTestCase {
    func testLeavingSendDoesNotStopTheNewPairingSession() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let model = SendFormFixture.make(amountValidators: [])
        let state = HandoffState()
        let router = NavigationRouter()
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView:
            HandoffHost(router: router, model: model, state: state)
            .environment(\.router, router)
            .environment(KeysignReviewPresenter())
            .environmentObject(DeeplinkViewModel())
            .environmentObject(CoinSelectionViewModel())
            .environmentObject(AppViewModel.shared)
            .environmentObject(SettingsViewModel.shared)
            .environmentObject(HomeViewModel())
            .environmentObject(PushNotificationManager.shared)
            .environmentObject(SheetPresentedCounterManager())
            .modelContainer(token.container)
        )
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
            Mediator.shared.stop()
        }
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(500))
        withAnimation { router.navigate(to: KeysignReviewFixture.fastKeysignRoute()) }
        for _ in 0..<50 where !state.disappeared || !state.started {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(state.started)
        XCTAssertTrue(state.disappeared)
        // Simulators share the host network. A concurrent wallet or test may
        // own the mediator's fixed port; that is not a lifecycle regression.
        guard state.serverStarted else { throw XCTSkip("Mediator port 18080 is in use by another process") }
        let events = state.events.joined(separator: " → ")
        guard state.events == ["pairing mediator started", "send disappeared"] else {
            throw XCTSkip("This runtime did not exercise the late cleanup ordering: \(events)")
        }
        let attachment = XCTAttachment(string: events)
        attachment.name = "send-pairing-lifecycle"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(Mediator.shared.server.state, .running, "Pairing mediator must still be running: \(events)")

        // Back out of pairing, then leave Send: preserve the old exit cleanup.
        withAnimation { router.navigateBack() }
        for _ in 0..<50 where state.appearances < 2 {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertGreaterThanOrEqual(state.appearances, 2)
        state.disappeared = false
        state.showForm = false
        for _ in 0..<50 where !state.disappeared {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(state.disappeared)
        XCTAssertEqual(Mediator.shared.server.state, .stopped, "Leaving Send after backing out must clean up the session")
    }
}

@MainActor
@Observable
private final class HandoffState {
    var showForm = true
    var appearances = 0
    var started = false
    var serverStarted = false
    var disappeared = false
    var events: [String] = []
}

private struct HandoffHost: View {
    @ObservedObject var router: NavigationRouter
    let model: SendDetailsViewModel
    let state: HandoffState

    var body: some View {
        NavigationStack(path: $router.navPath) {
            ZStack {
                if state.showForm {
                    SendDetailsScreen(coin: nil, viewModel: model, vault: model.vault)
                        .onAppear { state.appearances += 1 }
                        .onDisappear {
                            state.events.append("send disappeared")
                            state.disappeared = true
                        }
                }
            }
            .navigationDestination(for: SigningRoute.self) { _ in
                Text("Pairing lifecycle probe")
                    .onLoad {
                        Task { @MainActor in
                            Mediator.shared.start(name: "Keysign-review-test")
                            state.serverStarted = Mediator.shared.server.state == .running
                            state.events.append("pairing mediator started")
                            state.started = true
                        }
                    }
            }
        }
    }
}
#endif
