//
//  MemoDecodingService.swift
//  VultisigApp
//

import Foundation
import BigInt

struct ParsedMemoParams {
    let functionSignature: String
    let functionArguments: String
}

struct MemoDecodingService {

    static let shared = MemoDecodingService()

    func decode(memo: String) async throws -> String? {
        // Legacy support or simple string return
        guard let info = try await FourByteRepository.shared.decode(memo: memo) else {
            return nil
        }
        return info.functionName
    }
    
    /// Comprehensive memo parsing using FourByteRepository
    func getParsedMemo(memo: String?) async -> ParsedMemoParams? {
        guard let memo = memo, !memo.isEmpty, memo != "0x" else {
            return nil
        }
        
        do {
            guard let info = try await FourByteRepository.shared.decode(memo: memo) else {
                return nil
            }
            
            return ParsedMemoParams(
                functionSignature: info.fullSignature,
                functionArguments: info.encodedArguments
            )
            
        } catch {
            return nil
        }
    }
}
