//
//  DefaultTheme.swift
//  DesignSystem
//
//  Created by Gaston Mazzeo on 01/08/2025.
//

public struct DefaultTheme: Theme {
    public let fonts: FontSystem = DefaultFontSystem()
    public let colors: ColorSystem = DefaultColorSystem()

    public init() {}
}
