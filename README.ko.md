# SimPilot

번역: [English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [Español](README.es.md) | **한국어** | [Português do Brasil](README.pt-BR.md)

SimPilot은 Claude Code 또는 Codex에서 자연어 요청으로 구동되는 iOS Simulator용 테스트 및 검증 agent skills 모음입니다.

최상위 README만 번역합니다. skill docs와 코드는 영어를 유지합니다.

## 기능

- **`/sipi-test`**: iOS Simulator에서 UI 테스트를 자동화합니다. 자연어로 테스트를 정의하면 skill이 상호작용과 검증을 자동화합니다. 회귀 테스트, 멀티 디바이스 실행, 품질 감사(접근성, 현지화, 화면 검토)를 지원합니다.
- **`/sipi-verify`**: 구현 후 검증입니다. 기능 추가나 버그 수정 후 변경 사항이 올바르게 동작하고 화면도 문제가 없는지 확인합니다.

결과는 `.simpilot/`에 저장되며, 브라우저에서 열 수 있는 HTML 리포트가 생성됩니다.

## 사전 요구 사항

- macOS 15 이상
- Xcode 26 이상
- [AXe](https://github.com/cameroncooke/AXe) CLI
  - `brew install cameroncooke/axe/axe`
  - `axe init`
- [Claude Code](https://claude.com/claude-code) 또는 Codex

SimPilot의 simulator automation은 에이전트 환경에 `axe` skill이 있다고 가정합니다.

## 설치

```bash
git clone https://github.com/hmhv/SimPilot.git
cd SimPilot
make install
```

`make install`은 다음을 수행합니다.

- SimPilot skills를 Claude Code에 등록 (`~/.claude/skills/`)
- SimPilot skills를 Codex에 등록 (`~/.agents/skills/`)

업데이트 및 제거:

```bash
make update
make uninstall
```

## 빠른 시작

iOS 앱 프로젝트에서 사용합니다.

- Claude Code: `/sipi-test` 같은 슬래시 명령 사용
- Codex: `Use the sipi-test skill to ...`처럼 자연스럽게 skill 지정

**테스트:**
```text
/sipi-test 홈과 설정 탭을 전환하는 테스트를 만들어줘
Use the sipi-test skill to create a test for switching between the home and settings tabs
```

처음 사용할 때 SimPilot이 프로젝트를 감지하고 `.simpilot/config.json`을 만든 뒤 simulator 세션을 준비합니다.

**검증:**
```text
/sipi-verify 새 로그인 플로우가 simulator에서 제대로 동작하는지 확인해줘
Use the sipi-verify skill to verify the dark mode fix looks correct
```

## 자주 하는 작업

**테스트 생성:**
```text
/sipi-test 홈 화면 탭 전환 테스트를 만들어줘
/sipi-test 로그인 후 설정을 여는 테스트를 만들어줘
/sipi-test 현재 화면에서 테스트를 만들어줘
```

**테스트 실행:**
```text
/sipi-test settings-navigation 테스트를 실행해줘
/sipi-test regression 스위트를 실행해줘
/sipi-test smoke 태그 테스트를 실행해줘
/sipi-test iPhone 16 Pro에서 regression 스위트를 실행해줘
/sipi-test iPhone 16과 iPhone 15에서 테스트를 실행해줘
/sipi-test regression-profile 디바이스 세트로 테스트를 실행해줘
```

여러 디바이스를 지정하면 테스트는 병렬로 실행됩니다. `.simpilot/config.json`에 `build` 항목이 있으면 실행 전에 앱을 빌드합니다.

**결과 보기:**
```text
/sipi-test 최신 결과를 보여줘
/sipi-test settings-toggle 테스트 실패 상세를 보여줘
/sipi-test 실패한 모든 테스트의 상세를 보여줘
/sipi-test HTML 리포트를 열어줘
```

각 run은 run 디렉터리에 `report.html`을 생성합니다. 결과는 `.simpilot/runs/`에 저장됩니다.

**스위트 관리:**
```text
/sipi-test 모든 테스트를 보여줘
/sipi-test smoke 태그 테스트를 보여줘
/sipi-test app-launch, settings-toggle, tab-navigation으로 regression 스위트를 만들어줘
```

**품질 감사:**
```text
/sipi-test onboarding과 settings 화면을 접근성 감사해줘
/sipi-test 누락된 접근성 라벨과 identifier를 확인해줘
/sipi-test English, 일본어, 독일어에서 onboarding 번역 완성도를 확인해줘
/sipi-test 번역되지 않은 텍스트와 잘린 텍스트를 확인해줘
/sipi-test profile 화면을 Light와 Dark에서 비교해줘
/sipi-test 큰 Dynamic Type 크기에서 settings 플로우를 확인해줘
```

## 워크스페이스 구조

SimPilot은 `.simpilot/` 아래에 다음 구조를 사용합니다.

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

`.simpilot/` 전체 또는 최소한 `runs/`와 `verify/`는 프로젝트의 `.gitignore`에 추가하는 것을 권장합니다.

## 참고

- **[JSON-REFERENCE.md](.claude/skills/sipi-test/references/json-reference.md)**: tests, suites, devices, results, metadata에 대한 전체 JSON 명세

## 알려진 제한 사항

- 텍스트 입력은 클립보드를 사용하며, 비밀번호에는 `axe type`을 사용할 수 없습니다
- `axe type`은 미국식 키보드 레이아웃을 가정합니다
- drag and drop, pinch, rotation 제스처는 재현할 수 없습니다
- PhotosPicker 같은 system UI 요소는 `describe-ui`로 접근할 수 없습니다

## Note

이 저장소는 주로 AI가 관리합니다. 이슈와 피드백은 환영하지만 pull request는 받지 않습니다. 필요하면 fork해서 자체 워크플로에 맞게 사용하세요.

## License

[LICENSE](LICENSE)를 참고하세요.
