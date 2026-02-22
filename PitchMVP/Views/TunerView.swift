//
//  TunerView.swift
//  PitchMVP
//
//  Created by victor on 21/02/26.
//
import SwiftUI

struct TunerView: View {
    
    @StateObject private var viewModel = TunerViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            
            Text("Frequência Detectada")
                .font(.title2)
            
            Text(String(format: "%.2f Hz", viewModel.pitch?.frequency ?? 0.0))
                .font(.largeTitle)
                .bold()
            
            Button("Analisar voz5.wav") {
                if let url = Bundle.main.url(forResource: "voz5",
                                             withExtension: "wav") {
                    viewModel.analyzeFile(url: url)
                } else {
                    print("Arquivo não encontrado no Bundle")
                }
            }
        }
        .padding()
    }
}
