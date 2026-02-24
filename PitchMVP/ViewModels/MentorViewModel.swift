// MentorViewModel.swift
// PitchMVP

import SwiftUI

/// ViewModel da tela de Mentor.
/// Recebe frequências detectadas (reais ou simuladas) e calcula
/// o feedback de afinação em relação à nota alvo configurada.
///
/// Fluxo de dados:
/// `SimulatedMentorEngine.simulatedFrequency` → `update(detectedFrequency:)` → `feedback` → View
final class MentorViewModel: ObservableObject {

    // MARK: - Estado Publicado

    /// Frequência alvo em Hz — atualizada quando o usuário muda nota/oitava
    @Published var targetFrequency: Double = 440.0

    /// Nome da nota alvo formatado (ex: "A4", "C#3") — exibido na View
    @Published var targetNote: String = "A4"

    /// Resultado do cálculo de afinação para a última frequência detectada.
    /// `nil` indica que ainda não há sinal de entrada.
    @Published var feedback: PitchFeedback?

           let sessionRecorder = SessionRecorder()
       let sessionService  = SessionHistoryService()

    // MARK: - Processamento

    /// Recebe uma frequência detectada e calcula o desvio em cents em relação ao alvo.
    /// - Parameter detectedFrequency: Frequência em Hz vinda do engine (simulado ou real)
    func update(detectedFrequency: Double) {

        // Ignora frequências inválidas (silêncio ou erro de detecção)
        guard detectedFrequency > 0 else { return }

        // Fórmula do intervalo em cents: 1200 * log2(f_detectada / f_alvo)
        // Positivo = agudo, Negativo = grave, 0 = afinado
        let cents = 1200 * log2(detectedFrequency / targetFrequency)

               if let feedback = self.feedback {
           sessionRecorder.record(feedback: feedback)
       }

        feedback = PitchFeedback(
            detectedFrequency: detectedFrequency,
            targetFrequency: targetFrequency,
            note: targetNote,
            cents: cents
        )
    }

        // 3. Crie uma função para finalizar a sessão:
       func finishSession() {
           guard let session = sessionRecorder.finish(
               targetNote: targetNote,
               targetFrequency: targetFrequency,
               simulationMode: "Simulado"
           ) else { return }
           sessionService.save(session: session)
       }
}