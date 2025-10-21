//
//  THORChainAPIService+Bonds.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation

extension THORChainAPIService {
    func getNodes() async throws -> [String] {
        let response = try await httpClient.request(THORChainBondsAPI.getNodes, responseType: [THORChainNodesResponse].self)
        return response.data.map(\.nodeAddress)
    }
    
    func getBondedNodes(address: String) async throws -> BondedNodes {
        do {
            let response = try await httpClient.request(THORChainBondsAPI.getBondedNodes(address: address), responseType: BondedNodesResponse.self)
            let nodes: [RuneBondNode] = response.data.nodes.compactMap { node in
                guard let amount = Decimal(string: node.bond) else {
                    return nil
                }
                
                return RuneBondNode(status: node.status, address: node.address, bond: amount)
            }
            return BondedNodes(totalBonded: Decimal(string: response.data.totalBonded) ?? .zero, nodes: nodes)
        } catch {
            throw THORChainAPIError.invalidResponse
        }
    }
}
