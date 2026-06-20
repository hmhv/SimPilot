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
- Xcode 26 이상: Simulator를 구동하기 위해 **런타임**에 필요합니다(SimPilot이 Xcode의 private Simulator frameworks를 로드합니다). 설치할 때는 필요하지 않습니다.
- [Claude Code](https://claude.com/claude-code) 또는 Codex

## 설치

SimPilot은 skills를 포함한 단일 `sipi` 바이너리로 배포됩니다. 한 줄로 설치합니다.

```bash
curl -fsSL https://raw.githubusercontent.com/hmhv/SimPilot/main/install.sh | bash
```

설치 프로그램이 사전 빌드된 `sipi` 바이너리를 내려받고, `sipi`가 포함된 `sipi-common` / `sipi-test` / `sipi-verify` skills를 다음 위치에 등록합니다.

- Claude Code (`~/.claude/skills/`)
- Codex (`~/.agents/skills/`)

`sipi doctor`로 simulator 기능을 확인하세요.

업데이트 및 제거:

```bash
sipi update      # GitHub Releases에서 최신 sipi를 내려받고 skills를 갱신
sipi uninstall   # skills, 설치 metadata, sipi 바이너리를 제거
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

- 미국식 이외의 텍스트 입력은 키 단위 직접 입력이 아니라 클립보드(붙여넣기)로 처리합니다
- 키 단위 직접 HID 입력은 미국식 키보드 레이아웃을 지원합니다
- simulator만 지원하며 실제 기기는 지원하지 않습니다

## Note

이 저장소는 주로 AI가 관리합니다. 이슈와 피드백은 환영하지만 pull request는 받지 않습니다. 필요하면 fork해서 자체 워크플로에 맞게 사용하세요.

## 면책 조항

SimPilot은 개발용 도구입니다. Apple의 **문서화되지 않은 비공개 프레임워크**를 통해 iOS 시뮬레이터를 제어하며, 이러한 프레임워크는 Xcode나 macOS 업데이트에서 Apple이 언제든 변경하거나 제거할 수 있습니다. 그럴 경우 예고 없이 SimPilot이 동작하지 않을 수 있습니다. 이 도구는 Apple과 제휴하거나 승인받은 관계가 아니며, App Store나 프로덕션 용도로 사용하기 위한 것이 아닙니다. 이 도구는 **있는 그대로(as-is) 어떠한 보증도 없이 제공되며, 사용에 따른 책임은 본인에게 있습니다.**

## License

MIT © 2026 hmhv. 자세한 내용은 [LICENSE](LICENSE)를 참고하세요.
