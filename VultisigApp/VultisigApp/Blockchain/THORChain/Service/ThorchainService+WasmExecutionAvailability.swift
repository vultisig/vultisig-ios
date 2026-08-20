//
//  ThorchainService+WasmExecutionAvailability.swift
//  VultisigApp
//

import Foundation
import OSLog

enum THORChainWasmExecutionAvailability: Equatable, Sendable {
    case available
    case halted
    case unavailable
}

protocol THORChainWasmExecutionAvailabilityProviding {
    func fetchWasmExecutionAvailabilities(
        for contractAddresses: Set<String>
    ) async -> [String: THORChainWasmExecutionAvailability]
}

extension ThorchainService: THORChainWasmExecutionAvailabilityProviding {
    /// Mirrors `WasmMgr.ExecuteContract` in thornode: global WASM, contract-address suffix,
    /// then code-checksum halts. Deployer halts intentionally do not participate here; thornode
    /// applies those only when storing or instantiating code, not when executing an existing app.
    func fetchWasmExecutionAvailabilities(
        for contractAddresses: Set<String>
    ) async -> [String: THORChainWasmExecutionAvailability] {
        guard !contractAddresses.isEmpty else { return [:] }

        let currentHeight: Int64
        let globalHaltHeight: Int64
        do {
            async let height = fetchWasmPolicyBlockHeight()
            async let globalHalt = fetchWasmMimirHeight(key: Self.wasmGlobalHaltMimirKey)
            (currentHeight, globalHaltHeight) = try await (height, globalHalt)
        } catch {
            logger.warning("Could not verify THORChain global WASM availability: \(error.localizedDescription)")
            return contractAddresses.reduce(into: [:]) { result, address in
                result[address] = .unavailable
            }
        }

        if Self.isWasmHaltActive(globalHaltHeight, at: currentHeight) {
            return contractAddresses.reduce(into: [:]) { result, address in
                result[address] = .halted
            }
        }

        return await withTaskGroup(
            of: (String, THORChainWasmExecutionAvailability).self,
            returning: [String: THORChainWasmExecutionAvailability].self
        ) { group in
            for address in contractAddresses {
                group.addTask {
                    do {
                        let availability = try await self.fetchWasmContractExecutionAvailability(
                            address: address,
                            currentHeight: currentHeight
                        )
                        return (address, availability)
                    } catch {
                        self.logger.warning(
                            "Could not verify THORChain WASM availability for \(address, privacy: .private): \(error.localizedDescription)"
                        )
                        return (address, .unavailable)
                    }
                }
            }

            var result: [String: THORChainWasmExecutionAvailability] = [:]
            for await (address, availability) in group {
                result[address] = availability
            }
            return result
        }
    }
}

extension ThorchainService {
    static let wasmGlobalHaltMimirKey = "HaltWasmGlobal"

    static func wasmContractHaltMimirKey(address: String) -> String? {
        guard address.count >= 6 else { return nil }
        return "HaltWasmContract-\(address.suffix(6))"
    }

    static func wasmChecksumHaltMimirKey(dataHash: String) -> String? {
        guard let checksum = Data(hexString: dataHash), checksum.count == 32 else { return nil }
        return "HaltWasmCs-\(base32MimirReference(checksum))"
    }

    static func isWasmHaltActive(_ haltHeight: Int64, at currentHeight: Int64) -> Bool {
        haltHeight > 0 && currentHeight > haltHeight
    }

    static func parseWasmMimirHeight(_ data: Data) -> Int64? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        return Int64(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// RFC 4648 base32 without trailing `=` padding. THORNode derives checksum Mimir keys with
    /// Go's `base32.StdEncoding` and trims that padding to fit the 64-character Mimir key limit.
    static func base32MimirReference(_ data: Data) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var accumulator = 0
        var bitCount = 0
        var output = ""

        for byte in data {
            accumulator = (accumulator << 8) | Int(byte)
            bitCount += 8
            while bitCount >= 5 {
                bitCount -= 5
                output.append(alphabet[(accumulator >> bitCount) & 0x1F])
            }
            accumulator &= (1 << bitCount) - 1
        }

        if bitCount > 0 {
            output.append(alphabet[(accumulator << (5 - bitCount)) & 0x1F])
        }
        return output
    }
}

private extension ThorchainService {
    enum WasmAvailabilityError: Error {
        case invalidBlockHeight
        case invalidContractAddress
        case invalidDataHash
        case invalidMimir
    }

    struct WasmContractInfoResponse: Decodable {
        struct ContractInfo: Decodable {
            let codeID: String

            enum CodingKeys: String, CodingKey {
                case codeID = "code_id"
            }
        }

        let contractInfo: ContractInfo

        enum CodingKeys: String, CodingKey {
            case contractInfo = "contract_info"
        }
    }

    struct WasmCodeInfoResponse: Decodable {
        struct CodeInfo: Decodable {
            let dataHash: String

            enum CodingKeys: String, CodingKey {
                case dataHash = "data_hash"
            }
        }

        let codeInfo: CodeInfo

        enum CodingKeys: String, CodingKey {
            case codeInfo = "code_info"
        }
    }

    func fetchWasmContractExecutionAvailability(
        address: String,
        currentHeight: Int64
    ) async throws -> THORChainWasmExecutionAvailability {
        guard let contractMimirKey = Self.wasmContractHaltMimirKey(address: address) else {
            throw WasmAvailabilityError.invalidContractAddress
        }

        async let contractHalt = fetchWasmMimirHeight(key: contractMimirKey)
        let contractInfoResponse = try await httpClient.request(
            mainnet(.wasmContractInfo(address: address)),
            responseType: WasmContractInfoResponse.self
        )
        let codeInfoResponse = try await httpClient.request(
            mainnet(.wasmCodeInfo(codeID: contractInfoResponse.data.contractInfo.codeID)),
            responseType: WasmCodeInfoResponse.self
        )
        guard let checksumMimirKey = Self.wasmChecksumHaltMimirKey(
            dataHash: codeInfoResponse.data.codeInfo.dataHash
        ) else {
            throw WasmAvailabilityError.invalidDataHash
        }

        async let checksumHalt = fetchWasmMimirHeight(key: checksumMimirKey)
        let (contractHaltHeight, checksumHaltHeight) = try await (contractHalt, checksumHalt)
        let halted = Self.isWasmHaltActive(contractHaltHeight, at: currentHeight) ||
            Self.isWasmHaltActive(checksumHaltHeight, at: currentHeight)
        return halted ? .halted : .available
    }

    func fetchWasmPolicyBlockHeight() async throws -> Int64 {
        let response = try await httpClient.request(
            mainnet(.lastBlock),
            responseType: [LastBlockResponse].self
        )
        guard let height = response.data.first?.thorchain,
              let blockHeight = Int64(exactly: height) else {
            throw WasmAvailabilityError.invalidBlockHeight
        }
        return blockHeight
    }

    func fetchWasmMimirHeight(key: String) async throws -> Int64 {
        let response = try await httpClient.request(mainnet(.mimir(key: key)))
        guard let height = Self.parseWasmMimirHeight(response.data) else {
            throw WasmAvailabilityError.invalidMimir
        }
        return height
    }
}
