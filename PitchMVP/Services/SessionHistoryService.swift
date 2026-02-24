//
//  SessionHistoryService.swift
//  PitchMVP
//
//  Created by victor on 23/02/26.
//

// SessionHistoryService.swift
// PitchMVP
//
// Persiste histórico de sessões de afinação usando UserDefaults.
// Cada sessão registra nota alvo, desvio médio, tempo e avaliação geral.
//
// Uso no MentorViewModel:
//   sessionService.save(session: currentSession)
//   let history = sessionService.loadAll()

import Foundation
import Combine

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Modelo de Sessão
// ─────────────────────────────────────────────────────────────────────────────

/// Representa uma sessão de prática de afinação.
/// Codable para serialização via UserDefaults/JSON.
struct PracticeSession: Identifiable, Codable, Hashable {

    let id: UUID
    let date: Date

    /// Nota alvo praticada (ex: "A4")
    let targetNote: String

    /// Frequência alvo em Hz
    let targetFrequency: Double

    /// Desvio médio absoluto em cents durante a sessão
    let averageCents: Double

    /// Desvio máximo absoluto em cents registrado
    let maxCents: Double

    /// Porcentagem do tempo em que estava afinado (dentro de 5 cents)
    let inTunePercentage: Double

    /// Duração da sessão em segundos
    let durationSeconds: Double

    /// Modo de simulação usado (ex: "Estável", "Instável")
    let simulationMode: String

    init(
        targetNote: String,
        targetFrequency: Double,
        averageCents: Double,
        maxCents: Double,
        inTunePercentage: Double,
        durationSeconds: Double,
        simulationMode: String
    ) {
        self.id = UUID()
        self.date = Date()
        self.targetNote = targetNote
        self.targetFrequency = targetFrequency
        self.averageCents = averageCents
        self.maxCents = maxCents
        self.inTunePercentage = inTunePercentage
        self.durationSeconds = durationSeconds
        self.simulationMode = simulationMode
    }

    // MARK: Computed

    /// Avaliação geral baseada na % do tempo afinado
    var rating: SessionRating {
        switch inTunePercentage {
        case 80...:  return .excellent
        case 60..<80: return .good
        case 40..<60: return .fair
        default:     return .needsWork
        }
    }

    static func == (lhs: PracticeSession, rhs: PracticeSession) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Avaliação qualitativa da sessão
enum SessionRating: String, Codable {
    case excellent  = "Excelente"
    case good       = "Bom"
    case fair       = "Regular"
    case needsWork  = "Precisa melhorar"

    var emoji: String {
        switch self {
        case .excellent: return "🎯"
        case .good:      return "✅"
        case .fair:      return "📈"
        case .needsWork: return "💪"
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SessionHistoryService
// ─────────────────────────────────────────────────────────────────────────────

/// Serviço de persistência do histórico de sessões via UserDefaults.
/// Mantém no máximo `maxSessions` sessões, removendo as mais antigas.
final class SessionHistoryService {

    // MARK: - Configuração

    private let storageKey = "pitchMVP.sessionHistory"
    private let maxSessions = 100
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - API Pública

    /// Salva uma nova sessão no histórico.
    /// Remove a sessão mais antiga se o limite for atingido.
    func save(session: PracticeSession) {
        var sessions = loadAll()
        sessions.append(session)

        // Mantém apenas as N sessões mais recentes
        if sessions.count > maxSessions {
            sessions = Array(sessions.suffix(maxSessions))
        }

        persist(sessions)
    }

    /// Carrega todas as sessões salvas, ordenadas da mais recente para a mais antiga.
    func loadAll() -> [PracticeSession] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let sessions = try? decoder.decode([PracticeSession].self, from: data)
        else { return [] }

        return sessions.sorted { $0.date > $1.date }
    }

    /// Carrega sessões para uma nota específica (ex: "A4").
    func load(for note: String) -> [PracticeSession] {
        loadAll().filter { $0.targetNote == note }
    }

    /// Remove todas as sessões do histórico.
    func clearAll() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    /// Remove uma sessão específica pelo ID.
    func delete(sessionID: UUID) {
        var sessions = loadAll()
        sessions.removeAll { $0.id == sessionID }
        persist(sessions)
    }

    // MARK: - Estatísticas

    /// Estatísticas agregadas de todas as sessões.
    func statistics() -> SessionStatistics {
        let sessions = loadAll()
        guard !sessions.isEmpty else { return .empty }

        let avgCents = sessions.map(\.averageCents).reduce(0, +) / Double(sessions.count)
        let avgInTune = sessions.map(\.inTunePercentage).reduce(0, +) / Double(sessions.count)
        let bestSession = sessions.max(by: { $0.inTunePercentage < $1.inTunePercentage })

        return SessionStatistics(
            totalSessions: sessions.count,
            averageCentsDeviation: avgCents,
            averageInTunePercentage: avgInTune,
            bestSession: bestSession
        )
    }

    // MARK: - Privado

    private func persist(_ sessions: [PracticeSession]) {
        guard let data = try? encoder.encode(sessions) else {
            print("[SessionHistoryService] ❌ Falha ao serializar sessões")
            return
        }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

/// Estatísticas agregadas do histórico completo
struct SessionStatistics {
    let totalSessions: Int
    let averageCentsDeviation: Double
    let averageInTunePercentage: Double
    let bestSession: PracticeSession?

    static let empty = SessionStatistics(
        totalSessions: 0,
        averageCentsDeviation: 0,
        averageInTunePercentage: 0,
        bestSession: nil
    )
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SessionRecorder
// ─────────────────────────────────────────────────────────────────────────────

/// Gravador de sessão em tempo real — coleta feedbacks durante a prática
/// e gera um `PracticeSession` ao final.
///
/// Uso no MentorViewModel:
///   recorder.record(feedback: feedback)       // a cada tick
///   let session = recorder.finish(note: "A4") // ao sair da tela
final class SessionRecorder {

    // MARK: - Estado

    private var feedbacks: [PitchFeedback] = []
    private var startTime: Date?

    // MARK: - API

    /// Inicia uma nova gravação. Descarta qualquer gravação anterior.
    func start() {
        feedbacks.removeAll()
        startTime = Date()
    }

    /// Registra um feedback do MentorViewModel.
    func record(feedback: PitchFeedback) {
        feedbacks.append(feedback)
    }

    /// Finaliza a gravação e retorna a sessão compilada.
    /// - Parameters:
    ///   - targetNote: Nota praticada (ex: "A4")
    ///   - targetFrequency: Frequência alvo em Hz
    ///   - simulationMode: Modo usado durante a sessão
    /// - Returns: `PracticeSession` com métricas calculadas, ou `nil` se sem dados
    func finish(
        targetNote: String,
        targetFrequency: Double,
        simulationMode: String
    ) -> PracticeSession? {

        guard !feedbacks.isEmpty, let start = startTime else { return nil }

        let duration = Date().timeIntervalSince(start)
        let absCents = feedbacks.map { abs($0.cents) }

        let averageCents = absCents.reduce(0, +) / Double(absCents.count)
        let maxCents = absCents.max() ?? 0
        let inTuneCount = feedbacks.filter(\.isInTune).count
        let inTunePercentage = Double(inTuneCount) / Double(feedbacks.count) * 100

        return PracticeSession(
            targetNote: targetNote,
            targetFrequency: targetFrequency,
            averageCents: averageCents,
            maxCents: maxCents,
            inTunePercentage: inTunePercentage,
            durationSeconds: duration,
            simulationMode: simulationMode
        )
    }
}