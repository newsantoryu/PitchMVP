# PitchMVP

> Aplicativo iOS para cantores e alunos de canto — ferramentas de treino, análise e comparação de voz.

## Visão geral

PitchMVP é um app iOS focado em treinos vocais e análise de desempenho. Ele oferece transcrição, análise de pitch, comparação entre vozes, exportação de partituras/lyrics e utilitários para estudantes e professores de canto.

## Funcionalidades principais

- **Transcrição de áudio**: integração com transcribers para transformar áudio em texto.
- **Análise de pitch**: visualização e avaliação de pitch por segmento.
- **Comparação de performances**: sobreposição de curvas de pitch entre gravações.
- **Feedback de afinação**: métricas e sugestões para melhorar a entonação.
- **Exportação**: gerar PDFs de letras/partituras via `API/LyricsPDFExporter.swift`.
- **Armazenamento**: integração com Supabase via `API/SupabaseStorageClient.swift`.

## Estrutura do repositório (resumo)

- **App entry**: [PitchMVPApp.swift](PitchMVP/PitchMVPApp.swift)
- **Views principais**: [Views](PitchMVP/Views/) (ex.: [TunerView.swift](PitchMVP/Views/TunerView.swift))
- **Serviços**: [Services](PitchMVP/Services/) (ex.: `AudioEngineService.swift`, `SessionHistoryService.swift`)
- **APIs e infra**: [API](PitchMVP/API/) (ex.: `SupabaseConfig.swift`, `SupabaseStorageClient.swift`)
- **Engines / DSP**: [Engines](PitchMVP/Engines/) e [DSP](PitchMVP/DSP/)
- **Modelos**: [Models](PitchMVP/Models/)

Para ver arquivos específicos, abra as pastas acima no projeto Xcode.

## Requisitos

- macOS com Xcode (versão compatível com SwiftUI do projeto)
- CocoaPods / Swift Package Manager dependendo das dependências usadas pelo projeto

## Como abrir e rodar

1. Clone o repositório:

```bash
git clone <repo-url>
cd PitchMVP
```

2. Abra o workspace/projeto no Xcode:

```bash
open PitchMVP.xcodeproj
```

3. Se houver scripts de setup (opcional):

```bash
# Exemplo: executar um script local de configuração (se existir)
~/setup_swift.sh PitchMVP
```

4. Selecione um simulador ou dispositivo e clique em Run (⌘R).

## Testes

O projeto inclui testes em `PitchMVPTests/` e `PitchMVPUITests/`. Rode-os via Xcode ou usando a linha de comando:

```bash
xcodebuild test -project PitchMVP.xcodeproj -scheme PitchMVP -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 14'
```

## Considerações de arquitetura

- O app usa SwiftUI para a UI e separa responsabilidades entre `Views`, `ViewModels`, `Services`, `Engines` e `API`.
- Módulos importantes:
  - `Services` gerenciam estado e comunicação com áudio/armazenamento.
  - `Engines` e `DSP` lidam com processamento de áudio e alinhamento melódico.
  - `Models` contém tipos de domínio (pitch, notas, transcrição, feedback).

## Contribuição

- Abra uma issue para discutir mudanças grandes.
- Faça fork, crie branch com feature/bugfix e envie um pull request bem descrito.

## Próximos passos sugeridos

- Documentar detalhes das dependências (SPM/CocoaPods).
- Adicionar instruções de CI (GitHub Actions) para build/test.
- Exemplos de uso das principais features no diretório `docs/`.

## Contato

Para dúvidas e contribuições, abra uma issue ou entre em contato com o mantenedor do repositório.

---

Arquivo gerado automaticamente com descrição inicial. Precisa que eu personalize seções (instalação detalhada, badges, licença)?
