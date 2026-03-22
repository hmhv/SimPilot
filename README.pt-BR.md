# SimPilot

Traduções: [English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [Español](README.es.md) | [한국어](README.ko.md) | **Português do Brasil**

SimPilot é um conjunto de agent skills para testes e verificação no iOS Simulator, acionado por solicitações em linguagem natural no Claude Code ou no Codex.

Somente o README de nível superior é traduzido. Os skill docs e o código permanecem em inglês.

## O que faz

- **`/sipi-test`**: automação de testes de UI no iOS Simulator. Defina testes em linguagem natural; o skill automatiza a interação e a verificação. Suporta suítes de regressão, execução em múltiplos dispositivos e auditorias de qualidade (acessibilidade, localização e aparência).
- **`/sipi-verify`**: verificação pós-implementação. Confirma que um recurso ou correção funciona corretamente após mudanças no código.

Os resultados são salvos em `.simpilot/` com relatórios HTML que podem ser abertos no navegador.

## Pré-requisitos

- macOS 15 ou superior
- Xcode 26 ou superior
- [AXe](https://github.com/cameroncooke/AXe) CLI
  - `brew install cameroncooke/axe/axe`
  - `axe init`
- [Claude Code](https://claude.com/claude-code) ou Codex

A simulator automation do SimPilot assume que o ambiente do agente tem o skill `axe` disponível.

## Instalação

```bash
git clone https://github.com/hmhv/SimPilot.git
cd SimPilot
make install
```

`make install` faz o seguinte:

- Registra os skills do SimPilot no Claude Code (`~/.claude/skills/`)
- Registra os skills do SimPilot no Codex (`~/.agents/skills/`)

Para atualizar e desinstalar:

```bash
make update
make uninstall
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
/sipi-test Crie um teste a partir da tela atual
```

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
```

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
      report.html              # HTML report (open in browser)
      <test-id>/
        result.json            # Test result
        step-NNN.png           # Step screenshots
        recording.mp4          # (if enabled)
  verify/                      # Verification results (sipi-verify)
    <timestamp>_<description>/
      report.html
```

É recomendável adicionar `.simpilot/` inteira, ou ao menos `runs/` e `verify/`, ao `.gitignore` do projeto.

## Referência

- **[JSON-REFERENCE.md](.claude/skills/sipi-test/references/json-reference.md)**: especificação JSON completa para tests, suites, devices, results e metadata

## Limitações conhecidas

- A entrada de texto usa a área de transferência; não há `axe type` para senhas
- `axe type` assume um layout de teclado dos EUA
- Não é possível reproduzir gestos de drag and drop, pinch e rotation
- Elementos de system UI como PhotosPicker não são acessíveis via `describe-ui`

## Note

Este repositório é gerenciado principalmente por IA. Issues e feedback são bem-vindos, mas pull requests não são aceitos. Se quiser adaptar ao seu fluxo, faça um fork e use sua própria cópia.

## License

Consulte [LICENSE](LICENSE).
