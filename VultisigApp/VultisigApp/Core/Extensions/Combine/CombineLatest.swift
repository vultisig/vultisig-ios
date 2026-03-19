//
//  CombineLatest.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import Combine

public extension Array where Element: Publisher {
    func combineLatest() -> AnyPublisher<[Element.Output], Element.Failure> {
        Publishers.CombineLatestArray(self)
    }
}

public extension Publishers {
    static func CombineLatestArray<P>(_ array: [P]) -> AnyPublisher<[P.Output], P.Failure> where P: Publisher {
        guard !array.isEmpty else {
            return Empty().eraseToAnyPublisher()
        }
        return array.dropFirst().reduce(into: AnyPublisher(array[0].map {[$0]})) { res, ob in
            res = res.combineLatest(ob) { i1, i2 -> [P.Output] in
                return i1 + [i2]
            }.eraseToAnyPublisher()
        }
    }
}
