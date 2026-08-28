//
//  CosmosIBCTransferMemoTests.swift
//  VultisigAppTests
//
//  The IBC routing codec, and the byte-parity claim that lets it replace inline
//  colon arithmetic on a signing path.
//
//  Two separate obligations are pinned here:
//
//  1. **Nothing that worked changed.** For a transfer with no user memo, and one
//     whose memo contains no colon, `CosmosHelperStruct.getPreSignedInputData`
//     must produce bytes identical to what the previous parse produced. The
//     previous parse is re-implemented below (`legacySourceChannelAndMemo`) and
//     the two signing inputs are compared as raw `Data`, so this is a real
//     producer/consumer parity proof rather than an assertion about the fields
//     the new code happens to set.
//  2. **The broken case is fixed.** A memo containing one colon, several
//     colons, or a JSON payload now reaches the signed transaction intact. Each
//     of those previously signed with an EMPTY memo — the transfer settled and
//     the crediting did not.
//
//  The committed golden `cosmos_osmosis_ibc_transfer_to_gaia` in
//  `SigningGoldenVectors.json` covers (1) independently and from the other
//  direction: it was recorded before this change and is not re-recorded.
//

@testable import VultisigApp
import BigInt
import VultisigCommonData
import WalletCore
import XCTest

final class CosmosIBCTransferMemoTests: XCTestCase {

    private static let destinationAddress = "cosmos1xyzfixturegaiachainvaultaddress000000000"
    private static let channel = "channel-0"
    private static let chainName = "Cosmos"

    // MARK: - Codec

    func testPackedShapeMatchesTheLegacyEncodingWithoutAMemo() {
        let memo = CosmosIBCTransferMemo(
            destinationChainName: Self.chainName,
            sourceChannel: Self.channel,
            destinationAddress: Self.destinationAddress
        )
        XCTAssertEqual(memo.packed, "Cosmos:channel-0:\(Self.destinationAddress)")
    }

    func testPackedShapeAppendsTheUserMemoOnlyWhenPresent() {
        let withMemo = CosmosIBCTransferMemo(
            destinationChainName: Self.chainName,
            sourceChannel: Self.channel,
            destinationAddress: Self.destinationAddress,
            userMemo: "hello-ibc"
        )
        XCTAssertEqual(withMemo.packed, "Cosmos:channel-0:\(Self.destinationAddress):hello-ibc")

        let withEmptyMemo = CosmosIBCTransferMemo(
            destinationChainName: Self.chainName,
            sourceChannel: Self.channel,
            destinationAddress: Self.destinationAddress,
            userMemo: .empty
        )
        XCTAssertFalse(withEmptyMemo.packed.hasSuffix(":"), "An absent memo must not leave a trailing separator")
    }

    func testRoundTripsEveryMemoShape() {
        let memos = [
            "",
            "hello-ibc",
            "deposit:12345",
            "route:osmosis:swap:atom",
            #"{"wasm":{"contract":"osmo1abc","msg":{"swap":{"min":"1:2"}}}}"#
        ]

        for userMemo in memos {
            let original = CosmosIBCTransferMemo(
                destinationChainName: Self.chainName,
                sourceChannel: Self.channel,
                destinationAddress: Self.destinationAddress,
                userMemo: userMemo
            )
            XCTAssertEqual(
                CosmosIBCTransferMemo(packed: original.packed),
                original,
                "Memo \(userMemo.isEmpty ? "<empty>" : userMemo) must survive the round trip"
            )
        }
    }

    /// The defect this migration exists for: the old parse split on every colon
    /// and copied the memo only at a component count of exactly four.
    func testAMemoContainingColonsSurvivesDecoding() {
        let cases: [(name: String, memo: String)] = [
            ("one colon", "deposit:12345"),
            ("several colons", "a:b:c:d:e"),
            ("json payload", #"{"forward":{"receiver":"osmo1abc","port":"transfer:0"}}"#),
            ("trailing colon", "tag:")
        ]

        for (name, userMemo) in cases {
            guard let decoded = CosmosIBCTransferMemo(
                packed: "Cosmos:channel-0:\(Self.destinationAddress):\(userMemo)"
            ) else {
                return XCTFail("\(name) must decode")
            }
            XCTAssertEqual(decoded.userMemo, userMemo, "\(name) must arrive intact")
            XCTAssertEqual(decoded.sourceChannel, Self.channel, "\(name) must not disturb the channel")
            XCTAssertEqual(decoded.destinationAddress, Self.destinationAddress)
        }
    }

    /// The old code read `splitedMemo[1]` on the split result, which *traps* —
    /// not returns nil — when the memo has fewer than two components. A peer can
    /// put any memo on a payload it marks `.ibcTransfer`, so this had to become
    /// a refusal rather than a crash.
    func testAMemoTooShortToBeRoutingDataIsRefused() {
        for packed in ["", "hello", "Cosmos:channel-0"] {
            XCTAssertNil(
                CosmosIBCTransferMemo(packed: packed),
                "\(packed.isEmpty ? "<empty>" : packed) cannot describe a transfer and must be refused, not indexed"
            )
        }
    }

    /// An empty channel means the app found no route. Signing anyway produced a
    /// transfer the chain could only reject — and, because empty components were
    /// dropped, one whose channel was actually the destination address.
    func testAnEmptyChannelIsRefused() {
        XCTAssertNil(CosmosIBCTransferMemo(packed: "Cosmos::\(Self.destinationAddress)"))
        XCTAssertNil(CosmosIBCTransferMemo(packed: "Cosmos::\(Self.destinationAddress):memo"))
    }

    func testAnEmptyDestinationChainNameStillDecodes() {
        // Not something the form produces, but it is not the signer's business
        // to reject: the chain name is display data and the channel is what is
        // signed.
        let decoded = CosmosIBCTransferMemo(packed: ":channel-0:\(Self.destinationAddress)")
        XCTAssertEqual(decoded?.sourceChannel, Self.channel)
        XCTAssertEqual(decoded?.destinationChainName, .empty)
    }

    // MARK: - Byte parity against the previous parse

    /// The parse this replaces, reproduced exactly, minus the out-of-bounds
    /// subscript (which would trap the test runner rather than fail a case).
    /// Returns nil where the old code would have crashed.
    private func legacySourceChannelAndMemo(_ packed: String) -> (channel: String, memo: String)? {
        let split = packed.split(separator: ":")
        guard split.count >= 2 else { return nil }
        return (String(split[1]), split.count == 4 ? String(split[3]) : "")
    }

    /// Builds the signing input the way the signer does, but with the channel
    /// and memo supplied — i.e. the old algorithm's output fed through the same
    /// message construction. Any difference between this and
    /// `getPreSignedInputData` is a byte change on the signing path.
    private func referenceSigningInput(
        payload: KeysignPayload,
        channel: String,
        memo: String,
        config: CosmosHelperConfig
    ) throws -> Data {
        guard case .Cosmos(let accountNumber, let sequence, let gas, _, let ibcDenomTrace, _) = payload.chainSpecific else {
            throw HelperError.runtimeError("expected Cosmos chain specific")
        }
        guard let pubKeyData = Data(hexString: payload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("invalid hex public key")
        }

        let timeouts = ibcDenomTrace?.height?.split(separator: "_") ?? []
        let timeout = UInt64(timeouts.last ?? "0") ?? 0

        let transferMessage = WalletCore.CosmosMessage.Transfer.with {
            $0.sourcePort = "transfer"
            $0.sourceChannel = channel
            $0.sender = payload.coin.address
            $0.receiver = payload.toAddress
            $0.token = CosmosAmount.with {
                $0.denom = payload.coin.isNativeToken ? config.denom : payload.coin.contractAddress
                $0.amount = String(payload.toAmount)
            }
            $0.timeoutHeight = CosmosHeight.with {
                $0.revisionNumber = 0
                $0.revisionHeight = 0
            }
            $0.timeoutTimestamp = timeout
        }

        let helper = CosmosHelperStruct(config: config)
        return try CosmosSigningInput.with {
            $0.publicKey = pubKeyData
            $0.signingMode = helper.getSigningMode(keysignPayload: payload)
            $0.chainID = config.coinType.chainId
            $0.accountNumber = accountNumber
            $0.sequence = sequence
            $0.mode = .sync
            if !memo.isEmpty {
                $0.memo = memo
            }
            $0.messages = [WalletCore.CosmosMessage.with { $0.transferTokensMessage = transferMessage }]
            $0.fee = WalletCore.CosmosFee.with {
                $0.gas = config.gasLimit
                $0.amounts = [CosmosAmount.with {
                    $0.denom = config.denom
                    $0.amount = String(gas)
                }]
            }
        }.serializedData()
    }

    private func makeCoin(chain: Chain, ticker: String, decimals: Int) -> Coin {
        let meta = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: ticker.lowercased(),
            decimals: decimals,
            priceProviderId: "",
            contractAddress: "",
            isNativeToken: true
        )
        let hexPublicKey = "02" + String(repeating: "0", count: 64)
        return Coin(asset: meta, address: "\(chain.rawValue)1from", hexPublicKey: hexPublicKey)
    }

    private func makePayload(coin: Coin, memo: String) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: Self.destinationAddress,
            toAmount: BigInt(1_000_000),
            chainSpecific: .Cosmos(
                accountNumber: 7,
                sequence: 3,
                gas: 200_000,
                transactionType: VSTransactionType.ibcTransfer.rawValue,
                ibcDenomTrace: CosmosIbcDenomTraceDenomTrace(
                    path: "",
                    baseDenom: "",
                    height: "32597414_1753579499419760896"
                ),
                gasLimit: nil
            ),
            utxos: [],
            memo: memo,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
        )
    }

    private func signedBytes(for payload: KeysignPayload, chain: Chain) throws -> Data {
        let helper = CosmosHelperStruct(config: try CosmosHelperConfig.getConfig(forChain: chain))
        return try helper.getPreSignedInputData(keysignPayload: payload)
    }

    /// The claim the migration rests on: a transfer with no user memo signs the
    /// exact same bytes it signed before.
    func testNoUserMemoSignsIdenticalBytes() throws {
        let chain = Chain.osmosis
        let coin = makeCoin(chain: chain, ticker: "OSMO", decimals: 6)
        let packed = "Cosmos:channel-0:\(Self.destinationAddress)"
        let payload = makePayload(coin: coin, memo: packed)

        guard let legacy = legacySourceChannelAndMemo(packed) else {
            return XCTFail("Fixture must be parseable by the previous algorithm")
        }
        XCTAssertEqual(legacy.channel, Self.channel)
        XCTAssertEqual(legacy.memo, .empty)

        let reference = try referenceSigningInput(
            payload: payload,
            channel: legacy.channel,
            memo: legacy.memo,
            config: try CosmosHelperConfig.getConfig(forChain: chain)
        )

        XCTAssertEqual(
            try signedBytes(for: payload, chain: chain),
            reference,
            "A transfer with no memo must sign byte-identically to the previous parse"
        )
    }

    /// The other unaffected case: a memo the old parse could already carry.
    func testColonFreeUserMemoSignsIdenticalBytes() throws {
        let chain = Chain.osmosis
        let coin = makeCoin(chain: chain, ticker: "OSMO", decimals: 6)
        let packed = "Cosmos:channel-0:\(Self.destinationAddress):hello-ibc"
        let payload = makePayload(coin: coin, memo: packed)

        guard let legacy = legacySourceChannelAndMemo(packed) else {
            return XCTFail("Fixture must be parseable by the previous algorithm")
        }
        XCTAssertEqual(legacy.memo, "hello-ibc", "The previous parse did carry a colon-free memo")

        let reference = try referenceSigningInput(
            payload: payload,
            channel: legacy.channel,
            memo: legacy.memo,
            config: try CosmosHelperConfig.getConfig(forChain: chain)
        )

        XCTAssertEqual(
            try signedBytes(for: payload, chain: chain),
            reference,
            "A colon-free memo must sign byte-identically to the previous parse"
        )
    }

    /// Same parity claim across all three chains the operation is offered on,
    /// since each has its own `CosmosHelperConfig` (denom, gas limit, chain id).
    func testParityHoldsOnEveryChainThatOffersIbc() throws {
        let fixtures: [(chain: Chain, ticker: String, decimals: Int)] = [
            (.gaiaChain, "ATOM", 6),
            (.osmosis, "OSMO", 6)
        ]

        for fixture in fixtures {
            let coin = makeCoin(chain: fixture.chain, ticker: fixture.ticker, decimals: fixture.decimals)
            let config = try CosmosHelperConfig.getConfig(forChain: fixture.chain)

            for packed in [
                "Cosmos:channel-0:\(Self.destinationAddress)",
                "Cosmos:channel-0:\(Self.destinationAddress):plain-memo"
            ] {
                let payload = makePayload(coin: coin, memo: packed)
                guard let legacy = legacySourceChannelAndMemo(packed) else {
                    return XCTFail("Fixture must be parseable by the previous algorithm")
                }

                XCTAssertEqual(
                    try signedBytes(for: payload, chain: fixture.chain),
                    try referenceSigningInput(
                        payload: payload,
                        channel: legacy.channel,
                        memo: legacy.memo,
                        config: config
                    ),
                    "\(fixture.chain.rawValue) must sign byte-identically for \(packed)"
                )
            }
        }
    }

    // MARK: - The fix, at the signing boundary

    func testAColonMemoNowReachesTheSignedTransaction() throws {
        let chain = Chain.osmosis
        let coin = makeCoin(chain: chain, ticker: "OSMO", decimals: 6)

        let userMemos = [
            "deposit:12345",
            "a:b:c:d",
            #"{"forward":{"receiver":"osmo1abc","channel":"channel-0"}}"#
        ]

        for userMemo in userMemos {
            let packed = "Cosmos:channel-0:\(Self.destinationAddress):\(userMemo)"
            let payload = makePayload(coin: coin, memo: packed)
            let input = try CosmosSigningInput(serializedBytes: try signedBytes(for: payload, chain: chain))

            XCTAssertEqual(input.memo, userMemo, "\(userMemo) must be signed, not dropped")
            XCTAssertEqual(
                input.messages.first?.transferTokensMessage.sourceChannel,
                Self.channel,
                "Recovering the memo must not disturb the channel"
            )

            // And the thing that made it a fund bug: the previous parse signed
            // an empty memo for exactly these inputs.
            let legacy = legacySourceChannelAndMemo(packed)
            XCTAssertEqual(legacy?.memo, .empty, "Fixture must be one the previous parse dropped")
        }
    }

    /// The channel is no longer read positionally out of a split, so it must be
    /// pinned explicitly: a memo with colons must not shift it.
    func testTheChannelIsResolvedFromTheChannelFieldNotByPosition() throws {
        let chain = Chain.gaiaChain
        let coin = makeCoin(chain: chain, ticker: "ATOM", decimals: 6)
        let payload = makePayload(
            coin: coin,
            memo: "Cosmos:channel-118:\(Self.destinationAddress):route:channel-999:swap"
        )

        let input = try CosmosSigningInput(serializedBytes: try signedBytes(for: payload, chain: chain))
        XCTAssertEqual(input.messages.first?.transferTokensMessage.sourceChannel, "channel-118")
        XCTAssertEqual(input.memo, "route:channel-999:swap")
    }

    func testAnUnparseableMemoThrowsInsteadOfSigning() {
        let coin = makeCoin(chain: .osmosis, ticker: "OSMO", decimals: 6)
        for memo in ["", "not-routing-data", "Cosmos:channel-0"] {
            XCTAssertThrowsError(
                try signedBytes(for: makePayload(coin: coin, memo: memo), chain: .osmosis),
                "\(memo.isEmpty ? "<empty>" : memo) must fail closed"
            )
        }
    }
}
