//
//  PitchResult.swift
//  PitchMVP
//
//  Created by victor on 21/02/26.
//
import SwiftUI
/// Resultado da análise de pitch de um arquivo de áudio (TunerViewModel / Lab).
/// Produzido por `MusicTheory.analyze(frequency:)` após detecção via FFT + HPS.
struct PitchResult {

    /// Frequência fundamental detectada em Hz
    let frequency: Float

    /// Nota MIDI contínua (ex: 69.3 = A4 com desvio de 30 cents)
    let midNote: Float

    /// Nome da nota mais próxima com oitava (ex: "A4", "C#3")
    let noteName: String

    /// Desvio em cents em relação à nota MIDI mais próxima
    /// Positivo = agudo, Negativo = grave
    let cents: Float
}