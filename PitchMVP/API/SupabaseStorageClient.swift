// SupabaseStorageClient.swift
// PitchMVP

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
        case .invalidURL:                    return "URL inválida"
        case .httpError(let code, let msg):  return "HTTP \(code): \(msg)"
        case .decodingError(let msg):        return "Decode error: \(msg)"
        case .fileSystemError(let msg):      return "File error: \(msg)"
        case .emptyResponse:                 return "Resposta vazia"
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SupabaseFileObject
// ─────────────────────────────────────────────────────────────────────────────

struct SupabaseFileObject: Decodable, Identifiable, Hashable {

    let id: String?
    let name: String
    let metadata: FileMetadata?

    struct FileMetadata: Decodable, Hashable {
        let size: Int?
        let mimetype: String?
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

    func hash(into hasher: inout Hasher) { hasher.combine(name) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.name == rhs.name }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SupabaseStorageClient
// ─────────────────────────────────────────────────────────────────────────────

final class SupabaseStorageClient {

    static let shared = SupabaseStorageClient()

    private let session: URLSession
    private let fileManager = FileManager.default

    private init() {
        // URLSession simples — headers são adicionados por request
        // (httpAdditionalHeaders pode ser ignorado em alguns casos no iOS)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 30
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)

        try? fileManager.createDirectory(
            at: SupabaseConfig.cacheDirectory,
            withIntermediateDirectories: true
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Request Builder (central — garante headers sempre presentes)
    // ─────────────────────────────────────────────────────────────────────────

    /// Cria uma URLRequest com os headers do Supabase já aplicados.
    /// Usar este método garante que Authorization nunca seja omitido.
    private func makeRequest(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        // Headers adicionados diretamente no request — mais confiável que httpAdditionalHeaders
        request.setValue(SupabaseConfig.anonKey,               forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)",   forHTTPHeaderField: "Authorization")
        return request
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Listar Arquivos
    // ─────────────────────────────────────────────────────────────────────────

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

        // Descarta pastas (id==nil), placeholders (size==0) e não-áudio
        let audio = files.filter { file in
            guard file.id != nil else { return false }
            guard (file.metadata?.size ?? 0) > 0 else { return false }
            return isAudioFile(file.name)
        }

        print("[Supabase] LIST \(files.count) total → \(audio.count) áudio válidos")
        audio.forEach { print("[Supabase]   • \($0.name) (\($0.formattedSize))") }
        return audio
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Download com Cache
    // ─────────────────────────────────────────────────────────────────────────

    func downloadAudio(
        bucket: String,
        userFolder: String,
        fileName: String,
        isPrivate: Bool = false
    ) async throws -> URL {

        let cacheKey = "\(bucket)_\(userFolder)_\(fileName)"
            .replacingOccurrences(of: "/", with: "_")
        let localURL = SupabaseConfig.cacheDirectory.appendingPathComponent(cacheKey)

        // Cache hit
        if fileManager.fileExists(atPath: localURL.path) {
            print("[Supabase] CACHE HIT: \(cacheKey)")
            return localURL
        }

        // Monta URL de download — mesmo padrão do seu curl:
        // GET /storage/v1/object/{bucket}/{userFolder}/{fileName}
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

        print("[Supabase] DOWNLOAD url=\(downloadURL.absoluteString)")

        // Usa makeRequest para garantir Authorization no download
        let request = makeRequest(url: downloadURL, method: "GET")
        let (tempURL, response) = try await session.download(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseStorageError.emptyResponse
        }

        print("[Supabase] DOWNLOAD status: \(httpResponse.statusCode)")
        try validateHTTPResponse(httpResponse, data: nil)

        do {
            if fileManager.fileExists(atPath: localURL.path) {
                try fileManager.removeItem(at: localURL)
            }
            try fileManager.moveItem(at: tempURL, to: localURL)
        } catch {
            throw SupabaseStorageError.fileSystemError(error.localizedDescription)
        }

        print("[Supabase] DOWNLOAD salvo em: \(localURL.path)")
        return localURL
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Signed URL
    // ─────────────────────────────────────────────────────────────────────────

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

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Cache Management
    // ─────────────────────────────────────────────────────────────────────────

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

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Helpers Privados
    // ─────────────────────────────────────────────────────────────────────────

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
            // Loga o body para facilitar debug
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
            throw SupabaseStorageError.httpError(statusCode: response.statusCode, message: message)
        }
    }

    private func isAudioFile(_ name: String) -> Bool {
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        // Aceita extensões de áudio comuns (mimetype pode variar: audio/wav vs audio/x-wav)
        return ["wav", "mp3", "m4a", "aac", "aiff", "flac", "ogg", "caf"].contains(ext)
    }
}

// MARK: - Response Models

private struct SignedURLResponse: Decodable {
    let signedURL: String
}