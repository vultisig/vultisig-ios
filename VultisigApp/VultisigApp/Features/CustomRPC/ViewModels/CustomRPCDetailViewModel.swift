//
//  CustomRPCDetailViewModel.swift
//  VultisigApp
//

import Foundation

@MainActor
final class CustomRPCDetailViewModel: ObservableObject {

    enum ProbeState: Equatable {
        case idle
        case testing
        case result(RPCHealthResult)
    }

    let chain: Chain

    @Published var urlText: String = ""
    @Published private(set) var hasOverride: Bool = false
    @Published private(set) var probeState: ProbeState = .idle

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

    var canSave: Bool { isURLValid }

    var canReset: Bool { hasOverride }

    func test() async {
        guard isURLValid else { return }
        probeState = .testing
        let result = await probe.probe(urlString: urlText, chain: chain)
        probeState = .result(result)
    }

    func save() {
        guard isURLValid else { return }
        store.set(urlText, for: chain)
        hasOverride = true
    }

    func reset() {
        store.reset(chain)
        urlText = ""
        hasOverride = false
        probeState = .idle
    }
}
