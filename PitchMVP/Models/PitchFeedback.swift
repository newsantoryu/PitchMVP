//
//  PitchFeedback.swift
//  PitchMVP
//
//  Created by victor on 22/02/26.
//
// ─────────────────────────────────────────────────────────────────────────────
// MARK: - PitchFeedback
// ─────────────────────────────────────────────────────────────────────────────
import SwiftUI
/// Resultado do cálculo de afinação em tempo real (MentorViewModel).
/// Encapsula a comparação entre frequência detectada e frequência alvo,
/// expressa em cents para granularidade musical.
struct PitchFeedback {

    /// Frequência detectada pelo engine simulado ou microfone (Hz)
    let detectedFrequency: Double

    /// Frequência alvo configurada pelo usuário (Hz)
    let targetFrequency: Double

    /// Nome da nota alvo (ex: "A4", "C#3")
    let note: String

    /// Desvio em cents: positivo = agudo, negativo = grave
    /// 100 cents = 1 semitom. Limiar perceptível humano ≈ 5-10 cents.
    let cents: Double

    /// Considera afinado quando desvio é menor que 5 cents (imperceptível ao ouvido médio)
    var isInTune: Bool {
        abs(cents) < 5
    }

    /// Offset normalizado em [-1, 1] para uso direto no PitchMeterView.
    /// Clampeado para que desvios > 50 cents não ultrapassem os limites do medidor.
    var nomalizedOffset: Double {
        max(-1, min(1, cents / 50))
    }
}
