//
//  BaseNote.swift
//  PitchMVP
//
//  Created by victor on 22/02/26.
//
import SwiftUI
/// Representa uma nota base sem oitava — usada como referência de frequência na oitava 4.
/// Pode ser combinada com um número de oitava para calcular a frequência exata.
struct BaseNote: Identifiable, Hashable {
    let id = UUID()

    /// Nome da nota (ex: "A", "C#")
    let name: String

    /// Frequência de referência na oitava 4 (Hz) — ex: A4 = 440 Hz
    let baseFrequency: Float
}
