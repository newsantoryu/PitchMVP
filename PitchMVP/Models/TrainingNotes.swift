//
//  TrainingNotes.swift
//  PitchMVP
//
//  Created by victor on 22/02/26.
//
import SwiftUI
/// Nota usada em sessões de treinamento vocal — inclui oitava e frequência exata.
/// Diferente de `BaseNote`, esta já representa uma nota completa (nota + oitava).
struct TrainingNote: Identifiable, Hashable {
    let id = UUID()

    /// Nome completo da nota com oitava (ex: "A4", "C#3")
    let name: String

    /// Frequência exata em Hz calculada pelo temperamento igual
    let frequency: Float
}