//
//  Theme.swift
//  DesignSystem
//
//  Created by Gaston Mazzeo on 01/08/2025.
//

public protocol ThemeProtocol {
    static var fonts: FontSystemProtocol { get }
    static var colors: ColorSystemProtocol { get }
}
