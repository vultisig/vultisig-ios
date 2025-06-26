import Foundation
public struct RuneBondNode: Identifiable {
    public var id: String { address }
    public let status: String
    public let address: String
    public let bond: Decimal
    

    public var shortAddress: String {
        guard address.count > 4 else { return address }
        return String(address.suffix(4))
    }
}

extension ThorchainService {
    
    // MARK: - Public Methods
    func fetchRuneBondedAmount(address: String, completion: @escaping (Decimal) -> Void) {
        fetchRuneBondNodes(address: address) { nodes in
            let totalBond = nodes.reduce(Decimal.zero) { $0 + $1.bond }
            completion(totalBond)
        }
    }
    

    func fetchRuneBondedAmount(address: String) async -> Decimal {
        let nodes = await fetchRuneBondNodes(address: address)
        return nodes.reduce(Decimal.zero) { $0 + $1.bond }
    }
    

    func fetchRuneBondNodes(address: String, completion: @escaping ([RuneBondNode]) -> Void) {
        let urlString = Endpoint.fetchRuneBondedAmount(address: address)
        guard let url = URL(string: urlString) else {
            completion([])
            return
        }
        
        let task = URLSession.shared.dataTask(with: URLRequest(url: url)) { data, _, error in
            guard let data = data, error == nil else {
                completion([])
                return
            }
            completion(self.parseRuneBondNodes(from: data))
        }
        
        task.resume()
    }
    

    func fetchRuneBondNodes(address: String) async -> [RuneBondNode] {
        let urlString = Endpoint.fetchRuneBondedAmount(address: address)
        guard let url = URL(string: urlString) else { return [] }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return parseRuneBondNodes(from: data)
        } catch {
            print("Error fetching bonded nodes: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - Private Helpers
    private func parseRuneBondedAmount(from data: Data) -> Decimal {
        let nodes = parseRuneBondNodes(from: data)
        return nodes.reduce(Decimal.zero) { $0 + $1.bond }
    }
    

    private func parseRuneBondNodes(from data: Data) -> [RuneBondNode] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nodes = json["nodes"] as? [[String: Any]] else {
            return []
        }
        
        var bondNodes: [RuneBondNode] = []
        
        for node in nodes {
            guard let address = node["address"] as? String,
                  let bondStr = node["bond"] as? String,
                  let bondInt = UInt64(bondStr),
                  let status = node["status"] as? String else {
                continue
            }
            
            let bondNode = RuneBondNode(
                status: status,
                address: address,
                bond: Decimal(bondInt)
            )
            
            bondNodes.append(bondNode)
        }
        
        return bondNodes
    }
}
