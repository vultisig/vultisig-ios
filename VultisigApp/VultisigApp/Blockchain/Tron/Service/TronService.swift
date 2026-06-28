//
//  TronService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 02/01/25.
//

import Foundation
import BigInt
import WalletCore

class TronService {

    static let shared = TronService()

    private let apiService: TronAPIService

    // Cache for chain parameters
    private var chainParametersCache: TronChainParametersResponse?

    // Constants from Android implementation
    private static let BYTES_PER_COIN_TX: Int64 = 300
    private static let BYTES_PER_CONTRACT_TX: Int64 = 345

    // Energy a TRC20 transfer consumes: ~65k when the recipient already holds the token,
    // ~130k when a new balance slot has to be written (approximated via account activation).
    private static let ENERGY_PER_TRC20_TRANSFER_ACTIVE: Int64 = 65_000
    private static let ENERGY_PER_TRC20_TRANSFER_INACTIVE: Int64 = 130_000

    // Fallback SUN-per-energy price used when chain parameters are unavailable.
    private static let DEFAULT_ENERGY_UNIT_PRICE_SUN: Int64 = 210

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.apiService = TronAPIService(httpClient: httpClient)
    }

    // MARK: - Broadcast

    func broadcastTransaction(jsonString: String) async -> Result<String, Error> {
        do {
            let txHash = try await apiService.broadcastTransaction(jsonString: jsonString)
            return .success(txHash)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Block Info

    func getBlockInfo(coin: Coin, to: String? = nil, memo: String? = nil, isSwap: Bool = false) async throws -> BlockChainSpecific {
        let response = try await apiService.getNowBlock()

        let currentTimestampMillis = UInt64(Date().timeIntervalSince1970 * 1000)
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        let oneHourMillis = Int64(60 * 60 * 1000)
        let expiration = nowMillis + oneHourMillis

        let calculatedFee = try await calculateTronFee(coin: coin, to: to, memo: memo)

        // For swaps a 0 fee means the estimate could not be derived, so fall back to the default.
        // For regular sends a 0 fee is legitimate (energy + bandwidth fully cover the transfer).
        let finalFee = (isSwap && calculatedFee == 0) ? coin.feeDefault.toBigInt() : calculatedFee
        let estimation = String(finalFee)

        return BlockChainSpecific.Tron(
            timestamp: currentTimestampMillis,
            expiration: UInt64(expiration),
            blockHeaderTimestamp: response.block_header?.raw_data?.timestamp ?? 0,
            blockHeaderNumber: response.block_header?.raw_data?.number ?? 0,
            blockHeaderVersion: UInt64(response.block_header?.raw_data?.version ?? 0),
            blockHeaderTxTrieRoot: response.block_header?.raw_data?.txTrieRoot ?? "",
            blockHeaderParentHash: response.block_header?.raw_data?.parentHash ?? "",
            blockHeaderWitnessAddress: response.block_header?.raw_data?.witness_address ?? "",
            gasFeeEstimation: UInt64(estimation) ?? 0
        )
    }

    // MARK: - Token Info

    func getTokenInfo(contractAddress: String) async throws -> (name: String, symbol: String, decimals: Int) {
        return try await apiService.getTokenInfo(contractAddress: contractAddress)
    }

    // MARK: - Balance

    func getBalance(coin: CoinMeta, address: String) async throws -> String {
        if coin.isNativeToken {
            return try await apiService.getNativeBalance(address: address)
        } else {
            let balance = try await apiService.getTRC20Balance(
                contractAddress: coin.contractAddress,
                walletAddress: address
            )
            return String(balance)
        }
    }

    // MARK: - Account Info

    func getAccount(address: String) async throws -> TronAccountResponse {
        return try await apiService.getAccount(address: address)
    }

    func getAccountResource(address: String) async throws -> TronAccountResourceResponse {
        return try await apiService.getAccountResource(address: address)
    }

    // MARK: - Private Helpers

    private func calculateTronFee(coin: Coin, to: String?, memo: String?) async throws -> BigInt {
        do {
            let memoFee = try await getTronFeeMemo(memo: memo)
            let activationFee = try await getTronInactiveDestinationFee(to: to)

            let transactionFee: BigInt
            if coin.isNativeToken {
                let accountResource = try await apiService.getAccountResource(address: coin.address)
                let availableBandwidth = accountResource.calculateAvailableBandwidth()

                transactionFee = try await getBandwidthFeeDiscount(
                    isNativeToken: true,
                    availableBandwidth: availableBandwidth
                )
            } else {
                let accountResource = try await apiService.getAccountResource(address: coin.address)
                let availableEnergy = max(0, accountResource.EnergyLimit - accountResource.EnergyUsed)
                let availableBandwidth = accountResource.calculateAvailableBandwidth()

                let isDestinationActive = try await checkIfAccountIsActive(address: to)
                let energyRequired = isDestinationActive
                    ? Self.ENERGY_PER_TRC20_TRANSFER_ACTIVE
                    : Self.ENERGY_PER_TRC20_TRANSFER_INACTIVE

                // Energy and bandwidth covered by staked/free resources cost no TRX; only the
                // shortfall is burned. A fully resourced transfer therefore estimates to zero.
                let chainParams = try await getCachedChainParameters()
                let energyShortfall = max(0, energyRequired - availableEnergy)
                let energyCost = BigInt(energyShortfall) * BigInt(chainParams.energyUnitPrice)

                let bandwidthCost = try await getBandwidthFeeDiscount(
                    isNativeToken: false,
                    availableBandwidth: availableBandwidth
                )

                transactionFee = energyCost + bandwidthCost
            }

            let totalFee = transactionFee + memoFee + activationFee
            return totalFee

        } catch {
            // Network failure: fall back to a fee_limit large enough to cover a typical TRC20
            // transfer's energy cost so the transaction can still broadcast.
            return BigInt(Self.ENERGY_PER_TRC20_TRANSFER_ACTIVE) * BigInt(Self.DEFAULT_ENERGY_UNIT_PRICE_SUN)
        }
    }

    private func checkIfAccountIsActive(address: String?) async throws -> Bool {
        guard let address = address, !address.isEmpty else {
            return true
        }

        do {
            let account = try await apiService.getAccount(address: address)
            return !account.address.isEmpty
        } catch {
            return false
        }
    }

    private func getCachedChainParameters() async throws -> TronChainParametersResponse {
        if let cached = chainParametersCache {
            return cached
        }

        let parameters = try await apiService.getChainParameters()
        chainParametersCache = parameters
        return parameters
    }

    private func getBandwidthFeeDiscount(isNativeToken: Bool, availableBandwidth: Int64) async throws -> BigInt {
        let feeBandwidthRequired = isNativeToken ? Self.BYTES_PER_COIN_TX : Self.BYTES_PER_CONTRACT_TX
        let chainParams = try await getCachedChainParameters()
        let bandwidthPrice = chainParams.bandwidthFeePrice

        // Bandwidth (free daily allowance + staked) covers the transaction size for both native
        // and TRC20 transfers; the byte cost is only burned as TRX when bandwidth is insufficient.
        return availableBandwidth >= feeBandwidthRequired
            ? BigInt.zero
            : BigInt(feeBandwidthRequired * bandwidthPrice)
    }

    private func getTronFeeMemo(memo: String?) async throws -> BigInt {
        guard let memo = memo, !memo.isEmpty else {
            return BigInt.zero
        }

        let chainParams = try await getCachedChainParameters()
        return BigInt(chainParams.memoFeeEstimate)
    }

    private func getTronInactiveDestinationFee(to: String?) async throws -> BigInt {
        guard let to = to, !to.isEmpty else {
            return BigInt.zero
        }

        let accountExists: Bool
        do {
            let account = try await apiService.getAccount(address: to)
            accountExists = !account.address.isEmpty
        } catch {
            accountExists = false
        }

        if accountExists {
            return BigInt.zero
        }

        let chainParams = try await getCachedChainParameters()
        let createAccountFee = BigInt(chainParams.createAccountFeeEstimate)
        let createAccountContractFee = BigInt(chainParams.createNewAccountFeeEstimateContract)

        return createAccountFee + createAccountContractFee
    }
}
