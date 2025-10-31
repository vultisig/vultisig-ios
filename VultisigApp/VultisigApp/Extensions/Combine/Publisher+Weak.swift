//
//  Publisher+Weak.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import Combine

public extension Publisher {
    func flatMap<A: AnyObject, P: Publisher>(weak obj: A, transform: @escaping (A, Output) -> P) -> Publishers.FlatMap<P, Self> {
        flatMap { [weak obj] value in
            guard let obj = obj else {
                // swiftlint:disable:next force_cast
                return Empty<Output, Failure>() as! P
            }

            return transform(obj, value)
        }
    }

    func map<A: AnyObject, T: Any>(weak obj: A, transform: @escaping (A, Output) -> T) -> Publishers.Map<Publishers.CompactMap<Self, (A, Self.Output)>, T> {
        compactMap { [weak obj] value in
            guard let obj = obj else {
                return nil
            }

            return (obj, value)
        }
        .map { obj, value in
            transform(obj, value)
        }
    }

    func tryMap<A: AnyObject, T: Any>(weak obj: A, transform: @escaping (A, Output) throws -> T) -> Publishers.TryMap<Publishers.CompactMap<Self, (A, Self.Output)>, T> {
        compactMap { [weak obj] value in
            guard let obj = obj else {
                return nil
            }

            return (obj, value)
        }
        .tryMap { obj, value in
            try transform(obj, value)
        }
    }

    func filter<A: AnyObject>(weak obj: A, isIncluded: @escaping (A, Output) -> Bool) -> Publishers.Filter<Publishers.CompactMap<Self, (A, Self.Output)>> {
        compactMap { [weak obj] value in
            guard let obj = obj else {
                return nil
            }

            return (obj, value)
        }
        .filter { obj, value in
            isIncluded(obj, value)
        }
    }

    func sink<A: AnyObject>(weak obj: A, selector: @escaping (A, Output) -> Void) -> AnyCancellable {
        sink { _ in

        } receiveValue: { [weak obj] output in
            guard let obj = obj else {
                return
            }

            selector(obj, output)
        }
    }

    func sink<A: AnyObject>(
        weak obj: A,
        receiveCompletion: @escaping (A, Subscribers.Completion<Self.Failure>) -> Void,
        receiveValue: @escaping (A, Output) -> Void
    ) -> AnyCancellable {
        sink { [weak obj] completion in
            guard let obj = obj else {
                return
            }

            receiveCompletion(obj, completion)
        } receiveValue: { [weak obj] output in
            guard let obj = obj else {
                return
            }

            receiveValue(obj, output)
        }
    }

    func handleOutput<A: AnyObject>(weak obj: A, selector: @escaping (A, Output) -> Void) -> Publishers.HandleEvents<Self> {
        handleEvents(receiveOutput: { [weak obj] output in
            guard let obj = obj else {
                return
            }

            selector(obj, output)
        })
    }

}

public extension Publisher where Self.Failure == Never {
    func sink<A: AnyObject>(weak obj: A, selector: @escaping (A, Output) -> Void) -> AnyCancellable {
        sink { [weak obj] output in
            guard let obj = obj else {
                return
            }

            selector(obj, output)
        }
    }

    func assign<T: AnyObject>(
        to keyPath: ReferenceWritableKeyPath<T, Output>,
        onWeak object: T
    ) -> AnyCancellable {
        sink { [weak object] value in
            object?[keyPath: keyPath] = value
        }
    }
}
