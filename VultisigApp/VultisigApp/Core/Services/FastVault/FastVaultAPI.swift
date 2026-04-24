//
//  FastVaultAPI.swift
//  VultisigApp
//

import Foundation

enum FastVaultAPI: TargetType {
    case validateAccess(pubKeyECDSA: String, base64Password: String)
    case exists(pubKeyECDSA: String)
    case create(VaultCreateRequest)
    case batchCreate(BatchKeygenRequest)
    case keyImport(KeyImportRequest)
    case batchKeyImport(BatchKeyImportRequest)
    case reshare(ReshareRequest)
    case batchReshare(BatchReshareRequest)
    case sign(KeysignRequest)
    case migrate(MigrationRequest)
    case singleKeygen(CreateMldsaRequest)
    case verifyBackupOTP(pubKeyECDSA: String, code: String)

    var baseURL: URL {
        guard let url = URL(string: Endpoint.vultisigApiProxy) else {
            fatalError("Invalid FastVault base URL")
        }
        return url
    }

    var path: String {
        switch self {
        case .validateAccess(let pubKey, _):
            return "/vault/get/\(pubKey)"
        case .exists(let pubKey):
            return "/vault/exist/\(pubKey)"
        case .create:
            return "/vault/create"
        case .batchCreate:
            return "/vault/batch/keygen"
        case .keyImport:
            return "/vault/import"
        case .batchKeyImport:
            return "/vault/batch/import"
        case .reshare:
            return "/vault/reshare"
        case .batchReshare:
            return "/vault/batch/reshare"
        case .sign:
            return "/vault/sign"
        case .migrate:
            return "/vault/migrate"
        case .singleKeygen:
            return "/vault/mldsa"
        case .verifyBackupOTP(let pubKey, let code):
            return "/vault/verify/\(pubKey)/\(code)"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .validateAccess, .exists, .verifyBackupOTP:
            return .get
        case .create, .batchCreate, .keyImport, .batchKeyImport,
             .reshare, .batchReshare, .sign, .migrate, .singleKeygen:
            return .post
        }
    }

    var task: HTTPTask {
        switch self {
        case .validateAccess, .exists, .verifyBackupOTP:
            return .requestPlain
        case .create(let req):
            return .requestCodable(req, .jsonEncoding)
        case .batchCreate(let req):
            return .requestCodable(req, .jsonEncoding)
        case .keyImport(let req):
            return .requestCodable(req, .jsonEncoding)
        case .batchKeyImport(let req):
            return .requestCodable(req, .jsonEncoding)
        case .reshare(let req):
            return .requestCodable(req, .jsonEncoding)
        case .batchReshare(let req):
            return .requestCodable(req, .jsonEncoding)
        case .sign(let req):
            return .requestCodable(req, .jsonEncoding)
        case .migrate(let req):
            return .requestCodable(req, .jsonEncoding)
        case .singleKeygen(let req):
            return .requestCodable(req, .jsonEncoding)
        }
    }

    var headers: [String: String]? {
        switch self {
        case .validateAccess(_, let base64Password):
            return [
                "Content-Type": "application/json",
                "x-password": base64Password
            ]
        default:
            return ["Content-Type": "application/json"]
        }
    }

    var validationType: ValidationType {
        switch self {
        case .validateAccess:
            return .customCodes([200, 401, 403, 404])
        default:
            return .successCodes
        }
    }
}
