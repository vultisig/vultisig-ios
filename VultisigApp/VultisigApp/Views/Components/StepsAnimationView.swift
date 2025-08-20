//
//  StepsAnimationView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-27.
//

import SwiftUI

struct StepsAnimationView<Header: View, CellContent: View>: View {
    @State var contentHeight: CGFloat = .zero
    @State var cellHeight: CGFloat = .zero
    
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
        HStack(spacing: 0) {
            rectangle
            content
        }
    }
    
    var rectangle: some View {
        Rectangle()
            .frame(width: 2, height: contentHeight-cellHeight+6)
            .foregroundColor(Theme.colors.bgSecondary)
            .offset(y: -2)
    }

    var content: some View {
        VStack(spacing: 28) {
            headerContent
            titleView
            list
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        contentHeight = geometry.size.height
                        setData()
                    }
            }
        )
    }

    var headerContent: some View {
        HStack {
            header()
            Spacer()
        }
    }

    var titleView: some View {
        Text(title)
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.largeTitle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 24)
    }
    
    var shadow: some View {
        Circle()
            .frame(width: 360, height: 360)
            .foregroundColor(Theme.colors.alertInfo)
            .opacity(0.05)
            .blur(radius: 20)
    }

    var list: some View {
        VStack(spacing: 16) {
            ForEach(0..<steps, id: \.self) { index in
                getCell(index: index)
                    .background(
                        index == 0 ?
                            GeometryReader { geometry in
                                Color.clear
                                    .onAppear {
                                        cellHeight = geometry.size.height
                                    }
                            }
                        : nil
                    )
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        cellHeight = geometry.size.height
                    }
            }
        )
    }

    @ViewBuilder
    private func getCell(index: Int) -> some View {
        let showCell = showCells[index]
        HStack(spacing: 0) {
            Rectangle()
                .frame(width: 22, height: 2)
                .foregroundColor(Theme.colors.bgSecondary)

            cellContent(index)
                .padding(16)
                .background(Theme.colors.bgSecondary)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.colors.border, lineWidth: 1)
                )
        }
        .opacity(showCell ? 1 : 0)
        .offset(y: showCell ? 0 : -10)
        .animation(.easeInOut, value: showCell)
    }
    
    private func setData() {
        showCells.enumerated().forEach { index, _ in
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
