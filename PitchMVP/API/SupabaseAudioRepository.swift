// SupabaseAudioRepository.swift
// PitchMVP
//
// CACHE PERSISTENTE:
//   Ao carregar a lista de arquivos, reconnecta automaticamente localURL
//   de qualquer arquivo já em cache no disco — sem request de rede adicional.
//
//   Ao baixar, passa o updated_at do Supabase para o client comparar com
//   o manifesto e decidir se re-baixa ou usa o cache.

import Foundation
import Combine

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - RemoteAudioFile
// ─────────────────────────────────────────────────────────────────────────────

struct RemoteAudioFile: Identifiable, Hashable {

    let id: String
    let name: String
    let bucket: AudioBucket
    let userFolder: String
    let formattedSize: String

    /// Timestamp de última modificação no Supabase — usado para invalidar cache.
    let updatedAt: String?

    /// nil = não baixado ainda, .some = caminho local no cache persistente
    var localURL: URL? = nil

    var isDownloaded: Bool { localURL != nil }

    var displayName: String {
        URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
    }

    init(from file: SupabaseFileObject, bucket: AudioBucket, userFolder: String) {
        self.id          = file.id ?? file.name
        self.name        = file.name
        self.bucket      = bucket
        self.userFolder  = userFolder
        self.formattedSize = file.formattedSize
        self.updatedAt   = file.cacheValidator   // updated_at ou eTag como fallback
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

final class SupabaseAudioRepository: ObservableObject {

    // MARK: - Singleton

    static let shared = SupabaseAudioRepository()

    // MARK: - Estado Publicado

    @Published private(set) var performanceFiles: [RemoteAudioFile] = []
    @Published private(set) var referenceFiles:   [RemoteAudioFile] = []
    @Published private(set) var isLoading   = false
    @Published private(set) var loadError: String? = nil

    // MARK: - Configuração

    var currentUserID: String = "user_001"
    var useSignedURLs: Bool   = false

    // MARK: - Dependências

    private let client = SupabaseStorageClient.shared

    // MARK: - Init

    private init() {}

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Listar Arquivos
    // ─────────────────────────────────────────────────────────────────────────

    /// Carrega a lista de arquivos de ambos os buckets em paralelo.
    ///
    /// Após listar, cada arquivo tem seu localURL restaurado automaticamente
    /// se já existir em cache — sem download adicional.
    @MainActor
    func loadAllFiles() async {
        isLoading = true
        loadError = nil

        async let performances = fetchFiles(bucket: .performances)
        async let references   = fetchFiles(bucket: .references)

        let (perf, refs) = await (performances, references)

        // Reconnecta localURL de arquivos já em cache persistente
        performanceFiles = perf.map { reconnectCache($0) }
        referenceFiles   = refs.map { reconnectCache($0) }
        isLoading        = false

        let cachedCount = (performanceFiles + referenceFiles).filter(\.isDownloaded).count
        print("[Repository] Lista carregada — \(cachedCount) arquivo(s) já em cache")
    }

    @MainActor
    func loadFiles(bucket: AudioBucket) async {
        isLoading = true
        loadError = nil

        let files = await fetchFiles(bucket: bucket)

        switch bucket {
        case .performances:
            performanceFiles = files.map { reconnectCache($0) }
        case .references:
            referenceFiles   = files.map { reconnectCache($0) }
        }

        isLoading = false
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Download com Invalidação por updated_at
    // ─────────────────────────────────────────────────────────────────────────

    /// Baixa um arquivo remoto, usando cache persistente.
    ///
    /// Passa o `updatedAt` do arquivo para o client comparar com o manifesto.
    /// Se o arquivo não mudou no Supabase desde o último download, retorna o
    /// cache local imediatamente sem nenhuma request de rede.
    @MainActor
    @discardableResult
    func download(_ file: RemoteAudioFile) async throws -> URL {

        // Se já está em cache E o validator local bate com o remoto,
        // o client retorna imediatamente sem download.
        let localURL = try await client.downloadAudio(
            bucket:           file.bucket.rawValue,
            userFolder:       file.userFolder,
            fileName:         file.name,
            isPrivate:        useSignedURLs,
            remoteValidator:  file.updatedAt
        )

        updateLocalURL(for: file, url: localURL)
        return localURL
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Cache Utilities
    // ─────────────────────────────────────────────────────────────────────────

    /// Tamanho total do cache formatado (ex: "23.4 MB").
    var formattedCacheSize: String {
        client.formattedCacheSize()
    }

    /// Remove todo o cache local e reinicia o estado de download.
    @MainActor
    func clearCache() throws {
        try client.clearCache()

        // Reseta localURL de todos os arquivos listados
        performanceFiles = performanceFiles.map {
            var f = $0; f.localURL = nil; return f
        }
        referenceFiles = referenceFiles.map {
            var f = $0; f.localURL = nil; return f
        }

        print("[Repository] Cache limpo")
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
            return raw.map {
                RemoteAudioFile(from: $0, bucket: bucket, userFolder: currentUserID)
            }
        } catch {
            await MainActor.run { self.loadError = error.localizedDescription }
            return []
        }
    }

    /// Tenta reconectar o localURL de um arquivo usando o cache persistente em disco.
    /// Não faz nenhuma request de rede — apenas verifica se o arquivo existe localmente.
    ///
    /// Chamado após cada listagem para que arquivos já baixados apareçam como
    /// `isDownloaded = true` imediatamente, sem o usuário precisar re-baixar.
    private func reconnectCache(_ file: RemoteAudioFile) -> RemoteAudioFile {
        guard file.localURL == nil else { return file }   // já conectado

        if let cached = client.cachedURL(
            bucket:     file.bucket.rawValue,
            userFolder: file.userFolder,
            fileName:   file.name
        ) {
            var updated = file
            updated.localURL = cached
            print("[Repository] Cache reconnected: \(file.name)")
            return updated
        }

        return file
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