//
//  TonJettonTestSupport.swift
//  VultisigAppTests
//
//  Shared doubles + recorded payloads for the TON jetton suites. Every JSON
//  literal here was captured from the live service it names and then trimmed;
//  no test in this directory performs a network call.
//

import Foundation
@testable import VultisigApp

/// Drives one scripted outcome per request, so a suite can assert what happens
/// on the *second* call — which is how "only successes are cached" is provable.
final class ScriptedJettonHTTPClient: HTTPClientProtocol, @unchecked Sendable {

    enum Step {
        case success(String)
        case failure
    }

    private let lock = NSLock()
    private var script: [Step]
    private var _attempts = 0
    private let delay: Duration

    /// Requests served so far. The last step repeats once the script runs out.
    var attempts: Int { lock.withLock { _attempts } }

    init(script: [Step], delay: Duration = .zero) {
        self.script = script
        self.delay = delay
    }

    func request(_: TargetType) async throws -> HTTPResponse<Data> {
        let step: Step = lock.withLock {
            let index = min(_attempts, script.count - 1)
            _attempts += 1
            return script[index]
        }

        if delay > .zero {
            try? await Task.sleep(for: delay)
        }

        switch step {
        case .failure:
            throw HTTPError.statusCode(503, nil)
        case .success(let json):
            guard let url = URL(string: "https://test.local"),
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
            else {
                throw HTTPError.invalidResponse
            }
            return HTTPResponse(data: Data(json.utf8), response: response)
        }
    }
}

/// A clock the test moves by hand, so TTL behaviour is asserted rather than waited out.
final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self._now = start
    }

    var now: Date { lock.withLock { _now } }

    func advance(by interval: TimeInterval) {
        lock.withLock { _now += interval }
    }
}

enum TonJettonFixtures {

    // MARK: - Addresses (the real Tether jetton master, in every spelling)

    static let usdtMasterRawUpper = "0:B113A994B5024A16719F69139328EB759596C38A25F59028B146FECDC3621DFE"
    static let usdtMasterRawLower = "0:b113a994b5024a16719f69139328eb759596c38a25f59028b146fecdc3621dfe"
    static let usdtMasterFriendly = "EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs"

    static let notcoinMasterRaw = "0:2f956143c461769579baef2e32cc2d7bc18283f40d20bb03e432cd603ac33ffc"
    static let dogsMasterRaw = "0:afc49cb8786f21c87045b19ede78fc6b46c51048513f8e9a6d44060199c1bf0c"

    /// A jetton master that is on no list — used as the counterfeit's address.
    static let unlistedMasterRaw = "0:87E3837BDC15C4853F34EB72802BFDBBA02A26BC99E601A79BB28F9D668C80CB"
    static let secondUnlistedMasterRaw = "0:6F323F84B83F1F606A65F06FA365E123E1281FE1334E2FADAAF38AA812D6375F"

    // MARK: - ton-assets

    /// Four real `jettons.json` entries, verbatim. Tether is listed under the
    /// tugrik spelling with no `decimals`, and `image` is explicitly null for
    /// most of the file — both are why the curated overlay matters.
    static let tonAssetsWhitelist = #"""
    [
      {"address": "0:b113a994b5024a16719f69139328eb759596c38a25f59028b146fecdc3621dfe", "symbol": "USD₮", "name": "Tether USD", "image": null},
      {"address": "0:2f956143c461769579baef2e32cc2d7bc18283f40d20bb03e432cd603ac33ffc", "symbol": "NOT", "name": "Notcoin", "decimals": 9},
      {"address": "0:afc49cb8786f21c87045b19ede78fc6b46c51048513f8e9a6d44060199c1bf0c", "symbol": "DOGS", "name": "Dogs", "image": null},
      {"address": "0:3690254dc15b2297610cda60744a45f2b710aa4234b89adb630e99d79b01bd4f", "symbol": "STON", "name": "STON", "decimals": 9},
      {"address": "0:729c13b6df2c07cbf0a06ab63d34af454f3d320ec1bcd8fb5c6d24d0806a17c2", "symbol": "jUSDT", "name": "jUSDT", "decimals": 6}
    ]
    """#

    /// Entries the builder must drop rather than index: no symbol, a blank
    /// symbol, and an address that is not a TON address at all.
    static let tonAssetsWithUnusableEntries = #"""
    [
      {"address": "0:2f956143c461769579baef2e32cc2d7bc18283f40d20bb03e432cd603ac33ffc", "symbol": "NOT", "name": "Notcoin", "decimals": 9},
      {"address": "0:afc49cb8786f21c87045b19ede78fc6b46c51048513f8e9a6d44060199c1bf0c", "name": "No Symbol"},
      {"address": "0:3690254dc15b2297610cda60744a45f2b710aa4234b89adb630e99d79b01bd4f", "symbol": "   ", "name": "Blank Symbol"},
      {"address": "0xd2912bc567894032f42edda72bd27bcaae79d74c", "symbol": "EVM", "name": "Not A Ton Address"}
    ]
    """#

    /// The shape a proxy or a CDN error page returns — an object, not a list.
    static let tonAssetsMalformed = #"{"message": "Not Found"}"#

    // MARK: - Toncenter owner-jetton-wallets listing

    static let owner = "0:83DFD552E63729B472FCBCC8C45EBCC6691702558B68EC7527E1BA403A0F31A8"
    static let foreignOwner = "0:1111111111111111111111111111111111111111111111111111111111111111"

    static let stonMasterRaw = "0:3690254DC15B2297610CDA60744A45F2B710AA4234B89ADB630E99D79B01BD4F"
    static let jusdtMasterRaw = "0:729C13B6DF2C07CBF0A06AB63D34AF454F3D320EC1BCD8FB5C6D24D0806A17C2"

    static let dogsLogo = "https://proxy.toncenter.com/dogs/pr:medium/abc"

    /// One page of `/ton/v3/jetton/wallets`, shaped exactly like the live
    /// response: raw upper-case addresses, and a `metadata` map carrying an
    /// entry for **every** address in the response — the owner's jetton wallets
    /// under `type: "jetton_wallets"` as well as the masters under
    /// `type: "jetton_masters"`, both marked `valid: true`.
    ///
    /// Seven rows, each present for a reason:
    ///   1. USDT   — curated, held
    ///   2. NOT    — whitelisted, held, balance beyond `UInt64`
    ///   3. DOGS   — whitelisted, held; its master entry is listed *after* a
    ///               wallet-typed one and carries the only logo in the fixture
    ///   4. counterfeit — unlisted, calls itself `USD₮` / "Tether USD", and
    ///               reports `is_scam: false` the way real counterfeits do
    ///   5. MMM    — unlisted and impersonating nothing
    ///   6. STON   — whitelisted, but owned by somebody else
    ///   7. jUSDT  — whitelisted and held at zero
    static let ownerJettonWalletsPage = #"""
    {
      "jetton_wallets": [
        {"address": "0:AA01000000000000000000000000000000000000000000000000000000000001", "balance": "5000000", "owner": "0:83DFD552E63729B472FCBCC8C45EBCC6691702558B68EC7527E1BA403A0F31A8", "jetton": "0:B113A994B5024A16719F69139328EB759596C38A25F59028B146FECDC3621DFE"},
        {"address": "0:AA01000000000000000000000000000000000000000000000000000000000002", "balance": "184467440737095516160000", "owner": "0:83DFD552E63729B472FCBCC8C45EBCC6691702558B68EC7527E1BA403A0F31A8", "jetton": "0:2F956143C461769579BAEF2E32CC2D7BC18283F40D20BB03E432CD603AC33FFC"},
        {"address": "0:AA01000000000000000000000000000000000000000000000000000000000003", "balance": "250000000000", "owner": "0:83DFD552E63729B472FCBCC8C45EBCC6691702558B68EC7527E1BA403A0F31A8", "jetton": "0:AFC49CB8786F21C87045B19EDE78FC6B46C51048513F8E9A6D44060199C1BF0C"},
        {"address": "0:AA01000000000000000000000000000000000000000000000000000000000004", "balance": "9000000", "owner": "0:83DFD552E63729B472FCBCC8C45EBCC6691702558B68EC7527E1BA403A0F31A8", "jetton": "0:87E3837BDC15C4853F34EB72802BFDBBA02A26BC99E601A79BB28F9D668C80CB"},
        {"address": "0:AA01000000000000000000000000000000000000000000000000000000000005", "balance": "1000000000", "owner": "0:83DFD552E63729B472FCBCC8C45EBCC6691702558B68EC7527E1BA403A0F31A8", "jetton": "0:6F323F84B83F1F606A65F06FA365E123E1281FE1334E2FADAAF38AA812D6375F"},
        {"address": "0:AA01000000000000000000000000000000000000000000000000000000000006", "balance": "7000000", "owner": "0:1111111111111111111111111111111111111111111111111111111111111111", "jetton": "0:3690254DC15B2297610CDA60744A45F2B710AA4234B89ADB630E99D79B01BD4F"},
        {"address": "0:AA01000000000000000000000000000000000000000000000000000000000007", "balance": "0", "owner": "0:83DFD552E63729B472FCBCC8C45EBCC6691702558B68EC7527E1BA403A0F31A8", "jetton": "0:729C13B6DF2C07CBF0A06AB63D34AF454F3D320EC1BCD8FB5C6D24D0806A17C2"}
      ],
      "metadata": {
        "0:AA01000000000000000000000000000000000000000000000000000000000001": {"is_indexed": true, "token_info": [{"valid": true, "type": "jetton_wallets", "extra": {"balance": "5000000"}}]},
        "0:AA01000000000000000000000000000000000000000000000000000000000003": {"is_indexed": true, "token_info": [{"valid": true, "type": "jetton_wallets", "extra": {"balance": "250000000000"}}]},
        "0:B113A994B5024A16719F69139328EB759596C38A25F59028B146FECDC3621DFE": {"is_indexed": true, "token_info": [{"valid": true, "type": "jetton_masters", "name": "Tether USD", "symbol": "USD₮", "is_scam": false, "extra": {"decimals": "6"}}]},
        "0:2F956143C461769579BAEF2E32CC2D7BC18283F40D20BB03E432CD603AC33FFC": {"is_indexed": true, "token_info": [{"valid": true, "type": "jetton_masters", "name": "Notcoin", "symbol": "NOT", "is_scam": false, "extra": {"decimals": "9"}}]},
        "0:AFC49CB8786F21C87045B19EDE78FC6B46C51048513F8E9A6D44060199C1BF0C": {"is_indexed": true, "token_info": [{"valid": true, "type": "jetton_wallets", "extra": {"balance": "250000000000"}}, {"valid": true, "type": "jetton_masters", "name": "Dogs", "symbol": "DOGS", "is_scam": false, "extra": {"decimals": "9", "_image_medium": "https://proxy.toncenter.com/dogs/pr:medium/abc"}}]},
        "0:87E3837BDC15C4853F34EB72802BFDBBA02A26BC99E601A79BB28F9D668C80CB": {"is_indexed": true, "token_info": [{"valid": true, "type": "jetton_masters", "name": "Tether USD", "symbol": "USD₮", "is_scam": false, "extra": {"decimals": "6"}}]},
        "0:6F323F84B83F1F606A65F06FA365E123E1281FE1334E2FADAAF38AA812D6375F": {"is_indexed": true, "token_info": [{"valid": true, "type": "jetton_masters", "name": "MMM2049", "symbol": "MMM", "is_scam": false, "extra": {"decimals": "9"}}]},
        "0:3690254DC15B2297610CDA60744A45F2B710AA4234B89ADB630E99D79B01BD4F": {"is_indexed": true, "token_info": [{"valid": true, "type": "jetton_masters", "name": "STON", "symbol": "STON", "is_scam": false, "extra": {"decimals": "9"}}]},
        "0:729C13B6DF2C07CBF0A06AB63D34AF454F3D320EC1BCD8FB5C6D24D0806A17C2": {"is_indexed": true, "token_info": [{"valid": true, "type": "jetton_masters", "name": "jUSDT", "symbol": "jUSDT", "is_scam": false, "extra": {"decimals": "6"}}]}
      }
    }
    """#

    /// Two held jettons, for the paging rules with an injected page size of 2.
    static let pageOfTwo = #"""
    {
      "jetton_wallets": [
        {"address": "0:BB01000000000000000000000000000000000000000000000000000000000001", "balance": "5000000", "owner": "0:83DFD552E63729B472FCBCC8C45EBCC6691702558B68EC7527E1BA403A0F31A8", "jetton": "0:B113A994B5024A16719F69139328EB759596C38A25F59028B146FECDC3621DFE"},
        {"address": "0:BB01000000000000000000000000000000000000000000000000000000000002", "balance": "1000000000", "owner": "0:83DFD552E63729B472FCBCC8C45EBCC6691702558B68EC7527E1BA403A0F31A8", "jetton": "0:2F956143C461769579BAEF2E32CC2D7BC18283F40D20BB03E432CD603AC33FFC"}
      ],
      "metadata": {
        "0:2F956143C461769579BAEF2E32CC2D7BC18283F40D20BB03E432CD603AC33FFC": {"is_indexed": true, "token_info": [{"valid": true, "type": "jetton_masters", "name": "Notcoin", "symbol": "NOT", "extra": {"decimals": "9"}}]}
      }
    }
    """#

    /// One held jetton — a short page, which ends the walk.
    static let pageOfOne = #"""
    {
      "jetton_wallets": [
        {"address": "0:CC01000000000000000000000000000000000000000000000000000000000001", "balance": "250000000000", "owner": "0:83DFD552E63729B472FCBCC8C45EBCC6691702558B68EC7527E1BA403A0F31A8", "jetton": "0:AFC49CB8786F21C87045B19EDE78FC6B46C51048513F8E9A6D44060199C1BF0C"}
      ],
      "metadata": {
        "0:AFC49CB8786F21C87045B19EDE78FC6B46C51048513F8E9A6D44060199C1BF0C": {"is_indexed": true, "token_info": [{"valid": true, "type": "jetton_masters", "name": "Dogs", "symbol": "DOGS", "extra": {"decimals": "9"}}]}
      }
    }
    """#

    static let emptyPage = ##"{"jetton_wallets": [], "metadata": {}}"##

    /// A full page of somebody else's wallets. Nothing here survives the owner
    /// check, but the rows are all new, so the walk must continue past it.
    static let pageOfTwoForeignRows = #"""
    {
      "jetton_wallets": [
        {"address": "0:DD01000000000000000000000000000000000000000000000000000000000001", "balance": "5000000", "owner": "0:1111111111111111111111111111111111111111111111111111111111111111", "jetton": "0:B113A994B5024A16719F69139328EB759596C38A25F59028B146FECDC3621DFE"},
        {"address": "0:DD01000000000000000000000000000000000000000000000000000000000002", "balance": "1000000000", "owner": "0:1111111111111111111111111111111111111111111111111111111111111111", "jetton": "0:2F956143C461769579BAEF2E32CC2D7BC18283F40D20BB03E432CD603AC33FFC"}
      ],
      "metadata": {}
    }
    """#

    /// A master whose only indexer entry carries no `type` at all — the shape a
    /// Toncenter that stopped emitting the field would produce.
    static let pageWithUntypedMasterEntry = #"""
    {
      "jetton_wallets": [
        {"address": "0:EE01000000000000000000000000000000000000000000000000000000000001", "balance": "250000000000", "owner": "0:83DFD552E63729B472FCBCC8C45EBCC6691702558B68EC7527E1BA403A0F31A8", "jetton": "0:AFC49CB8786F21C87045B19EDE78FC6B46C51048513F8E9A6D44060199C1BF0C"}
      ],
      "metadata": {
        "0:AFC49CB8786F21C87045B19EDE78FC6B46C51048513F8E9A6D44060199C1BF0C": {"is_indexed": true, "token_info": [{"valid": true, "name": "Dogs", "symbol": "DOGS", "extra": {"decimals": "9", "_image_medium": "https://proxy.toncenter.com/dogs/pr:medium/abc"}}]}
      }
    }
    """#

    /// An untyped entry listed *ahead* of the real master entry for the same
    /// address, which is the ordering that makes preference — not mere
    /// acceptance — the thing under test.
    static let pageWithUntypedEntryBeforeMaster = #"""
    {
      "jetton_wallets": [
        {"address": "0:FF01000000000000000000000000000000000000000000000000000000000001", "balance": "250000000000", "owner": "0:83DFD552E63729B472FCBCC8C45EBCC6691702558B68EC7527E1BA403A0F31A8", "jetton": "0:AFC49CB8786F21C87045B19EDE78FC6B46C51048513F8E9A6D44060199C1BF0C"}
      ],
      "metadata": {
        "0:AFC49CB8786F21C87045B19EDE78FC6B46C51048513F8E9A6D44060199C1BF0C": {"is_indexed": true, "token_info": [{"valid": true, "extra": {"balance": "250000000000"}}, {"valid": true, "type": "jetton_masters", "name": "Dogs", "symbol": "DOGS", "extra": {"decimals": "9", "_image_medium": "https://proxy.toncenter.com/dogs/pr:medium/abc"}}]}
      }
    }
    """#

    /// Degraded Toncenter: no entry declares a `type` at all, and under the
    /// master's own key a balance-only wallet record is listed *before* the
    /// record that actually describes the jetton.
    static let pageWithUntypedWalletBeforeUntypedMaster = #"""
    {
      "jetton_wallets": [
        {"address": "0:1A01000000000000000000000000000000000000000000000000000000000001", "balance": "250000000000", "owner": "0:83DFD552E63729B472FCBCC8C45EBCC6691702558B68EC7527E1BA403A0F31A8", "jetton": "0:729C13B6DF2C07CBF0A06AB63D34AF454F3D320EC1BCD8FB5C6D24D0806A17C2"}
      ],
      "metadata": {
        "0:729C13B6DF2C07CBF0A06AB63D34AF454F3D320EC1BCD8FB5C6D24D0806A17C2": {"is_indexed": true, "token_info": [{"valid": true, "extra": {"balance": "250000000000"}}, {"valid": true, "name": "jUSDT", "symbol": "jUSDT", "extra": {"decimals": "6"}}]}
      }
    }
    """#

    // MARK: - Helpers

    static func store(
        script: [ScriptedJettonHTTPClient.Step],
        client: ScriptedJettonHTTPClient? = nil,
        ttl: TimeInterval = 3600,
        clock: ManualClock = ManualClock()
    ) -> (store: TonJettonRegistryStore, client: ScriptedJettonHTTPClient) {
        let httpClient = client ?? ScriptedJettonHTTPClient(script: script)
        let store = TonJettonRegistryStore(
            httpClient: httpClient,
            api: TonAssetsAPI(host: URL(string: "https://test.local")!),
            ttl: ttl,
            defaults: isolatedDefaults(),
            now: { clock.now }
        )
        return (store, httpClient)
    }

    /// A defaults suite with nothing in it, so chain-visibility gates are read
    /// from a known state instead of whatever the running machine has set.
    static func isolatedDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "TonJettonTests-\(UUID().uuidString)")!
        return suite
    }
}
