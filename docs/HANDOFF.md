# Estado do projeto e plano do Windows

> Documento de retomada. Depois de um `/clear`, ler este arquivo + `README.md`
> dá todo o contexto necessário para continuar.

## 1. O que está pronto

Software completo e validado: `RKCore` (núcleo), `rkg68` (CLI), `RK G68.app`
(SwiftUI, instalado em `~/Applications`). Compila com `./build-app.sh`.

Validação forte: os 9 buffers de mapa de teclas gerados pelo RKCore são
**byte a byte idênticos** aos do software oficial da RK (comparado com captura
do F68). `rkg68 selftest` roda 37 verificações do protocolo a cada build.

Teclado do usuário: **VID 0x258A, PID 0x0049** (`RK-G68 Keyboard`), interface
de configuração em usage page `0x01` / usage `0x80`, feature report 65 bytes.
Responde a remap, aos 21 efeitos RGB, cor por tecla e brilho — tudo testado no
hardware real em 08/10/2026.

## 2. Os 4 LEDs — ENCERRADO: é defeito físico, não protocolo (09/10/2026)

Quatro teclas — **Backspace (79), `\` (80), Enter (81), `←` (83)** — não
acendem de forma confiável. Durante meses isso foi tratado aqui como "máscara
de LED por tecla gravada no firmware, comando não documentado por ninguém", e
era a razão principal da sessão planejada no PC Windows.

**Está errado. É contato elétrico intermitente na placa.** Confirmado pelo
usuário com teste de pressão: apertar de leve a carcaça no canto superior
direito (região Backspace / `\` / Enter) faz o grupo acender e apagar.

### A observação que derrubou a hipótese de software

O usuário descreveu o grupo ligando e desligando sozinho, respondendo a toques
em teclas, "quase como um liga e desliga" — **com o teclado em 2.4G**. Conferido
no barramento no mesmo instante:

```
"2.4G Wireless Receiver"   idVendor = 9639  (0x25A7, Compx)
```

O teclado (VID `0x258A`) **não estava no barramento**. Em 2.4G o canal de
configuração nem existe, então nenhum buffer nosso tocou no teclado enquanto o
fenômeno acontecia. Protocolo não pode ser a causa de algo que acontece sem
protocolo.

### Por que o conjunto fecha em hardware

- São exatamente os índices da **coluna 14 da matriz** (79, 80, 81, 82 vago,
  83); a coluna vizinha (↑ 88 / ↓ 89) nunca falhou. Uma linha de acionamento,
  não teclas avulsas.
- As quatro **digitam normalmente** → a matriz de teclas está íntegra; só a de
  LED falha. São trilhas diferentes.
- Acendem ao segurar `Fn` e ao apertar `\` — que é uma tecla **da própria
  coluna**. Pressão física na região restaura o contato.
- O estado é imprevisível e reversível ("apertei duas vezes seguidas e
  religaram"), o oposto de um registro gravado.
- Sobrevive a reset de fábrica, aos 21 efeitos e à troca de computador.

### O que foi descartado por medição, não por suposição

- **Mapa visual correto**: os retângulos do `KB.ini` sobrepostos à arte
  (`kbled.png`, 716×246) batem tecla a tecla; 79/80/81/83 caem exatamente em
  Backspace, `\`, Enter e `←`.
- **Keymap correto**: `dump-buffers remap` mostra os HID certos em `índice × 4`
  — `00 00 2a 00`, `00 00 31 00`, `00 00 28 00`, `00 00 50 00`.
- **Índices conferem entre modelos**: 0049, 00E7 e 013A dão os mesmos índices
  para essas quatro teclas.
- **Não existe tabela de índice de LED nos arquivos da RK**: `LedMask=0x02`
  está comentado nos 7 modelos e não há `SetLedRgbTab` nem `MaxEftKeyIndex` em
  lugar nenhum. Índice de LED = índice de tecla, 96 posições (16 colunas × 6
  linhas).
- **Não é a tabela de cor por tecla**: no modo 17 (Steady), que não lê essa
  tabela, as quatro continuam apagadas.

### Consequência para o plano

A sessão no PC Windows **deixa de ter o conserto dos LEDs como objetivo**. Resta
só o que é problema de protocolo de verdade: a **macro**. Se o defeito incomodar,
o caminho é garantia / reparo da placa, não software.

Armadilha para a próxima pessoa (ou para o próximo /clear): o perfil salvo
estava em **modo 14 = Customize** com zero cores por tecla. Aplicar aquele
perfil manda o teclado exibir uma tabela vazia e apaga quase tudo — fácil
confundir com o defeito dos quatro. Customize é modo de cor por tecla, não um
efeito.

Já tentado **sem sucesso** (mantido como registro): os 21 efeitos; cor por tecla
em todos os 151 índices; transação completa na ordem do Rangoli (luz → cores →
keymap); as duas variantes do reset de fábrica (`byte[6]=0x01`, com e sem `0xC0`
final); atalhos de reset do teclado (Fn+Esc, Fn+Space, Fn+Ctrl+Esc, Fn+M); RK
Launcher web.

## 2b. Auditoria do KB.ini — o que a RK declara e o código não lê (09/10/2026)

Feita contra o instalador **V4.6 20260816** (261 modelos), baixado de novo e
guardado em `~/Documents/keyboard-ref/`. O `Dev/0049/KB.ini` do instalador novo
é **idêntico** ao embutido em `Sources/RKCore/Resources/rk/` — nosso arquivo
está em dia.

Chaves do `[OPT]` que o `KeyboardConfig` ignora, e o que são:

| Chave | Modelos | O que é | Vale para o G68? |
|---|---|---|---|
| `GaoshouKey1/2`, `clrGaoshou`, `GaoshouIndex` | 7/7 | Conjuntos **Gaming mode** / **Office mode** | **sim — implementado como `keyset`** |
| `KbLayout` | 7/7 | 2 = ANSI, 3 = ISO | não: desenhamos pelos retângulos |
| `UnRectKey` | 3 (comentado no 0049) | polígono do Enter ISO em L | não: o 0049 é ANSI |
| `RGBIndex` | 154/261 | **ordem dos canais de cor** (`0,1,2` ou `1,0,2`) | não declarado no 0049 → ordem padrão |
| `ShowSleepTime` | 1/261 (só o 0103) | mostrar o controle de sleep na interface | **ver abaixo** |
| `LayerNum` / `LayerMask` | 68 / 23 | camadas Fn remapeáveis (`[FN1]`, `[FN2]`) | não: o 0049 não declara nenhuma |
| `MaxEftKeyIndex` | 19 | família de protocolo "EFT" | não |
| `OtherFun` | 12 | teclas extras fora do layout | não |

Chaves que o binário procura mas **nenhum** dos 261 modelos declara:
`GaoshouAddr`, `GaoshouGroupNum`, `GaoshouKeyColor`, `GameRGBIndex`,
`LedModeSelectOffset`, `SupportOutDev`. Existe parser, não existe dado.

Duas conclusões que mudam o que dá para fazer:

- **Nada de camada Fn no G68.** 121 modelos têm seção `[FN1]` no KB.ini e 68
  declaram `LayerNum`; o 0049 não tem nem um nem outro. A camada Fn deste
  teclado não é configurável nem pelo software oficial.
- **O controle de sleep que o app mostra pode ser inerte.** `ShowSleepTime=1`
  aparece **só** no modelo 0103. Como o software oficial esconde o controle
  para quem não declara a chave, o G68 provavelmente ignora o `buffer[13]` que
  a gente envia. Não testado.

### Gaoshou = Gaming/Office mode

Resolvido lendo os arquivos de idioma do binário: `Text/en/text.xml` tem
`tc_adv_str37 = Office mode` e `tc_adv_str38 = Gaming mode`, ao lado de
`Debounce` e `Wireless sleep time` — a aba Avançado. `GaoshouKey1` é o conjunto
de jogo (Esc+WASD+setas), `GaoshouKey2` o de escritório (atalhos, F1–F3,
navegação), `clrGaoshou` a cor (branco em todos os modelos).

Como `GaoshouAddr` não é declarado por modelo nenhum, isto é feito **do lado do
cliente**: preencher a tabela de cor por tecla e ligar o Customize. É o que
`rkg68 keyset` e os botões do app fazem.

O que **não** ficou resolvido: `GaoshouIndex`. Não é índice de modo de luz — no
modelo 0102, que declara 19 modos, ele vale 17, e nem 1-based nem 0-based cai
em Customize. Distribuição nos 261 modelos: 17 (121×), 13 (94×), 1 (31×),
11 (7×), 15 (1×). Fica em aberto; não impede nada.

## 3. Descobertas que nenhum projeto open source tem

- **Reset de fábrica**: buffer de iluminação com **`[6] = 0x01`** (byte que a
  comunidade documenta como "reservado"). Em `LightingCodec.encodeFactoryReset`.
- **O teclado aceita leitura** (`HidD_GetFeature`): report `0x0a` devolve
  `01 01 01 01 01 00…` constante. Em `RKHIDTransport.read`.
- **Três famílias de protocolo** no software oficial: `CDevRKKB` (G68, a
  implementada), `CDevG5KB` (páginas + CRC), `CDev3632` (SendCMD + CRC).
- **Macro vive na família 3632**: `CDev3632::SetMacro`, `Macro_Buffer_ID`,
  `MacroBufferNum`, `MacroHasMsKey=0x07`.
- **RK Launcher web (`drive.rkgaming.com`) NÃO suporta o G68**: a lista de
  dispositivos do site tem 100 PIDs da RK, o menor é `0x0136`. Confirmado no
  bundle JS. Só atende as famílias novas.

## 4. Plano do Windows

Objetivo único: **capturar o protocolo de macro**. O outro objetivo — restaurar
os quatro LEDs — **caiu em 09/10/2026**, quando ficou confirmado que é defeito
físico da placa (ver §2). Nenhuma captura conserta contato intermitente.

**Decisão (08/10/2026): usar um PC Windows real, não VM.** A ideia de montar uma
VM no Mac foi avaliada e descartada — ver abaixo. O teclado vai ser levado até
uma máquina Windows.

Material a levar:
- O teclado e o **cabo USB** (o canal de configuração só existe no cabo).
- Instalador: `~/Documents/keyboard-ref/RK_Keyboard_Software_Setup_V4.6_20260816.exe`
  (88 MB, baixado em 09/10/2026 de
  `https://en.rkgaming.com/media/RK_Keyboard_Software_Setup_V4.6_20260816.exe`,
  link publicado em <https://en.rkgaming.com/download/>). Inno Setup; extrair
  no Mac com `innoextract -s` — `app/DeviceDriver.exe` é o programa,
  `app/Dev/<PID>/KB.ini` as definições (261 modelos nesta versão).

### Passos no PC Windows

1. **Instalar o RK Keyboard Software** e abrir com o teclado conectado no cabo.
2. **Capturar o protocolo** com Wireshark + USBPcap, acionando cada função
   (lista ordenada abaixo). Agora é o objetivo primário.
3. **Trazer as capturas para o Mac** e implementar no RKCore: o protocolo de
   macro (família `CDev3632`, ver §3).

Aproveitar a sessão para conferir, de graça, duas coisas que nunca foram
comparadas com captura: `LightingCodec.encodeStandard` e `encodePerKey`. O
keymap já está validado byte a byte (9/9 no F68); esses dois só têm teste de
consistência interna no `selftest`.

### Por que não a VM (avaliado e descartado em 08/10/2026)

- O **cask do VMware Fusion saiu do Homebrew**: a Broadcom moveu o download para
  portal autenticado. Virou cadastro + download manual.
- O Mac é um **MacBook Air M1 com 8 GB de RAM e ~82 GB livres**: a VM ficaria com
  ~4 GB e ~40 GB de disco. Funciona, mas no limite.
- **Risco real no passthrough de USB HID**: o macOS reserva dispositivos HID, e
  é exatamente aí que aparece o erro de "claim interface". Esse é o único ponto
  que pode matar a sessão inteira, depois de horas de setup.
- **USBPcap é driver x64**: numa VM Windows 11 **ARM64** o suporte é duvidoso —
  ou seja, a VM talvez resolvesse o conserto mas **não** a captura, que é a
  metade mais valiosa. Num PC Windows x86 isso simplesmente funciona.

Se algum dia a VM voltar à mesa: o plano A passa a ser **Parallels Desktop**
(trial de 14 dias, melhor suporte a USB, instala via `brew install --cask
parallels` e baixa o Windows 11 ARM sozinho), não o Fusion. UTM só com backend
QEMU — o backend Apple Virtualization não repassa USB.

### O que capturar, em ordem (sessão de Wireshark)

Uma captura separada por ação, nomeada, para facilitar o diff depois:

1. `01-conectar.pcapng` — só abrir o software com o teclado conectado
   (revela o handshake e a leitura de estado inicial).
2. `02-restore-factory.pcapng` — acionar "restore factory settings".
3. `03-cor-por-tecla.pcapng` — pintar uma tecla específica no modo custom.
4. `04-as-quatro-teclas.pcapng` — pintar Backspace, `\`, Enter e `←`.
   (Já não é para conserto — serve só para conferir nosso `encodePerKey`.)
5. `05-macro-gravar.pcapng` — criar uma macro simples e gravá-la numa tecla.
   **Esta é a captura mais importante agora.**
6. `06-macro-apagar.pcapng` — remover a macro.

Comparar com o que o RKCore já envia usando `rkg68 dump-buffers`.

## 5. Como retomar depois do /clear

Ler este arquivo e `README.md`. O CLI está em `.build/debug/rkg68`
(`swift build` reconstrói). Comandos úteis: `scan`, `info`, `read --scan-ids`,
`dump-buffers`, `factory-reset`, `resync`.

**Regra de método** (aprendida à força neste projeto): antes de qualquer escrita
nova no firmware, ter o caminho de volta testado; mudar um parâmetro por vez;
usar `dump-buffers` antes de enviar.
