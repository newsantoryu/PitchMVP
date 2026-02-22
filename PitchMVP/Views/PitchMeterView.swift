//
//  PitchMeterView.swift
//  PitchMVP
//
//  Created by victor on 22/02/26.
//

import SwiftUI

struct PitchMeterView: View {
    
    var feedback: PitchFeedback?
    
    private let meterHeight: CGFloat = 220
    private let zoneHeight: CGFloat = 20
    
    var body: some View {
        ZStack {
            
            // Fundo do medidor
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.gray.opacity(0.1))
                .frame(width: 80, height: meterHeight)
            
            // Zona verde central (±5 cents)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.4))
                .frame(width: 80, height: zoneHeight)
            
            // Linha central
            Rectangle()
                .fill(Color.green)
                .frame(width: 80, height: 2)
            
            // Indicador móvel
            if let feedback = feedback {
                
                Circle()
                    .fill(feedback.isInTune ? Color.green : Color.orange)
                    .frame(width: 26, height: 26)
                    .offset(y: offsetY(from: feedback))
                    .animation(.easeOut(duration: 0.08), value: feedback.cents)
            }
        }
    }
    
    private func offsetY(from feedback: PitchFeedback) -> CGFloat {
        
        let normalized = feedback.nomalizedOffset
        let maxOffset = (meterHeight / 2) - 20
        
        return CGFloat(-normalized) * maxOffset
    }
}
