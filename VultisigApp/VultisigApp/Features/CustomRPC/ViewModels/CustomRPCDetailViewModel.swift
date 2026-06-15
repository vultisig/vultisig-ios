//
//  CustomRPCDetailViewModel.swift
//  VultisigApp
//

import Foundation

@MainActor
final class CustomRPCDetailViewModel: ObservableObject {

    let chain: Chain

    @Published var urlText: String = "" {
        didSet {
            guard urlText != oldValue else { return }
            // Clear stale validation feedback when the endpoint changes so the
            // displayed error always matches the current URL.
            saveError = nil
        }
    }

    /// Whether an override is currently persisted for this chain. Drives the
    /// New vs Edit layout (Edit shows the default-endpoint card and Reset).
    @Published private(set) var hasOverride: Bool = false

    /// True while the save probe is in flight — shows the button spinner and
    /// blocks overlapping saves.
    @Published private(set) var isSaving: Bool = false

    /// Inline error shown under the field when validation or the save probe
    /// fails. `nil` when there is nothing to report.
    @Published var saveError: String?

    private let store: CustomRPCStore
    private let probe: RPCHealthProbe

    init(
        chain: Chain,
        store: CustomRPCStore = .shared,
        probe: RPCHealthProbe = RPCHealthProbe()
    ) {
        self.chain = chain
        self.store = store
        self.probe = probe
    }

    func load() {
        let current = store.url(for: chain)
        urlText = current ?? ""
        hasOverride = current != nil
    }

    /// Toolbar title, e.g. "Ethereum RPC".
    var screenTitle: String {
        String(format: "customRPCScreenTitle".localized, chain.name)
    }

    /// The hardcoded default endpoint for this chain, shown in the read-only
    /// DEFAULT ENDPOINT card.
    var defaultEndpoint: String? {
        CustomRPCDefaultEndpoint.string(for: chain)
    }

    /// A well-formed http(s) URL with a host.
    var isURLValid: Bool {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            return false
        }
        return true
    }

    var canSave: Bool { isURLValid && !isSaving }

    var canReset: Bool { hasOverride && !isSaving }

    /// Probes the endpoint and, only if it is reachable on the right chain,
    /// persists the override. Returns `true` when the override was saved so the
    /// caller can navigate back. Blocks and surfaces an inline error otherwise.
    func save() async -> Bool {
        guard isURLValid else {
            saveError = "customRPCInvalidURL".localized
            return false
        }
        saveError = nil
        isSaving = true
        defer { isSaving = false }

        let result = await probe.probe(urlString: urlText, chain: chain)
        switch result {
        case .ok:
            store.set(urlText, for: chain)
            hasOverride = true
            return true
        case .unreachable:
            saveError = "customRPCUnreachable".localized
            return false
        case .wrongChain(let expected, let got):
            saveError = String(format: "customRPCWrongChain".localized, expected, got)
            return false
        case .invalidResponse:
            saveError = "customRPCInvalidResponse".localized
            return false
        }
    }

    func reset() {
        store.reset(chain)
        urlText = ""
        hasOverride = false
        saveError = nil
    }
}
