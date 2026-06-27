# FastTransfer — Instruções Completas

## 1. Abrir no Xcode

1. Abra o Finder e navegue até esta pasta.
2. Dê duplo clique em `FastTransfer.xcodeproj`.
3. O Xcode abrirá automaticamente.
4. No menu **Product → Run** (ou ⌘R) compile e execute.

> **Primeira vez:** O Xcode pedirá para selecionar um Development Team.  
> Vá em **FastTransfer target → Signing & Capabilities** e escolha seu Apple ID  
> (gratuito funciona para testes locais sem App Store).

---

## 2. Estrutura do Projeto

```
FastTransfer/
├── FastTransferApp.swift          # Entry point, AppDelegate
├── FastTransfer.entitlements      # Permissões (sem sandbox para usar rsync)
├── Assets.xcassets/               # Ícones e cores
├── Views/
│   ├── ContentView.swift          # Navegação lateral (sidebar)
│   ├── TransferView.swift         # Tela principal (drag, source, destino, favoritos)
│   └── HistoryView.swift          # Histórico de transferências
├── Models/
│   ├── TransferJob.swift          # Job individual (status, progresso)
│   ├── FavoriteDestination.swift  # Modelo de favorito
│   └── TransferRecord.swift       # Registro persistido no histórico
├── Engine/
│   ├── RsyncRunner.swift          # Executa rsync, parseia progresso em tempo real
│   └── TransferManager.swift      # Orquestra jobs, verifica espaço e volume
└── Managers/
    ├── FavoritesManager.swift     # Salva/carrega favoritos (UserDefaults + bookmarks)
    └── HistoryManager.swift       # Salva/carrega histórico (UserDefaults)
```

---

## 3. Instalar o Quick Action no Finder

### Opção A — Instalação manual (mais simples)

1. Copie a pasta `FastTransferQuickAction/FastTransfer Quick Action.workflow`
2. Cole em: `~/Library/Services/`
3. Abra **Preferências do Sistema → Privacidade e Segurança → Extensões → Finder**
   (ou **System Settings → Privacy & Security → Extensions → Finder**)
4. Ative "FastTransfer" na lista.
5. No Finder, selecione qualquer arquivo → botão direito → **Serviços → FastTransfer**

### Opção B — Criar pelo Automator (mais flexível)

1. Abra **Automator** (encontra pelo Spotlight).
2. Clique **Novo Documento → Quick Action**.
3. Configure:
   - **Workflow receives:** `files or folders` in `Finder`
4. Arraste a ação **"Run Shell Script"** para o fluxo.
5. Selecione `Pass input: as arguments`.
6. Cole o script:
   ```bash
   for f in "$@"
   do
       open -a FastTransfer "$f"
   done
   ```
7. Salve como `FastTransfer` em `~/Library/Services/`.
8. Ative nas configurações de extensões do Finder.

---

## 4. Como Testar

### Teste básico

1. Abra o FastTransfer.
2. Arraste uma pasta grande (ex: pasta de fotos) para a zona de drop.
3. Clique "Selecionar…" no destino e escolha uma pasta diferente.
4. Clique **Transferir** (⌘↩).
5. Observe a barra de progresso, velocidade e tempo restante.

### Comparar com o Finder (cp nativo)

```bash
# Teste com arquivo grande (ex: 10GB)
# Usando cp (Finder usa internamente):
time cp -r /Volumes/SSD/pasta_teste /Volumes/HD_externo/

# Usando FastTransfer (rsync):
time rsync -aHAX --info=progress2 /Volumes/SSD/pasta_teste /Volumes/HD_externo/
```

**O rsync tende a ser mais rápido porque:**
- Usa `--inplace`: escreve direto no arquivo destino sem arquivo temporário.
- Usa `--partial`: retoma de onde parou se interrompido.
- Preserva metadados de forma mais eficiente.

### Teste via Quick Action

1. No Finder, selecione 1 ou mais arquivos.
2. Botão direito → Serviços → FastTransfer.
3. O app abre com os arquivos já na fila de origem.
4. Selecione o destino e transfira.

---

## 5. Comando rsync Explicado

```
rsync -aHAX --info=progress2 --partial --inplace --human-readable ORIGEM DESTINO/
```

| Flag | Significado |
|------|-------------|
| `-a` | Archive: preserva permissões, datas, links simbólicos, grupos |
| `-H` | Preserva hard links |
| `-A` | Preserva ACLs (listas de controle de acesso) |
| `-X` | Preserva atributos estendidos (xattrs, usados pelo macOS) |
| `--info=progress2` | Mostra progresso global (não por arquivo) |
| `--partial` | Mantém arquivos parcialmente transferidos se cancelar |
| `--inplace` | Escreve diretamente no arquivo destino (mais rápido) |
| `--human-readable` | Exibe tamanhos em KB/MB/GB |

---

## 6. Configurações e Personalização

### Alterar configurações de sobrescrita

No `TransferManager.swift`, o método `startTransfer` aceita um parâmetro `overwrite`:
- `.replace` — substitui sem perguntar
- `.skip` — ignora arquivos existentes (adicione `--ignore-existing` ao rsync)
- `.cancel` — cancela toda a operação

### Adicionar destinos favoritos

1. Selecione um destino normalmente.
2. Clique no ícone de estrela ☆ ao lado do destino.
3. O destino aparece como chip na barra de favoritos.
4. Clique no chip para selecionar rapidamente.
5. Hover + X para remover.

---

## 7. Requisitos

- macOS 14 (Sonoma) ou superior
- Apple Silicon ou Intel
- Xcode 15 ou superior
- Conta Apple ID para assinar o app (gratuita para uso local)
