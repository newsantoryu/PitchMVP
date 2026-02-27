// SupabaseStorageClient.swift
// PitchMVP
//
// FIX v2:
// • CacheManifest.persist() — removida escrita manual via arquivo tmp.
//   `Data.write(to:options:.atomic)` já garante atomicidade via syscall do SO —
//   o padrão tmp→move anterior criava uma janela de race condition quando dois
//   downloads terminavam simultaneamente (ambos escreviam no mesmo .tmp e faziam
//   moveItem concorrentemente, podendo corromper ou perder entradas do manifesto).
//
// • persist() agora é chamado dentro do lock — garante que a escrita em disco
//   reflita exatamente o estado do dicionário no momento em que o lock foi adquirido,
//   eliminando a janela entre liberar o lock e escrever em disco.

import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SupabaseStorageError
// ─────────────────────────────────────────────────────────────────────────────

enum SupabaseStorageError: LocalizedError {
    case invalidURL
    case httpError(statusCode: Int, message: String)
    case decodingError(String)
    case fileSystemError(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:              return "URL inválida"
        case .httpError(let c, let m): return "HTTP \(c): \(m)"
        case .decodingError(let m):    return "Decode error: \(m)"
        case .fileSystemError(let m):  return "File error: \(m)"
        case .emptyResponse:           return "Resposta vazia"
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SupabaseFileObject
// ─────────────────────────────────────────────────────────────────────────────

struct SupabaseFileObject: Decodable, Identifiable, Hashable {

    let id: String?
    let name: String
    let updatedAt: String?
    let metadata: FileMetadata?

    struct FileMetadata: Decodable, Hashable {
        let size: Int?
        let mimetype: String?
        let eTag: String?

        enum CodingKeys: String, CodingKey {
            case size, mimetype
            case eTag = "eTag"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, metadata
        case updatedAt = "updated_at"
    }

    var fileExtension: String {
        URL(fileURLWithPath: name).pathExtension.lowercased()
    }

    var formattedSize: String {
        guard let bytes = metadata?.size else { return "—" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }

    var cacheValidator: String? { updatedAt ?? metadata?.eTag }

    func hash(into hasher: inout Hasher) { hasher.combine(name) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.name == rhs.name }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - CacheManifest
// ─────────────────────────────────────────────────────────────────────────────

private final class CacheManifest {

    private let url: URL
    private let fileManager = FileManager.default
    private var entries: [String: String] = [:]

    // Lock protege tanto o dicionário em memória quanto a escrita em disco.
    // persist() é chamado dentro do lock para garantir consistência total.
    private let lock = NSLock()

    init(url: URL) {
        self.url = url
        load()
    }

    // MARK: - API

    func validator(for key: String) -> String? {
        lock.withLock { entries[key] }
    }

    func setValidator(_ validator: String, for key: String) {
        // FIX: persist() dentro do lock — elimina janela de race condition
        // entre liberar o lock e escrever em disco.
        lock.withLock {
            entries[key] = validator
            persistLocked()
        }
    }

    func removeEntry(for key: String) {
        lock.withLock {
            entries.removeValue(forKey: key)
            persistLocked()
        }
    }

    func allKeys() -> [String] {
        lock.withLock { Array(entries.keys) }
    }

    // MARK: - Persistência

    private func load() {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        entries = decoded
        print("[CacheManifest] Carregado: \(entries.count) entradas")
    }

    /// Persiste atomicamente via `Data.write(to:options:.atomic)`.
    ///
    /// O SO (Darwin/APFS) implementa a atomicidade via rename(2) internamente —
    /// idêntico ao padrão tmp→move, mas sem a janela de race condition quando
    /// múltiplas tasks chamam persist() concorrentemente.
    ///
    /// IMPORTANTE: deve ser chamado com o lock já adquirido (sufixo "Locked").
    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(entries) else { return }

        do {
            // FIX: .atomic já usa tmp→rename internamente de forma thread-safe via SO.
            // O padrão manual (tmp→removeItem→moveItem) que existia antes criava
            // uma janela entre removeItem e moveItem onde outro processo podia
            // sobrescrever, corrompendo ou perdendo o manifesto.
            try data.write(to: url, options: .atomic)
        } catch {
            print("[CacheManifest] ⚠️ Falha ao persistir: \(error)")
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SupabaseStorageClient
// ─────────────────────────────────────────────────────────────────────────────

final class SupabaseStorageClient {

    static let shared = SupabaseStorageClient()

    private let session: URLSession
    private let fileManager = FileManager.default
    private let manifest: CacheManifest

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 30
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)

        let cacheDir = SupabaseConfig.cacheDirectory
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        self.manifest = CacheManifest(url: SupabaseConfig.cacheManifestURL)

        print("[Supabase] Cache em: \(cacheDir.path)")
    }

    // MARK: - Request Builder

    private func makeRequest(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(SupabaseConfig.anonKey,             forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: - Listar Arquivos

    func listFiles(
        bucket: String,
        userFolder: String? = nil,
        limit: Int = 100
    ) async throws -> [SupabaseFileObject] {

        guard let url = URL(string: "\(SupabaseConfig.listURL)/\(bucket)") else {
            throw SupabaseStorageError.invalidURL
        }

        var request = makeRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "prefix": userFolder ?? "",
            "limit":  limit,
            "offset": 0,
            "sortBy": ["column": "name", "order": "asc"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("[Supabase] LIST bucket=\(bucket) prefix='\(userFolder ?? "")'")

        let files: [SupabaseFileObject] = try await performRequest(request)

        let audio = files.filter { file in
            guard file.id != nil else { return false }
            guard (file.metadata?.size ?? 0) > 0 else { return false }
            return isAudioFile(file.name)
        }

        print("[Supabase] LIST \(files.count) total → \(audio.count) áudio válidos")
        return audio
    }

    // MARK: - Download com Cache Persistente

    func downloadAudio(
        bucket: String,
        userFolder: String,
        fileName: String,
        isPrivate: Bool = false,
        remoteValidator: String? = nil
    ) async throws -> URL {

        let cacheKey = makeCacheKey(bucket: bucket, userFolder: userFolder, fileName: fileName)
        let localURL = SupabaseConfig.cacheDirectory.appendingPathComponent(cacheKey)

        if fileManager.fileExists(atPath: localURL.path) {
            let cachedValidator = manifest.validator(for: cacheKey)

            if let remote = remoteValidator, let cached = cachedValidator {
                if remote == cached {
                    print("[Supabase] CACHE HIT (\(remote)): \(fileName)")
                    return localURL
                } else {
                    print("[Supabase] CACHE STALE: \(fileName) — remoto=\(remote) local=\(cached)")
                }
            } else if remoteValidator == nil && cachedValidator != nil {
                print("[Supabase] CACHE HIT (sem validator remoto): \(fileName)")
                return localURL
            }
        }

        let downloadURL: URL
        if isPrivate {
            downloadURL = try await createSignedURL(
                bucket: bucket,
                path: "\(userFolder)/\(fileName)"
            )
        } else {
            let rawPath = SupabaseConfig.downloadURL(
                bucket: bucket,
                userFolder: userFolder,
                fileName: fileName
            )
            guard let url = URL(string: rawPath) else {
                throw SupabaseStorageError.invalidURL
            }
            downloadURL = url
        }

        print("[Supabase] DOWNLOAD \(fileName) → \(downloadURL.absoluteString)")

        let request = makeRequest(url: downloadURL)
        let (tempURL, response) = try await session.download(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseStorageError.emptyResponse
        }

        print("[Supabase] DOWNLOAD status: \(httpResponse.statusCode) → \(fileName)")
        try validateHTTPResponse(httpResponse, data: nil)

        do {
            if fileManager.fileExists(atPath: localURL.path) {
                try fileManager.removeItem(at: localURL)
            }
            try fileManager.moveItem(at: tempURL, to: localURL)
        } catch {
            throw SupabaseStorageError.fileSystemError(error.localizedDescription)
        }

        let validatorToStore = remoteValidator ?? ISO8601DateFormatter().string(from: Date())
        manifest.setValidator(validatorToStore, for: cacheKey)

        print("[Supabase] DOWNLOAD salvo: \(localURL.path)")
        return localURL
    }

    // MARK: - Cache Utilities

    func cachedURL(bucket: String, userFolder: String, fileName: String) -> URL? {
        let cacheKey = makeCacheKey(bucket: bucket, userFolder: userFolder, fileName: fileName)
        let localURL = SupabaseConfig.cacheDirectory.appendingPathComponent(cacheKey)
        return fileManager.fileExists(atPath: localURL.path) ? localURL : nil
    }

    func clearCache() throws {
        let files = try fileManager.contentsOfDirectory(
            at: SupabaseConfig.cacheDirectory,
            includingPropertiesForKeys: nil
        )
        for file in files { try fileManager.removeItem(at: file) }
        print("[Supabase] Cache limpo: \(files.count) arquivos removidos")
    }

    func cacheSize() -> Int64 {
        guard let files = try? fileManager.contentsOfDirectory(
            at: SupabaseConfig.cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return files.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    func formattedCacheSize() -> String {
        let bytes = cacheSize()
        let mb = Double(bytes) / 1_048_576
        if mb < 1 { return String(format: "%.0f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", mb)
    }

    // MARK: - Signed URL

    func createSignedURL(bucket: String, path: String) async throws -> URL {

        guard let url = URL(string: "\(SupabaseConfig.signURL)/\(bucket)/\(path)") else {
            throw SupabaseStorageError.invalidURL
        }

        var request = makeRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["expiresIn": SupabaseConfig.signedURLExpiry]
        )

        let response: SignedURLResponse = try await performRequest(request)

        guard let signedURL = URL(string: "\(SupabaseConfig.projectURL)\(response.signedURL)") else {
            throw SupabaseStorageError.invalidURL
        }

        return signedURL
    }

    // MARK: - Helpers Privados

    private func makeCacheKey(bucket: String, userFolder: String, fileName: String) -> String {
        "\(bucket)_\(userFolder)_\(fileName)"
            .replacingOccurrences(of: "/", with: "_")
    }

    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseStorageError.emptyResponse
        }

        print("[Supabase] \(request.httpMethod ?? "?") \(request.url?.path ?? "") → \(httpResponse.statusCode)")

        try validateHTTPResponse(httpResponse, data: data)

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            print("[Supabase] Decode error. Body: \(body)")
            throw SupabaseStorageError.decodingError(error.localizedDescription)
        }
    }

    private func validateHTTPResponse(_ response: HTTPURLResponse, data: Data?) throws {
        guard (200...299).contains(response.statusCode) else {
            var message = HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = json["message"] as? String {
                message = msg
            }
            print("[Supabase] ❌ HTTP \(response.statusCode): \(message)")
            throw SupabaseStorageError.httpError(
                statusCode: response.statusCode,
                message: message
            )
        }
    }

    private func isAudioFile(_ name: String) -> Bool {
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        return ["wav", "mp3", "m4a", "aac", "aiff", "flac", "ogg", "caf"].contains(ext)
    }
}

// MARK: - Response Models

private struct SignedURLResponse: Decodable {
    let signedURL: String
}