//
//  CosmosIBCTransferMemo.swift
//  VultisigApp
//
//  The wire encoding of an IBC transfer's routing data, as a typed value.
//
//  An IBC transfer needs a source channel that the transaction itself has
//  nowhere to put: `CosmosSpecific` — the proto every co-signing device
//  rebuilds its payload from — carries an account number, a sequence, gas, a
//  transaction type, a denom trace and a gas limit, and no channel. Peers do
//  not blind-sign; each one runs the signing path against its own reconstructed
//  payload, so anything the initiator does not put on the wire the peer cannot
//  see. The channel has therefore always travelled inside `memo`, packed with
//  the destination chain and address:
//
//      <destinationChainName>:<sourceChannel>:<destinationAddress>[:<userMemo>]
//
//  This type is the only writer and the only reader of that string. Everything
//  above it — the form, the view-model, the builder — carries the four values
//  as separate typed fields, and the signer asks here instead of doing colon
//  arithmetic inline.
//
//  What that buys, concretely: the decode is *bounded*. Splitting on every
//  colon and taking the user memo only at a component count of exactly four
//  meant any memo containing a colon — a JSON forwarding payload, an exchange
//  deposit tag — signed with an empty memo. The transfer settled and the
//  crediting did not. `maxSplits: 3` makes the fourth component the entire
//  remainder, colons and all.
//

import Foundation

struct CosmosIBCTransferMemo: Equatable {
    /// Display name of the chain the transfer lands on. Carried for the verify
    /// screen and the history entry; the signing path does not read it.
    let destinationChainName: String
    /// The IBC channel on the *source* chain. This is the field the signing
    /// path exists to recover, and the one value here that changes what is
    /// signed.
    let sourceChannel: String
    /// The receiving address on the destination chain. Also carried on the
    /// payload's `toAddress`, which is what the transfer message actually
    /// reads — this copy is what makes the packed string self-describing.
    let destinationAddress: String
    /// The user's own memo, forwarded to the destination untouched. Empty when
    /// the user did not write one.
    let userMemo: String

    init(
        destinationChainName: String,
        sourceChannel: String,
        destinationAddress: String,
        userMemo: String = .empty
    ) {
        self.destinationChainName = destinationChainName
        self.sourceChannel = sourceChannel
        self.destinationAddress = destinationAddress
        self.userMemo = userMemo
    }

    /// The wire string. The trailing segment is appended only when the user
    /// wrote a memo, so a transfer without one is byte-identical to what the
    /// legacy form produced.
    var packed: String {
        let routing = "\(destinationChainName)\(Self.separator)\(sourceChannel)\(Self.separator)\(destinationAddress)"
        guard userMemo.isNotEmpty else { return routing }
        return routing + Self.separator + userMemo
    }

    /// Reads the wire string back, or `nil` when it cannot describe a signable
    /// transfer.
    ///
    /// Bounded at three splits: whatever follows the third colon is one user
    /// memo, however many colons it contains. Empty subsequences are kept so a
    /// missing field reads as missing rather than shifting every later field
    /// left — the old parse read an absent channel as the destination address
    /// and signed against it.
    ///
    /// Rejects rather than guesses:
    /// - fewer than three components. The old code indexed `[1]` on the split
    ///   result, which *traps* on a shorter memo. That is reachable from a
    ///   peer-supplied payload, not only from our own form, so the failure has
    ///   to be a thrown error on the signing path and not a crash.
    /// - an empty channel. There is no channel to transfer over; the signed
    ///   message could only ever be rejected by the chain.
    init?(packed: String) {
        let components = packed.split(
            separator: Self.separatorCharacter,
            maxSplits: 3,
            omittingEmptySubsequences: false
        )

        guard components.count >= 3 else { return nil }

        let channel = String(components[1])
        guard channel.isNotEmpty else { return nil }

        self.init(
            destinationChainName: String(components[0]),
            sourceChannel: channel,
            destinationAddress: String(components[2]),
            userMemo: components.count == 4 ? String(components[3]) : .empty
        )
    }

    private static let separator = ":"
    private static let separatorCharacter: Character = ":"
}
