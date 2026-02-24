//
//  SupabaseAudioRepository.swift
//  PitchMVP
//
//  Created by victor on 24/02/26.
//

// SupabaseAudioRepository.swift
// PitchMVP
//
// Repositório de alto nível que abstrai os dois buckets do Supabase:
//   • performances/$USER/$FILE  → gravações do usuário
//   • references/$USER/$FILE    → vozes de referência
//
// Cada ViewModel usa este repositório — nunca acessa SupabaseStorageClient diretamente.
// Isso facilita mock em testes e troca de backend no futuro.

import Foundation
import Combine

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - RemoteAudioFile
// ─────────────────────────────────────────────────────────────────────────────

/// Representa um arquivo de áudio remoto do Supabase com estado de download.
struct RemoteAudioFile: Identifiable, Hashable {

    let id: String
    let name: String
    let bucket: AudioBucket
    let userFolder: String
    let formattedSize: String

    /// nil = não baixado, .some = caminho local cacheado
    var localURL: URL? = nil

    var isDownloaded: Bool { localURL != nil }

    /// Label de exibição sem extensão
    var displayName: String {
        URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
    }

    init(from file: SupabaseFileObject, bucket: AudioBucket, userFolder: String) {
        self.id          = file.id ?? file.name
        self.name        = file.name
        self.bucket      = bucket
        self.userFolder  = userFolder
        self.formattedSize = file.formattedSize
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - AudioBucket
// ─────────────────────────────────────────────────────────────────────────────

enum AudioBucket: String {
    case performances = "performances"
    case references   = "references"

    var displayName: String {
        switch self {
        case .performances: return "Minha Voz"
        case .references:   return "Referências"
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SupabaseAudioRepository
// ─────────────────────────────────────────────────────────────────────────────

/// Repositório singleton para acesso aos áudios do Supabase.
/// Gerencia listagem, download e cache de ambos os buckets.
final class SupabaseAudioRepository: ObservableObject {

    // MARK: - Singleton
    static let shared = SupabaseAudioRepository()

    // MARK: - Estado Publicado

    @Published private(set) var performanceFiles: [RemoteAudioFile] = []
    @Published private(set) var referenceFiles:   [RemoteAudioFile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String? = nil

    // MARK: - Configuração

    /// ID do usuário atual — substitua pelo valor real do seu Auth system.
    /// Ex: se usar Supabase Auth: SupabaseAuth.shared.currentUser?.id
    var currentUserID: String = "user_001"

    /// Se true, usa signed URLs (bucket privado com RLS).
    /// Se false, usa URL pública direta (bucket público).
    var useSignedURLs: Bool = false

    // MARK: - Dependências

    private let client = SupabaseStorageClient.shared

    // MARK: - Init

    private init() {}

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Listar Arquivos
    // ─────────────────────────────────────────────────────────────────────────

    /// Carrega a lista de arquivos de ambos os buckets simultaneamente.
    @MainActor
    func loadAllFiles() async {
        isLoading = true
        loadError = nil

        async let performances = fetchFiles(bucket: .performances)
        async let references   = fetchFiles(bucket: .references)

        let (perf, refs) = await (performances, references)

        performanceFiles = perf
        referenceFiles   = refs
        isLoading        = false
    }

    /// Carrega arquivos de um bucket específico.
    @MainActor
    func loadFiles(bucket: AudioBucket) async {
        isLoading = true
        loadError = nil

        let files = await fetchFiles(bucket: bucket)

        switch bucket {
        case .performances: performanceFiles = files
        case .references:   referenceFiles   = files
        }

        isLoading = false
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Download
    // ─────────────────────────────────────────────────────────────────────────

    /// Baixa um arquivo remoto e atualiza seu `localURL` na lista.
    /// Retorna a URL local do arquivo (cacheado ou recém-baixado).
    @MainActor
    @discardableResult
    func download(_ file: RemoteAudioFile) async throws -> URL {

        // Se já está em cache, retorna imediatamente
        if let local = file.localURL {
            return local
        }

        let localURL = try await client.downloadAudio(
            bucket:     file.bucket.rawValue,
            userFolder: file.userFolder,
            fileName:   file.name,
            isPrivate:  useSignedURLs
        )

        // Atualiza o localURL na lista correspondente
        updateLocalURL(for: file, url: localURL)

        return localURL
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Privado
    // ─────────────────────────────────────────────────────────────────────────

    private func fetchFiles(bucket: AudioBucket) async -> [RemoteAudioFile] {
        do {
            let raw = try await client.listFiles(
                bucket:     bucket.rawValue,
                userFolder: currentUserID
            )
            return raw.map { RemoteAudioFile(from: $0, bucket: bucket, userFolder: currentUserID) }
        } catch {
            await MainActor.run {
                self.loadError = error.localizedDescription
            }
            return []
        }
    }

    @MainActor
    private func updateLocalURL(for file: RemoteAudioFile, url: URL) {
        func update(in list: inout [RemoteAudioFile]) {
            if let i = list.firstIndex(where: { $0.id == file.id }) {
                list[i].localURL = url
            }
        }
        update(in: &performanceFiles)
        update(in: &referenceFiles)
    }
}