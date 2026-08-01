# SimPilot

번역: [English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [Español](README.es.md) | **한국어** | [Português do Brasil](README.pt-BR.md)

SimPilot은 Claude Code 또는 Codex에서 자연어 요청으로 구동되는 iOS Simulator용 테스트 및 검증 agent skills 모음입니다.

최상위 README만 번역합니다. skill docs와 코드는 영어를 유지합니다.

## 기능

- **`/sipi-test`**: iOS Simulator에서 UI 테스트와 이상 상태 테스트를 자동화합니다. skill이 자연어 의도를 명시적인 v2 JSON 명세로 바꾸고, `sipi run-test` / `sipi run-suite`가 결정적 harness로 실행합니다. 저장된 테스트는 권한, deep link, 푸시 알림, 위치, 화면 모드, Dynamic Type, Increase Contrast, Face ID / Touch ID, VoiceOver, 더 넓은 범위의 접근성 화면 설정, 실행 환경, 명시적으로 구성한 network-condition provider를 제어할 수 있습니다.
- **`/sipi-verify`**: 구현 후 검증입니다. 기능 추가나 버그 수정 후 변경 사항이 올바르게 동작하고 화면도 문제가 없는지 확인합니다.

결과는 `.simpilot/`에 저장되며, 브라우저에서 열 수 있는 HTML 리포트가 생성됩니다.

## 사전 요구 사항

- macOS 15 이상
- Xcode 26 이상: Simulator를 구동하기 위해 **런타임**에 필요합니다(SimPilot이 Xcode의 private Simulator frameworks를 로드합니다). 설치할 때는 필요하지 않습니다. Xcode 27 이상에서는 Face ID / Touch ID, VoiceOver, 접근성 화면 설정도 추가로 사용할 수 있으며, 이들은 `xcrun devicectl`을 거칩니다.
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
/sipi-test 밝기 슬라이더를 80%로 설정하고 알림을 토글하는 테스트를 만들어줘
/sipi-test 현재 화면에서 테스트를 만들어줘
```

저장된 테스트는 탭과 스와이프뿐 아니라 탭·더블 탭·토글·슬라이더·제스처·드래그·길게 누르기·핀치와 원시 멀티터치·키 조합·회전까지 결정적 단계로 실행합니다.

또한 권한 거부, deep link, 푸시 전달, 좌표 시뮬레이션, Face ID / Touch ID 일치와 불일치, VoiceOver, 접근성 화면 설정 전체(동작 줄이기, 투명도 줄이기, 색상 필터, Liquid Glass 불투명도), provider 기반 오프라인/지연 프로파일처럼 Simulator가 실제로 제어하는 오류 전제 조건도 만들 수 있습니다. SimPilot은 독자적인 네트워크 컨디셔너를 포함하지도 흉내 내지도 않습니다. 네트워크 프로파일을 쓰기 전에 `sipi network-condition status`를 확인하세요.

검증은 텍스트 일치에서 그치지 않습니다. `contains` / `absent`와 정규 표현식에 더해, 각 단계는 요소 자체에 대해서도 단언할 수 있습니다. 컨트롤이 비활성 상태인지, 목록이 정확히 다섯 행인지, 값이 패턴과 일치하는지, 터치 영역이 44pt를 충족하는지 같은 것들입니다.

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
/sipi-test 동작 줄이기와 색상 필터를 켠 상태로 이 화면을 감사해줘
```

`sipi a11y-audit`는 그중 기계적으로 검사할 수 있는 부분을 부팅된 아무 simulator에 대해 명령줄에서 실행합니다. 너무 작은 터치 영역, 라벨 없는 컨트롤, 모호하게 중복된 라벨, 의미 없는 라벨, 잘린 텍스트를 찾아내고 error 심각도의 지적이 있으면 0이 아닌 코드로 종료하므로 CI 게이트로 쓸 수 있습니다. Xcode 자체 접근성 감사는 UI 테스트 타깃 안에서만 실행됩니다.

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

`.simpilot/` 전체 또는 최소한 `runs/`와 `verify/`는 프로젝트의 `.gitignore`에 추가하는 것을 권장합니다.

## 참고

- **[JSON-REFERENCE.md](.claude/skills/sipi-test/references/json-reference.md)**: tests, suites, devices, results, metadata에 대한 전체 JSON 명세

## 알려진 제한 사항

- 텍스트 입력은 기본적으로 필드의 접근성 값을 쓰는 방식(`set-text`)이며, 키보드가 필요 없고 어떤 문자 체계든 처리합니다. 키 단위 입력(`type`)은 기본적으로 클립보드(붙여넣기)를 거치며, 키 단위 직접 HID 입력은 미국식 키보드 레이아웃만 지원합니다
- **오래 사용한 simulator는 키보드 HID를 전달하지 않게 될 수 있습니다**(Xcode 27.0 beta 4에서 측정). 붙여넣기, 키 단위 입력, 전체 선택+삭제가 모두 무시되지만 터치 입력은 동작합니다. 이는 iOS 버전이 아니라 기기의 사용 기간에 따르며 `simctl erase`나 재부팅으로도 복구되지 않으므로 기기를 새로 만들어야 합니다. `type`은 이 상태를 감지해 성공으로 보고하지 않고 실패합니다. `set-text`는 영향을 받지 않습니다
- Face ID / Touch ID, VoiceOver, light/dark를 넘어서는 접근성 화면 설정 항목에는 Xcode 27이 필요합니다. 이들은 `xcrun devicectl`을 거치는데, devicectl은 해당 릴리스 이후의 simulator만 대상으로 할 수 있습니다
- 명암비와 잘린 텍스트는 `sipi a11y-audit`의 범위 밖입니다. 둘 다 렌더링된 프레임의 픽셀 분석이 필요합니다
- simulator만 지원하며 실제 기기는 지원하지 않습니다

## Note

이 저장소는 주로 AI가 관리합니다. 이슈와 피드백은 환영하지만 pull request는 받지 않습니다. 필요하면 fork해서 자체 워크플로에 맞게 사용하세요.

## 면책 조항

SimPilot은 개발용 도구입니다. Apple의 **문서화되지 않은 비공개 프레임워크**를 통해 iOS 시뮬레이터를 제어하며, 이러한 프레임워크는 Xcode나 macOS 업데이트에서 Apple이 언제든 변경하거나 제거할 수 있습니다. 그럴 경우 예고 없이 SimPilot이 동작하지 않을 수 있습니다. 이 도구는 Apple과 제휴하거나 승인받은 관계가 아니며, App Store나 프로덕션 용도로 사용하기 위한 것이 아닙니다. 이 도구는 **있는 그대로(as-is) 어떠한 보증도 없이 제공되며, 사용에 따른 책임은 본인에게 있습니다.**

## License

MIT © 2026 hmhv. 자세한 내용은 [LICENSE](LICENSE)를 참고하세요.
