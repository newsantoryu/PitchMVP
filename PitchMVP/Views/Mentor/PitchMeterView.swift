// PitchMeterView.swift
// PitchMVP — Refatorado

import SwiftUI

struct PitchMeterView: View {

    var feedback: PitchFeedback?

    private let meterHeight: CGFloat = 240
    private let meterWidth: CGFloat = 6
    private let tuneZoneHeight: CGFloat = 28

    var body: some View {
        HStack(spacing: 24) {

            // MARK: Labels laterais
            VStack {
                Text("+50¢")
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("0")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("-50¢")
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .frame(height: meterHeight)

            // MARK: Medidor central
            ZStack {
                // Trilha de fundo
                Capsule()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: meterWidth, height: meterHeight)

                // Zona afinada (verde, centro)
                Capsule()
                    .fill(Color.green.opacity(0.25))
                    .frame(width: meterWidth + 2, height: tuneZoneHeight)

                // Linha central
                Rectangle()
                    .fill(Color.green.opacity(0.6))
                    .frame(width: meterWidth + 8, height: 1.5)

                // Indicador
                if let feedback = feedback {
                    ZStack {
                        // Halo
                        Circle()
                            .fill(indicatorColor(feedback).opacity(0.15))
                            .frame(width: 34, height: 34)

                        // Bolinha principal
                        Circle()
                            .fill(indicatorColor(feedback))
                            .frame(width: 18, height: 18)
                            .shadow(color: indicatorColor(feedback).opacity(0.4), radius: 6, x: 0, y: 2)
                    }
                    .offset(y: offsetY(from: feedback))
                    .animation(.interpolatingSpring(stiffness: 180, damping: 18), value: feedback.cents)
                }
            }

            // MARK: Barra de intensidade (lado direito)
            VStack(spacing: 2) {
                ForEach(0..<12) { i in
                    let intensity = intensityLevel(for: i)
                    Capsule()
                        .fill(barColor(for: i, intensity: intensity))
                        .frame(width: 4, height: (meterHeight / 14))
                        .opacity(intensity)
                        .animation(.easeOut(duration: 0.12), value: feedback?.cents)
                }
            }
            .frame(height: meterHeight)
        }
    }

    // MARK: Helpers

    private func offsetY(from feedback: PitchFeedback) -> CGFloat {
        let normalized = feedback.nomalizedOffset
        let maxOffset = (meterHeight / 2) - 20
        return CGFloat(-normalized) * maxOffset
    }

    private func indicatorColor(_ feedback: PitchFeedback) -> Color {
        feedback.isInTune ? .green : Color(.systemOrange)
    }

    private func intensityLevel(for index: Int) -> Double {
        guard let cents = feedback?.cents else { return 0.08 }
        let absCents = abs(cents)
        // index 0 = topo (agudo), index 11 = baixo (grave)
        let threshold = Double(index + 1) * (50.0 / 12.0)
        if absCents > threshold { return 1.0 }
        return 0.08
    }

    private func barColor(for index: Int, intensity: Double) -> Color {
        guard let feedback = feedback else { return .gray }
        if feedback.isInTune { return .green }
        return feedback.cents < 0 ? Color(.systemBlue) : Color(.systemOrange)
    }
}