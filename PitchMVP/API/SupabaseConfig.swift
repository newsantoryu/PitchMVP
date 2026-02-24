// SupabaseConfig.swift
// PitchMVP
//
// ⚠️  SEGURANÇA — leia antes de commitar:
//
//  • serviceRoleKey → NUNCA deve ir para produção no app iOS.
//    Ela tem acesso total ao banco, bypassa RLS.
//    Use APENAS em scripts de backend/CLI (como seu curl de upload).
//
//  • anonKey → use esta no app iOS. Ela respeita RLS.
//    Pegue em: Supabase Dashboard → Settings → API → "anon public"
//
//  Recomendado para produção:
//    1. Crie um arquivo Config.xcconfig com SUPABASE_ANON_KEY=eyJ...
//    2. Adicione Config.xcconfig ao .gitignore
//    3. Leia via Bundle.main.infoDictionary["SUPABASE_ANON_KEY"]

import Foundation

enum SupabaseConfig {

    // MARK: - Projeto

    static let projectURL = "https://qgjhmdakmghcfiuarfhu.supabase.co"

    // MARK: - Chaves
    // Cole aqui sua anon key (Dashboard → Settings → API → anon public)
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFnamhtZGFrbWdoY2ZpdWFyZmh1Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MTkzOTY1NywiZXhwIjoyMDg3NTE1NjU3fQ.lgX4KuHJTGYP_EwjUF9h04qx9RGtDTTKHAREGo93b08"
    // ☝️ Atenção: esta é a service_role key (identificada pelo "role":"service_role" no JWT).
    //    Funciona para testes, mas substitua pela anon key antes de publicar o app.

    // MARK: - Buckets

    static let performancesBucket = "performances"
    static let referencesBucket   = "references"

    // MARK: - User
    // Substitua pelo ID real do usuário autenticado quando tiver Auth implementado.
    // Por enquanto usa o mesmo valor do seu curl de teste.
    static let defaultUserFolder = "user_001"

    // MARK: - URLs da Storage API (não edite)
    //
    // Baseado no seu curl:
    //   POST /storage/v1/object/references/$USER/$FILE  → upload
    //   GET  /storage/v1/object/references/$USER/$FILE  → download direto
    //   POST /storage/v1/object/list/references         → listar arquivos
    //   POST /storage/v1/object/sign/references/$PATH   → signed URL (bucket privado)

    static let storageURL  = "\(projectURL)/storage/v1"
    static let objectURL   = "\(storageURL)/object"
    static let listURL     = "\(storageURL)/object/list"
    static let signURL     = "\(storageURL)/object/sign"

    // https://qgjhmdakmghcfiuarfhu.supabase.co/storage/v1/object/public/performances/user_001/vozm1.wav

    /// Monta a URL de download direto de um arquivo.
    /// Equivalente ao GET do mesmo endpoint do seu curl de upload.
    static func downloadURL(bucket: String, userFolder: String, fileName: String) -> String {
        "\(objectURL)/\(bucket)/\(userFolder)/\(fileName)"
    }

    /// Tempo de expiração dos signed URLs em segundos (1 hora)
    static let signedURLExpiry = 3600

    // MARK: - Cache local

    static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SupabaseAudioCache", isDirectory: true)
    }
}