//
//  TonService+Models.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 29/08/25.
//

struct JettonWalletsResponse: Codable {
    let jetton_wallets: [JettonWalletInfo]
}

struct JettonWalletInfo: Codable {
    let address: String
    let balance: String
    let owner: String  // Raw address string, not a dictionary
    let jetton: String // Raw address string, not a dictionary
    let last_transaction_lt: String?
    let code_hash: String?
    let data_hash: String?
}

struct RunGetMethodResponse: Codable {
    let ok: Bool
    let result: RunGetMethodResult?
    let error: String?
}

struct RunGetMethodResult: Codable {
    let stack: [StackItem]?
    let gas_used: Int64?
    let exit_code: Int?
}

struct StackItem: Codable {
    let type: String?
    let value: StackValue?
    let boc: String?

    private enum CodingKeys: String, CodingKey {
        case type, value, boc
    }
}

struct StackValue: Codable {
    let bytes: String?
    let b64: String?
    let boc: String?

    private enum CodingKeys: String, CodingKey {
        case bytes, b64, boc
    }
}

struct ApiResponse<T: Codable>: Codable {
    let ok: Bool
    let result: T?
    let error: String?
    let code: Int?
}

struct TonBroadcastSuccessResponse: Codable {
    let hash: String
}

// MARK: - Flexible models for runGetMethod (handles array- and object-shaped stack entries)

struct RunGetMethodFlexibleResponse: Codable {
    let ok: Bool?
    let result: RunGetMethodFlexibleResult?
    let error: String?
}

struct RunGetMethodFlexibleResult: Codable {
    let stack: [FlexibleStackEntry]?
    let gas_used: Int64?
    let exit_code: Int?
}

enum FlexibleStackEntry: Codable {
    case object(StackItem)
    case array(FlexibleArrayEntry)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let obj = try? container.decode(StackItem.self) {
            self = .object(obj)
            return
        }
        if let arr = try? container.decode(FlexibleArrayEntry.self) {
            self = .array(arr)
            return
        }
        // Fallback to an empty object-shaped entry when type is unknown
        self = .object(StackItem(type: nil, value: nil, boc: nil))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let obj):
            try container.encode(obj)
        case .array(let arr):
            try container.encode(arr)
        }
    }
}

struct FlexibleArrayEntry: Codable {
    let type: String?
    let value: FlexibleValue?

    init(type: String?, value: FlexibleValue?) {
        self.type = type
        self.value = value
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()

        var decodedType: String? = nil
        var decodedValue: FlexibleValue? = nil

        // First element is usually the type string, but keep it optional
        if let t = try? container.decode(String.self) {
            decodedType = t
        } else if let dict = try? container.decode([String: String].self) {
            decodedType = dict["type"]
        } else {
            _ = try? container.decode(EmptyCodable.self)
        }

        // Second element can be a string or an object with bytes/b64/boc
        if let v = try? container.decode(FlexibleValue.self) {
            decodedValue = v
        } else if let s = try? container.decode(String.self) {
            decodedValue = FlexibleValue(bytes: s, b64: nil, boc: nil)
        } else if let dict = try? container.decode([String: String].self) {
            decodedValue = FlexibleValue(bytes: dict["bytes"], b64: dict["b64"], boc: dict["boc"])
        }

        self.type = decodedType
        self.value = decodedValue
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(type)
        try container.encode(value)
    }
}

struct FlexibleValue: Codable {
    let bytes: String?
    let b64: String?
    let boc: String?

    init(bytes: String?, b64: String?, boc: String?) {
        self.bytes = bytes
        self.b64 = b64
        self.boc = boc
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self.bytes = s
            self.b64 = nil
            self.boc = nil
            return
        }
        if let val = try? container.decode(StackValue.self) {
            self.bytes = val.bytes
            self.b64 = val.b64
            self.boc = val.boc
            return
        }
        if let dict = try? container.decode([String: String].self) {
            self.bytes = dict["bytes"]
            self.b64 = dict["b64"]
            self.boc = dict["boc"]
            return
        }
        self.bytes = nil
        self.b64 = nil
        self.boc = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(["bytes": bytes, "b64": b64, "boc": boc])
    }
}

private struct EmptyCodable: Codable {}
