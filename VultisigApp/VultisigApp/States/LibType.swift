//
//  LibType.swift
//  VultisigApp
//
//  Created by Johnny Luo on 4/12/2024.
//

import VultisigCommonData
import Foundation

enum LibType : Int,Codable {
    case GG20 = 0
    case DKLS = 1
    case KeyImport = 2
    func toVSLibType()->VSLibType{
        switch self {
        case .GG20:
            return .gg20
        case .DKLS:
            return .dkls
        case .KeyImport:
            return .keyimport
        }
    }
    
    func toString()->String{
        switch self {
        case .GG20:
            return "GG20"
        case .DKLS:
            return "DKLS"
        case .KeyImport:
            return "KeyImport"
        }
    }
}

extension VSLibType {
    func toLibType()->LibType{
        switch self {
        case .gg20:
            return .GG20
        case .dkls:
            return .DKLS
        case .keyimport:
            return .KeyImport
        default:
            return .GG20
        }
    }
}

func GetLibType() -> LibType {
    let existDKLS = UserDefaults.standard.value(forKey: "isDKLSEnabled")
    if existDKLS == nil {
        UserDefaults.standard.set(true, forKey: "isDKLSEnabled")
    }
    let useDKLS = UserDefaults.standard.bool(forKey: "isDKLSEnabled")
    if useDKLS {
        // TODO: return DKLS when ready
        return .KeyImport
        //return .DKLS
    }
    return .GG20
}
