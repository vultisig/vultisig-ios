//
//  PeerDiscoveryPayload.swift
//  VultisigApp
//


enum PeerDiscoveryPayload: Codable  {
    case Keygen(keygenMessage)
    case Reshare(ReshareMessage)
}
