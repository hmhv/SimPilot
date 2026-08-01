# SimPilot

Traduções: [English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [Español](README.es.md) | [한국어](README.ko.md) | **Português do Brasil**

SimPilot é um conjunto de agent skills para testes e verificação no iOS Simulator, acionado por solicitações em linguagem natural no Claude Code ou no Codex.

Somente o README de nível superior é traduzido. Os skill docs e o código permanecem em inglês.

## O que faz

- **`/sipi-test`**: automação de testes de UI e de estados adversos no iOS Simulator. O skill converte a intenção em linguagem natural em especificações JSON v2 explícitas e, em seguida, `sipi run-test` / `sipi run-suite` as executa com um harness determinístico. Os testes salvos podem controlar permissões, deep links, notificações push, localização, aparência, Dynamic Type, Increase Contrast, Face ID / Touch ID, VoiceOver, o restante das configurações de aparência de acessibilidade, o ambiente de lançamento e um provedor de condição de rede configurado explicitamente.
- **`/sipi-verify`**: verificação pós-implementação. Confirma que um recurso ou correção funciona corretamente após mudanças no código.

Os resultados são salvos em `.simpilot/` com relatórios HTML que podem ser abertos no navegador.

## Pré-requisitos

- macOS 15 ou superior
- Xcode 26 ou superior: necessário em **tempo de execução** para controlar o Simulator (o SimPilot carrega os private Simulator frameworks do Xcode). Não é necessário para instalar. O Xcode 27 ou superior habilita ainda Face ID / Touch ID, VoiceOver e as configurações de aparência de acessibilidade, que passam pelo `xcrun devicectl`.
- [Claude Code](https://claude.com/claude-code) ou Codex

## Instalação

O SimPilot é distribuído como um único binário `sipi` com os skills embutidos. Instale com um único comando:

```bash
curl -fsSL https://raw.githubusercontent.com/hmhv/SimPilot/main/install.sh | bash
```

O instalador baixa o binário `sipi` pré-compilado e, em seguida, o `sipi` registra os skills embutidos `sipi-common` / `sipi-test` / `sipi-verify` em:

- Claude Code (`~/.claude/skills/`)
- Codex (`~/.agents/skills/`)

Verifique os recursos do simulador com `sipi doctor`.

Para atualizar e desinstalar:

```bash
sipi update      # baixa o sipi mais recente do GitHub Releases e atualiza os skills
sipi uninstall   # remove os skills, a metadata de instalação e o binário sipi
```

## Início rápido

No projeto do seu app iOS:

- Claude Code: use slash commands como `/sipi-test`
- Codex: mencione o skill naturalmente, por exemplo `Use the sipi-test skill to ...`

**Testes:**
```text
/sipi-test Crie um teste para alternar entre as abas inicial e ajustes
Use the sipi-test skill to create a test for switching between the home and settings tabs
```

No primeiro uso, o SimPilot detecta seu projeto, cria `.simpilot/config.json` e prepara a sessão do simulator.

**Verificação:**
```text
/sipi-verify Verifique se o novo fluxo de login funciona no simulator
Use the sipi-verify skill to verify the dark mode fix looks correct
```

## Tarefas comuns

**Criar testes:**
```text
/sipi-test Crie um teste de alternância de abas na tela inicial
/sipi-test Crie um teste que faça login e abra ajustes
/sipi-test Crie um teste que ajuste o controle deslizante de brilho para 80% e alterne as notificações
/sipi-test Crie um teste a partir da tela atual
```

Os testes salvos acionam toda a superfície de interação — toques, toques duplos, interruptores, controles deslizantes, gestos, arrastos, toque longo, pinça e multitoque bruto, combinações de teclas e rotação — como passos determinísticos, não apenas toques e deslizes.

Eles também podem criar pré-condições de erro reais controladas pelo Simulator, como permissões negadas, deep links, entrega de push, coordenadas simuladas, correspondência e não correspondência de Face ID / Touch ID, VoiceOver, toda a superfície de aparência de acessibilidade (reduzir movimento, reduzir transparência, filtros de cor, opacidade do Liquid Glass) e perfis de offline/latência apoiados por um provedor. O SimPilot não embute nem imita nenhum condicionador de rede proprietário: verifique `sipi network-condition status` antes de usar um perfil de rede.

A verificação vai além da correspondência de texto: além de `contains` / `absent` e expressões regulares, um passo pode afirmar coisas sobre os próprios elementos — que um controle está desabilitado, que uma lista tem exatamente cinco linhas, que um valor corresponde a um padrão ou que uma área de toque atende aos 44pt.

**Executar testes:**
```text
/sipi-test Execute o teste settings-navigation
/sipi-test Execute a suíte regression
/sipi-test Execute os testes com a tag smoke
/sipi-test Execute a suíte regression no iPhone 16 Pro
/sipi-test Execute os testes no iPhone 16 e no iPhone 15
/sipi-test Execute os testes com o conjunto de dispositivos regression-profile
```

Quando vários dispositivos são especificados, os testes rodam em paralelo. Se `.simpilot/config.json` incluir uma entrada `build`, o app será compilado antes da execução.

**Ver resultados:**
```text
/sipi-test Mostre os resultados mais recentes
/sipi-test Mostre os detalhes da falha do teste settings-toggle
/sipi-test Mostre os detalhes de todos os testes com falha
/sipi-test Abra o relatório HTML
```

Cada execução gera `report.html` dentro do diretório do run. Os resultados são salvos em `.simpilot/runs/`.

**Gerenciar suítes:**
```text
/sipi-test Mostre todos os testes
/sipi-test Mostre os testes com a tag smoke
/sipi-test Crie uma suíte regression com app-launch, settings-toggle e tab-navigation
```

**Auditorias de qualidade:**
```text
/sipi-test Audite as telas onboarding e settings quanto à acessibilidade
/sipi-test Verifique labels e identifiers de acessibilidade ausentes
/sipi-test Verifique o onboarding em English, japonês e alemão quanto à completude da tradução
/sipi-test Verifique texto não traduzido e texto cortado
/sipi-test Compare a tela profile nos modos Light e Dark
/sipi-test Verifique o fluxo de settings com tamanhos grandes de Dynamic Type
/sipi-test Audite esta tela com Reduzir movimento e um filtro de cor ativados
```

O `sipi a11y-audit` executa a parte mecânica pela linha de comando em qualquer simulador iniciado — áreas de toque pequenas demais, controles sem label, labels duplicados ambíguos, labels sem sentido, texto truncado — e sai com código diferente de zero diante de um achado de severidade error, então pode barrar o CI. A auditoria de acessibilidade do próprio Xcode só roda de dentro de um target de teste de UI.

## Estrutura do workspace

O SimPilot usa a seguinte estrutura padrão dentro de `.simpilot/`:

```text
.simpilot/
  config.json                  # Project configuration (app bundle ID, build settings)
  tests/                       # Test definitions
    <test-id>.json
  suites/                      # Test suites
    <suite-name>.json
  devices/                     # Device/simulator profiles
    <profile-name>.json
  runs/                        # Test run results (sipi-test)
    <run-id>/
      run.json                 # Run summary
      summary.json             # Compact agent/CI summary
      report.html              # HTML report (open in browser)
      <test-id>/
        result.json            # Test result
        trace.jsonl            # Per-test event trace
        step-NNN.png           # Step screenshots
        step-NNN.describe-before.json
        step-NNN.describe-after.json
        recording.mp4          # (if enabled)
  verify/                      # Verification results (sipi-verify)
    <timestamp>_<description>/
      checks.json
      findings.json
      report.html
```

É recomendável adicionar `.simpilot/` inteira, ou ao menos `runs/` e `verify/`, ao `.gitignore` do projeto.

## Referência

- **[JSON-REFERENCE.md](.claude/skills/sipi-test/references/json-reference.md)**: especificação JSON completa para tests, suites, devices, results e metadata

## Limitações conhecidas

- A entrada de texto grava por padrão o valor de acessibilidade do campo (`set-text`), que dispensa teclado e aceita qualquer sistema de escrita. A entrada tecla a tecla (`type`) cola pela área de transferência por padrão; a digitação HID direta tecla por tecla cobre apenas o layout de teclado dos EUA
- **Um simulador muito usado pode parar de entregar HID de teclado** (medido no Xcode 27.0 beta 4): colar, digitar tecla por tecla e selecionar tudo + apagar são ignorados, enquanto a entrada por toque continua funcionando. Isso acompanha a idade do dispositivo, não a versão do iOS, e nem `simctl erase` nem uma reinicialização o recuperam: crie um dispositivo novo. `type` detecta a condição e falha em vez de relatar sucesso; `set-text` não é afetado
- Face ID / Touch ID, VoiceOver e as facetas de aparência de acessibilidade além de light/dark exigem o Xcode 27 — elas passam pelo `xcrun devicectl`, que só alcança simuladores dessa versão em diante
- Taxas de contraste e texto cortado estão fora do escopo do `sipi a11y-audit`; ambos exigem análise de pixels do frame renderizado
- Apenas simulador — dispositivos físicos não são suportados

## Note

Este repositório é gerenciado principalmente por IA. Issues e feedback são bem-vindos, mas pull requests não são aceitos. Se quiser adaptar ao seu fluxo, faça um fork e use sua própria cópia.

## Isenção de responsabilidade

O SimPilot é uma ferramenta de desenvolvimento. Ele controla o Simulador do iOS por meio dos **frameworks privados não documentados** da Apple, que a Apple pode alterar ou remover em qualquer atualização do Xcode ou do macOS — o que pode quebrar o SimPilot sem aviso. Ele não é afiliado nem endossado pela Apple e não se destina ao uso na App Store ou em produção. É fornecido **no estado em que se encontra, sem garantia — use por sua conta e risco.**

## License

MIT © 2026 hmhv. Consulte [LICENSE](LICENSE).
