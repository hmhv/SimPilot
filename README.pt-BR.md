# SimPilot

Traduções: [English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [Español](README.es.md) | [한국어](README.ko.md) | **Português do Brasil**

O SimPilot permite que o Claude Code ou o Codex controlem o iOS Simulator a partir de linguagem natural — ler a tela, tocar, digitar, dobrar, capturar, colocar arquivos no app e ler de volta o que ele salvou — e mantém instalado e limpo o conjunto de ferramentas do Xcode e do simulador por trás disso. Como conferir um resultado fica a cargo do agente: ele lê a tela, faz capturas e lê os dados do app da forma que melhor se adequar à tarefa.

Somente o README de nível superior é traduzido. Os skill docs e o código permanecem em inglês.

## O que faz

- **Controlar o simulador**: o `sipi` lê a árvore de acessibilidade e age sobre ela de forma nativa e headless: toques por rótulo ou id, entrada de texto em qualquer sistema de escrita, gestos, botões físicos, rotação, dobrar um iPhone Duo, capturas de tela e vídeo, Face ID / Touch ID, as configurações de aparência de acessibilidade e avisos de pressão de memória.
- **Trabalhar com os dados do app**: colocar arquivos no contêiner de dados do app, em um App Group ou no Files.app; inspecionar o que o app salvou como texto, JSON, plist ou SQLite; tirar snapshots do contêiner e comparar as diferenças; coletar os relatórios de falha do app.
- **Gerenciar o Xcode e os runtimes do simulador**: `sipi xcode list / install / uninstall` lista, instala e remove versões do Xcode, e `sipi runtime list` mostra os runtimes do simulador que a Apple oferece; instalar e remover runtimes e dispositivos é feito com `xcodebuild` e `simctl`, como o skill descreve.
- **Limpar**: encontrar e remover o que o Xcode e os simuladores deixam para trás: DerivedData, arquivos de suporte de dispositivos, dispositivos de preview e de teste, runtimes inutilizáveis, Xcodes antigos. Nada é removido sem aprovação, e os arquivos vão para o Lixo.

## Pré-requisitos

- Xcode 27.2 ou superior
- macOS 26.6 ou superior
- [Claude Code](https://claude.com/claude-code) ou Codex

## Instalação

O SimPilot é distribuído como um único binário `sipi` com o skill embutido. Instale com um único comando:

```bash
curl -fsSL https://raw.githubusercontent.com/hmhv/SimPilot/main/install.sh | bash
```

O instalador baixa o binário `sipi` pré-compilado e, em seguida, o `sipi` instala o skill embutido `sipi-common` em:

- Claude Code (`~/.claude/skills/`)
- Codex (`~/.agents/skills/`)

Verifique os recursos do simulador com `sipi doctor`.

Para atualizar e desinstalar:

```bash
sipi update      # baixa o sipi mais recente do GitHub Releases e atualiza o skill
sipi uninstall   # remove o skill, os metadados de instalação e o binário sipi
```

Atualizar a partir da 2.x remove os skills `sipi-test` e `sipi-verify`. Nos repositórios dos seus apps, `.simpilot/tests/`, `suites/`, `devices/`, `runs/` e `verify/`, e toda chave do `config.json` além de `app` e `build`, não são mais usados — apague-os quando não precisar mais deles.

## Início rápido

No projeto do seu app iOS:

- Claude Code: `/sipi-common` seguido da solicitação, ou simplesmente peça
- Codex: mencione o skill, por exemplo `Use the sipi-common skill to ...`

```text
/sipi-common Compile o app e verifique se o novo fluxo de login funciona no simulador
/sipi-common Abra os ajustes e ative as notificações
/sipi-common Coloque sample.pdf na Inbox do app e verifique a tela de importação
/sipi-common Mostre o que o app salvou depois do login
/sipi-common Instale o Xcode 27.2 e o runtime do iOS 27.2
/sipi-common Limpe o espaço em disco usado pelo Xcode
```

No primeiro uso, o SimPilot detecta seu projeto, cria `.simpilot/config.json` e prepara o simulador.

## Controlar o simulador diretamente

`sipi` é uma CLI comum que um agente chama passo a passo. `describe-ui --format compact` imprime a árvore de acessibilidade com um elemento por linha — tipo, rótulo, id, valor, frame, ponto de toque — numa fração do tamanho do JSON; `wait-for` faz polling até que um rótulo, id, valor ou texto apareça (ou desapareça) em vez de dormir; `screenshot --max-pixel 600` devolve uma captura pequena o bastante para olhar com baixo custo; `memory-warning` envia o aviso de pressão de memória que o menu Debug do Simulator.app oferecia (Xcode 27+); `fold-state` informa qual das duas telas de um iPhone Duo está acesa, `fold --closed|--open|--angle` dobra o aparelho — algo que nem simctl nem devicectl fazem — e `--display inner|cover` captura a tela apagada. Execute `sipi --help` para ver todos os comandos.

O `sipi a11y-audit` verifica a tela atual em qualquer simulador iniciado — áreas de toque pequenas demais, controles sem label, labels duplicados ambíguos, labels sem sentido, texto truncado. A auditoria de acessibilidade do próprio Xcode só roda de dentro de um target de teste de UI.

Os comandos de dados do app estão descritos em [App data and evidence commands](docs/data-artifacts.md).

## Xcode e runtimes do simulador

```bash
sipi xcode install 27B48
```

Passe um número de build de `sipi xcode list` (tirado de [xcodereleases.com](https://xcodereleases.com)). Uma janela se abre em developer.apple.com; faça login ali e ela se fecha sozinha. A sessão fica apenas na memória durante essa execução — nada é armazenado. O app é instalado como `/Applications/Xcode-<version>.app` (por exemplo `Xcode-27.2.0-release.candidate.app`). Selecioná-lo exige root, então o `sipi` imprime os comandos `sudo xcode-select -s …` e `sudo xcodebuild -runFirstLaunch` para você executar.

`sipi runtime list` mostra os runtimes do simulador que a Apple oferece, marcando os instalados (nem o `xcodebuild` nem o `simctl` conseguem listá-los). `xcodebuild -downloadPlatform iOS -buildVersion <versão> -architectureVariant arm64` instala um, `xcrun simctl runtime delete` remove um e `xcrun simctl create` cria dispositivos. O skill conhece esses comandos e os executa para você.

## Arquivos do projeto

O SimPilot mantém dois arquivos no seu projeto:

```text
.simpilot/
  config.json   # bundle ID e como compilar o app
  notes.md      # particularidades de interação do app que o skill registra
```

Vale a pena versionar os dois: um colega de equipe ou outro agente se beneficia deles.

## Limitações conhecidas

- A entrada de texto grava por padrão o valor de acessibilidade do campo (`set-text`), que dispensa teclado e aceita qualquer sistema de escrita. A entrada tecla a tecla (`type`) cola pela área de transferência por padrão; a digitação HID direta tecla por tecla cobre apenas o layout de teclado dos EUA e digita caracteres errados se o convidado estiver com outro layout ativo
- **Um simulador muito usado pode parar de aceitar HID de teclado** (medido no Xcode 27.0 beta 6): colar, digitar tecla por tecla e selecionar tudo + apagar são ignorados, enquanto a entrada por toque continua funcionando. Isso acompanha a idade do dispositivo, não a versão do iOS, e nem `simctl erase` nem uma reinicialização o recuperam. `type` detecta a condição e falha em vez de relatar sucesso; `set-text` não é afetado. `type --xcode-mcp` digita em vez disso pelo serviço do próprio Xcode 27, o que recuperou o dispositivo medido, com um custo (veja abaixo)
- Um toque em um elemento que a árvore de acessibilidade declara presente, mas cuja área visível não é de fato tocável, ainda relata sucesso. `describe-point` também devolve esse elemento, então nenhuma camada consegue distinguir; as ferramentas do próprio Xcode se comportam da mesma forma
- Taxas de contraste e texto cortado estão fora do escopo do `sipi a11y-audit`; ambos exigem análise de pixels do frame renderizado
- **iPhone Duo** (medido no Xcode 27.2): toques, deslizes, digitação e botões físicos alcançam as duas telas. A tela interna não responde ao teste de acerto de acessibilidade, então ali um toque por seletor vai ao quadro do elemento sem verificação, e `set-text` / `describe-point` funcionam só na tela externa. Enquanto o Device Hub está aberto ele assume a entrada do dispositivo: a tela interna descarta os toques e a área de transferência do Mac substitui a do simulador, então `type` se recusa a colar. O `sipi doctor` informa isso e `sipi repair-input` reconecta a entrada. Nada consegue girar um simulador Duo por script, e `sipi orientation --set` o recusa; use o botão de rotação do Device Hub
- Apenas simulador — dispositivos físicos não são suportados

## Digitar em um simulador que parou de aceitar teclas

Um simulador pode chegar a um estado em que ignora os eventos de teclado que o SimPilot injeta. O toque continua funcionando; colar, digitar tecla por tecla e selecionar tudo + apagar, não. O SimPilot envia exatamente os mesmos eventos em um dispositivo saudável e em um afetado, então não há o que corrigir do lado dele. Já o serviço de interação com dispositivos do próprio Xcode 27 digita por outro caminho que o dispositivo afetado medido ainda aceitou (um mais desgastado ignorou esse também), e esse caminho também ignora o layout de teclado do convidado.

`sipi type --xcode-mcp` seleciona esse caminho. O SimPilot nunca o toma por conta própria: no iOS 27, uma única sessão deixa todo app iniciado depois nesse dispositivo com a árvore de acessibilidade vazia até o dispositivo reiniciar (`simctl shutdown` + `boot`); use-o por último, ou reinicie antes do próximo lançamento. Todo o resto do SimPilot funciona sem nada disso, e `set-text` nunca precisa de teclado.

Três condições precisam estar satisfeitas:

```bash
xcode-select -p                    # Xcode 27.2 ou superior
sudo xcrun mcp-server enable       # ligar o modo headless
sipi xcode-mcp --approve <caminho de um .xcodeproj ou .xcworkspace>
```

O projeto é aberto apenas para levantar o diálogo de aprovação do Xcode e é fechado logo em seguida. Depois de configurado, o sipi inicia o serviço se ele não estiver rodando. O Xcode vincula a concessão ao binário exato, então `sipi update` ou uma recompilação exigem repetir a aprovação. `sipi xcode-mcp` informa o estado atual — incluindo uma concessão que pertence a um build anterior no mesmo caminho — e `sipi doctor` diz se esse caminho está disponível.

`--clear` não pode usar esse caminho: selecionar tudo e apagar também são teclas, e o serviço digita mas não consegue esvaziar um campo. Use `sipi set-text` para substituir um valor por completo.

O custo vem da sessão, não da digitação: medido novamente no Xcode 27.2, uma sessão de um único toque deixou todos os apps abertos depois com uma árvore de acessibilidade vazia até o dispositivo reiniciar.


## Note

Este repositório é gerenciado principalmente por IA. Issues e feedback são bem-vindos, mas pull requests não são aceitos. Se quiser adaptar ao seu fluxo, faça um fork e use sua própria cópia.

## Isenção de responsabilidade

O SimPilot é uma ferramenta de desenvolvimento. Ele controla o Simulador do iOS por meio dos **frameworks privados não documentados** da Apple, que a Apple pode alterar ou remover em qualquer atualização do Xcode ou do macOS — o que pode quebrar o SimPilot sem aviso. Ele não é afiliado nem endossado pela Apple e não se destina ao uso na App Store ou em produção. É fornecido **no estado em que se encontra, sem garantia — use por sua conta e risco.**

## License

MIT © 2026 hmhv. Consulte [LICENSE](LICENSE).
