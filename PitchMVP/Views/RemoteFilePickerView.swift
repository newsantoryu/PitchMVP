//
//  RemoteFilePickerView.swift
//  PitchMVP
//
//  Created by victor on 24/02/26.
//

// RemoteFilePickerView.swift
// PitchMVP
//
// Painel de seleção de arquivos remotos (Supabase) + Bundle + Externo.
// Usado dentro de VoiceComparisonView para ambas as abas.

import SwiftUI

struct RemoteFilePickerView: View {

    let title: String
    let accentColor: Color
    let remoteFiles: [RemoteAudioFile]
    let bundleFiles: [String]
    let selectedSource: AudioSource?
    let isLoadingRemote: Bool
    let remoteError: String?

    let onSelectRemote: (RemoteAudioFile) -> Void
    let onSelectBundle: (String) -> Void
    let onImportExternal: () -> Void
    let onRefreshRemote: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // ── Seção Remota (Supabase) ──────────────────────────────────
                sectionHeader(
                    title: "DO SUPABASE",
                    icon: "icloud.and.arrow.down",
                    action: onRefreshRemote,
                    actionIcon: "arrow.clockwise"
                )

                if isLoadingRemote {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 20)
                        Spacer()
                    }
                } else if let error = remoteError {
                    remoteErrorView(error)
                } else if remoteFiles.isEmpty {
                    emptyRemoteView
                } else {
                    remoteFileList
                }

                // ── Seção Bundle (local) ─────────────────────────────────────
                sectionHeader(title: "ARQUIVOS LOCAIS", icon: "internaldrive", action: nil, actionIcon: nil)

                bundleFileList

                // ── Importar externo ─────────────────────────────────────────
                Button(action: onImportExternal) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 13))
                        Text("Importar arquivo externo")
                            .font(.system(size: 14, design: .rounded))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Remote File List

    private var remoteFileList: some View {
        VStack(spacing: 1) {
            ForEach(remoteFiles) { file in
                let isSelected = selectedSource == .remote(file)

                RemoteFileRow(
                    file: file,
                    isSelected: isSelected,
                    accentColor: accentColor
                )
                .onTapGesture { onSelectRemote(file) }

                if file != remoteFiles.last {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Bundle File List

    private var bundleFileList: some View {
        VStack(spacing: 1) {
            ForEach(bundleFiles, id: \.self) { name in
                let isSelected = selectedSource == .bundle(name)

                FileRow(
                    name: "\(name).wav",
                    isSelected: isSelected,
                    accentColor: accentColor
                )
                .onTapGesture { onSelectBundle(name) }

                if name != bundleFiles.last {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Estados vazios / erro

    private var emptyRemoteView: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "tray")
                    .font(.system(size: 24, weight: .thin))
                    .foregroundStyle(.tertiary)
                Text("Nenhum arquivo no Supabase")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 24)
            Spacer()
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func remoteErrorView(_ error: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 16))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Erro ao carregar")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(error)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button("Tentar novamente", action: onRefreshRemote)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(accentColor)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Section Header

    private func sectionHeader(
        title: String,
        icon: String,
        action: (() -> Void)?,
        actionIcon: String?
    ) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.tertiary)

            Spacer()

            if let action, let actionIcon {
                Button(action: action) {
                    Image(systemName: actionIcon)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - RemoteFileRow
// ─────────────────────────────────────────────────────────────────────────────

struct RemoteFileRow: View {
    let file: RemoteAudioFile
    let isSelected: Bool
    let accentColor: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isSelected ? accentColor.opacity(0.15) : Color(.tertiarySystemFill))
                    .frame(width: 36, height: 36)

                Image(systemName: isSelected
                      ? "waveform"
                      : (file.isDownloaded ? "doc.waveform.fill" : "icloud.and.arrow.down"))
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? accentColor : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular,
                                  design: .rounded))
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Text(file.formattedSize)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.tertiary)

                    if file.isDownloaded {
                        Label("Em cache", systemImage: "checkmark.circle")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(accentColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isSelected ? accentColor.opacity(0.05) : Color.clear)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - FileRow (Bundle)
// ─────────────────────────────────────────────────────────────────────────────

struct FileRow: View {
    let name: String
    let isSelected: Bool
    let accentColor: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isSelected ? accentColor.opacity(0.15) : Color(.tertiarySystemFill))
                    .frame(width: 36, height: 36)
                Image(systemName: isSelected ? "waveform" : "doc.waveform")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? accentColor : Color.secondary)
            }

            Text(name)
                .font(.system(size: 15, weight: isSelected ? .semibold : .regular,
                              design: .rounded))

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(accentColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isSelected ? accentColor.opacity(0.05) : Color.clear)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}