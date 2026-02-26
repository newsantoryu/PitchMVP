// SimulatedMentorEngine.swift
// PitchMVP

import Foundation
import Combine

/// Engine que simula uma voz cantando em diferentes condições de afinação.
/// Publica uma frequência simulada via Combine a cada tick do timer,
/// permitindo testar o MentorViewModel sem microfone real.
///
/// Ciclo de vida: `start()` → ticks a cada 50ms → `stop()`
final class SimulatedMentorEngine: ObservableObject {

    // MARK: - Output Publicado

    /// Frequência simulada em Hz — consumida pela View via `.onReceive`
    @Published var simulatedFrequency: Double = 0

    // MARK: - Estado Interno

    /// Timer que dispara o loop de simulação a 20fps (50ms)
    private var timer: Timer?

    /// Contador de tempo acumulado — usado nas funções trigonométricas de simulação
    private var time: Double = 0

    // MARK: - Configuração Externa

    /// Frequência alvo em Hz — definida pela nota selecionada na MentorView
    var targetFrequency: Double = 440.0

    /// Modo de simulação — determina o comportamento do desvio em cents
    var mode: SimulationMode = .instavel

    // MARK: - Ciclo de Vida

    /// Inicia o loop de simulação. Idempotente — ignora chamadas duplicadas.
    func start() {
        guard timer == nil else { return }

        // Usa [weak self] para evitar retain cycle entre timer e engine
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    /// Para o loop de simulação e reseta o timer.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Loop de Simulação

    /// Calcula a frequência simulada para o instante `time` com base no modo.
    /// O desvio é expresso em cents e convertido para Hz via fórmula temperada:
    /// `f = f0 * 2^(cents/1200)`
    private func tick() {
        time += 0.05

        // Desvio em cents em relação à frequência alvo
        let centsOffset: Double

        switch mode {

        case .grave:
            // Fixo abaixo do alvo com leve oscilação — simula voz sempre baixa
            centsOffset = -25 + sin(time * 4) * 5

        case .agudo:
            // Fixo acima do alvo com leve oscilação — simula voz sempre alta
            centsOffset = 25 + sin(time * 4) * 5

        case .instavel:
            // Oscila entre ±20 cents — simula dificuldade de manter a nota
            centsOffset = sin(time * 3) * 20

        case .estavel:
            // Oscilação mínima de ±2 cents — simula voz bem controlada
            centsOffset = sin(time * 6) * 2
        }

        // Conversão cents → Hz usando a fórmula do temperamento igual
        let multiplier = pow(2.0, centsOffset / 1200.0)
        simulatedFrequency = targetFrequency * multiplier
    }
}