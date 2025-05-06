//
//  FunctionCallView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(macOS)
import SwiftUI

extension FunctionCallView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationBarBackButtonHidden(functionCallViewModel.currentIndex != 1 ? true : false)
    }
    
    var main: some View {
        VStack {
            headerMac
            layers
        }
    }
    
    var headerMac: some View {
        FunctionCallHeader(functionCallViewModel: functionCallViewModel)
    }
    
    var layers: some View {
        ZStack {
            Background()
            view
            
            if functionCallViewModel.isLoading || functionCallVerifyViewModel.isLoading {
                loader
            }
        }
    }
}
#endif
