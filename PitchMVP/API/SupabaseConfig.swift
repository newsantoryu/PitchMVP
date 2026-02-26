// SupabaseConfig.swift
// PitchMVP

import Foundation

enum SupabaseConfig {

    // MARK: - Projeto

    static let projectURL = "https://qgjhmdakmghcfiuarfhu.supabase.co"

    // MARK: - Chaves

    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFnamhtZGFrbWdoY2ZpdWFyZmh1Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MTkzOTY1NywiZXhwIjoyMDg3NTE1NjU3fQ.lgX4KuHJTGYP_EwjUF9h04qx9RGtDTTKHAREGo93b08"

    // MARK: - Buckets

    static let performancesBucket = "performances"
    static let referencesBucket   = "references"

    // MARK: - User

    static let defaultUserFolder = "user_001"

    // MARK: - URLs

    static let storageURL = "\(projectURL)/storage/v1"
    static let objectURL  = "\(storageURL)/object"
    static let listURL    = "\(storageURL)/object/list"
    static let signURL    = "\(storageURL)/object/sign"

    static func downloadURL(bucket: String, userFolder: String, fileName: String) -> String {
        "\(objectURL)/\(bucket)/\(userFolder)/\(fileName)"
    }

    static let signedURLExpiry = 3600

    // MARK: - Cache Persistente
    //
    // applicationSupportDirectory → nunca apagado pelo iOS, sobrevive a:
    //   • pressão de memória            (diferente de cachesDirectory)
    //   • updates do app                (diferente de tmp)
    //   • reinicializações do dispositivo
    //
    // É incluído no backup do iCloud por padrão — ideal para áudios de referência
    // que o usuário baixou intencionalmente e não deveria perder.
    //
    // Se preferir excluir do backup (arquivos grandes que podem ser re-baixados):
    //   var url = cacheDirectory
    //   try? (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)

    static var cacheDirectory: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("SupabaseAudioCache", isDirectory: true)
    }

    /// Arquivo de manifesto que registra updated_at de cada arquivo em cache.
    static var cacheManifestURL: URL {
        cacheDirectory.appendingPathComponent("cache_manifest.json")
    }
}