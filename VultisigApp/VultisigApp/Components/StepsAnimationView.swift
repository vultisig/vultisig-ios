//
//  StepsAnimationView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-27.
//

import SwiftUI

struct StepsAnimationView<Header: View, CellContent: View>: View {
    @State var contentHeight: CGFloat = .zero
    let cellHeight: CGFloat = 68
    private let railInset: CGFloat = 33

    let title: String
    let steps: Int
    let cellContent: (Int) -> CellContent
    let header: () -> Header

    @State var showCells: [Bool]

    init(
        title: String,
        steps: Int,
        @ViewBuilder cellContent: @escaping (Int) -> CellContent,
        @ViewBuilder header: @escaping () -> Header
    ) {
        self.title = title
        self.steps = steps
        self.cellContent = cellContent
        self.header = header
        self.showCells = Array(repeating: false, count: steps)
    }

    init(
        title: String,
        steps: Int,
        @ViewBuilder cellContent: @escaping (Int) -> CellContent
    ) where Header == EmptyView {
        self.init(
            title: title,
            steps: steps,
            cellContent: cellContent,
            header: { EmptyView() }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            rectangle
            content
        }
    }

    @ViewBuilder
    var rectangle: some View {
        let height = contentHeight - 2 * railInset
        if height.isFinite && height > 0 {
            Rectangle()
                .frame(width: 2, height: height)
                .foregroundStyle(Theme.colors.bgSurface1)
                .padding(.top, railInset)
        }
    }

    var content: some View {
        VStack(spacing: 32) {
            headerContent
            titleView
            list
        }
        .readSize {
            let currentContentHeight = contentHeight
            contentHeight = $0.height

            if currentContentHeight == 0 {
                setData()
            }
        }
    }

    var headerContent: some View {
        HStack {
            header()
            Spacer()
        }
    }

    var titleView: some View {
        Text(title)
            .settingsText(.largeTitle)
            .foregroundStyle(Theme.colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 20)
            .padding(.bottom, 16)
    }

    var list: some View {
        VStack(spacing: 16) {
            ForEach(0..<steps, id: \.self) { index in
                getCell(index: index)
            }
        }
    }

    @ViewBuilder
    private func getCell(index: Int) -> some View {
        let showCell = showCells[index]
        HStack(spacing: 0) {
            Rectangle()
                .frame(width: 22, height: 2)
                .foregroundStyle(Theme.colors.bgSurface1)

            cellContent(index)
                .padding(16)
                .frame(minHeight: cellHeight)
                .surface(Theme.colors.bgSurface1, radius: Theme.radius.lg)
        }
        .opacity(showCell ? 1 : 0)
        .offset(y: showCell ? 0 : -10)
        .animation(.easeInOut, value: showCell)
    }

    private func setData() {
        showCells.indices.forEach { index in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 * (Double(index) + 1)) {
                showCells[index] = true
            }
        }
    }
}

#Preview {
    StepsAnimationView(title: "How it works", steps: 4) { index in
        Button("Index \(index)") {}
    }
}
