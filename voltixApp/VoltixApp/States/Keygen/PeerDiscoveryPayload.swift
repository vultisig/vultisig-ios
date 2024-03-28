//
//  PeerDiscoveryPayload.swift
//  VoltixApp
//


enum PeerDiscoveryPayload: Codable  {
    case Keygen(keygenMessage)
    case Reshare(ReshareMessage)
}
