//
//  TonstakersBodyBuilder.swift
//  VultisigApp
//

import Foundation

/// Builds the message-body BOCs (base64) for the two Tonstakers operations.
/// Both are routed through the TonConnect `customPayload` signing path as the
/// `payload` of a `TonMessage` (so both MPC devices sign the identical body).
enum TonstakersBodyBuilder {

    /// Deposit body: `tonstakers_pool_deposit#47d54391 query_id:uint64`.
    ///
    /// For `query_id == 0` this is the verified constant BOC, so we return it
    /// directly (and assert the encoder reproduces it in tests). Non-zero query
    /// ids go through the cell builder. Sent to the pool with the staked TON as
    /// the message value.
    static func depositBody(queryId: UInt64 = 0) throws -> String {
        if queryId == 0 {
            return Self.depositConstantBase64
        }
        let builder = TonCellBuilder()
        try builder.storeUInt(UInt64(TonOpcode.tonstakersDeposit), bits: 32)
        try builder.storeUInt(queryId, bits: 64)
        return try builder.toBocBase64()
    }

    /// Burn body: TEP-74 `jetton_burn#595f07bc query_id:uint64
    /// amount:(VarUInteger 16) response_destination:MsgAddress
    /// custom_payload:(Maybe ^Cell)`.
    ///
    /// `amount` is the tsTON jetton amount to burn (base units, decimal string).
    /// `responseAddress` is the user's own wallet (raw or friendly form) — where
    /// the pool returns excess gas. No custom payload. Sent to the user's tsTON
    /// jetton wallet.
    static func burnBody(amount: String, responseAddress: String, queryId: UInt64 = 0) throws -> String {
        let builder = TonCellBuilder()
        try builder.storeUInt(UInt64(TonOpcode.jettonBurn), bits: 32)
        try builder.storeUInt(queryId, bits: 64)
        try builder.storeCoins(amount)
        try builder.storeAddress(rawAddress: responseAddress)
        try builder.storeBit(false) // custom_payload: Maybe ^Cell = nothing
        return try builder.toBocBase64()
    }

    /// The verified deposit constant for `query_id = 0`
    /// (`b5ee9c72…47d543910000000000000000`), base64-encoded. Decodes to op
    /// `0x47d54391` + 64-bit query id `0`.
    static let depositConstantBase64 = "te6ccgEBAQEADgAAGEfVQ5EAAAAAAAAAAA=="
}
