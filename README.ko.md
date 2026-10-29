# SimPilot

번역: [English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [Español](README.es.md) | **한국어** | [Português do Brasil](README.pt-BR.md)

SimPilot은 Claude Code 또는 Codex가 자연어 요청으로 iOS Simulator를 구동하게 해 줍니다. 화면을 읽고, 탭하고, 입력하고, 접고, 캡처하고, 앱에 파일을 넣고, 앱이 저장한 내용을 다시 읽습니다. 또한 그 뒤에 있는 Xcode와 simulator 도구 체인을 설치하고 깨끗하게 유지합니다. 결과를 어떻게 확인할지는 에이전트에게 맡깁니다. 에이전트는 작업에 맞는 방식으로 화면을 읽고, 캡처하고, 앱의 데이터를 읽습니다.

최상위 README만 번역합니다. skill docs와 코드는 영어를 유지합니다.

## 기능

- **simulator 구동**: `sipi`는 접근성 트리를 읽고 그 위에서 네이티브로, headless로 조작합니다. 레이블이나 id로 탭하기, 어떤 문자 체계든 텍스트 입력, 제스처, 하드웨어 버튼, 회전, iPhone Duo 접기, 스크린샷과 동영상, Face ID / Touch ID, 접근성 화면 설정, 메모리 경고를 다룹니다.
- **앱 데이터 다루기**: 앱의 데이터 컨테이너, App Group, Files.app에 파일을 넣고, 앱이 저장한 내용을 텍스트·JSON·plist·SQLite로 확인하고, 컨테이너의 스냅샷을 찍어 diff를 비교하고, 앱의 크래시 리포트를 수집합니다.
- **Xcode와 simulator 런타임 관리**: `sipi xcode list / install / uninstall`로 Xcode를 조회·설치·삭제하고, `sipi runtime list`로 Apple이 제공하는 simulator 런타임 목록을 봅니다. 런타임과 기기의 추가·삭제는 skill에 적힌 대로 `xcodebuild`와 `simctl`로 합니다.
- **정리**: Xcode와 simulator가 남긴 것을 찾아 제거합니다. DerivedData, device support 파일, 프리뷰·테스트용 기기, 사용할 수 없는 런타임, 오래된 Xcode가 대상입니다. 승인 없이는 아무것도 제거하지 않으며, 파일은 휴지통으로 이동합니다.

## 사전 요구 사항

- Xcode 27.2 이상
- macOS 26.6 이상
- [Claude Code](https://claude.com/claude-code) 또는 Codex

## 설치

SimPilot은 skill을 포함한 단일 `sipi` 바이너리로 배포됩니다. 한 줄로 설치합니다.

```bash
curl -fsSL https://raw.githubusercontent.com/hmhv/SimPilot/main/install.sh | bash
```

설치 프로그램이 사전 빌드된 `sipi` 바이너리를 내려받고, `sipi`가 포함된 `sipi-common` skill을 다음 위치에 등록합니다.

- Claude Code (`~/.claude/skills/`)
- Codex (`~/.agents/skills/`)

`sipi doctor`로 simulator 기능을 확인하세요.

업데이트 및 제거:

```bash
sipi update      # GitHub Releases에서 최신 sipi를 내려받고 skill을 갱신
sipi uninstall   # skill, 설치 메타데이터, sipi 바이너리를 삭제
```

2.x에서 업데이트하면 `sipi-test`와 `sipi-verify` skills가 제거됩니다. 앱 저장소의 `.simpilot/tests/`, `suites/`, `devices/`, `runs/`, `verify/`와 `config.json`에서 `app`, `build` 외의 키는 더 이상 쓰이지 않으니, 필요 없어지면 삭제하세요.

## 빠른 시작

iOS 앱 프로젝트에서 사용합니다.

- Claude Code: `/sipi-common` 뒤에 요청을 적거나, 그냥 요청
- Codex: `Use the sipi-common skill to ...`처럼 skill을 지정

```text
/sipi-common 앱을 빌드하고 새 로그인 흐름이 simulator에서 동작하는지 확인해 줘
/sipi-common 설정을 열고 알림을 켜 줘
/sipi-common sample.pdf를 앱의 Inbox에 넣고 가져오기 화면을 확인해 줘
/sipi-common 로그인 후 앱이 저장한 내용을 보여 줘
/sipi-common Xcode 27.2와 iOS 27.2 런타임을 설치해 줘
/sipi-common Xcode가 차지한 디스크 공간을 정리해 줘
```

처음 사용할 때 SimPilot이 프로젝트를 감지하고 `.simpilot/config.json`을 만든 뒤 simulator를 준비합니다.

## simulator 직접 구동

`sipi`는 에이전트가 한 단계씩 호출하는 일반 CLI입니다. `describe-ui --format compact`는 접근성 트리를 요소당 한 줄(유형, 레이블, id, 값, frame, 탭 좌표)로 출력해 JSON의 몇 분의 일 크기로 끝납니다. `wait-for`는 sleep 대신 레이블·id·값·텍스트가 나타날(또는 사라질) 때까지 폴링합니다. `screenshot --max-pixel 600`은 적은 비용으로 확인할 수 있을 만큼 작은 캡처를 돌려주고, `memory-warning`은 Simulator.app의 Debug 메뉴에 있던 메모리 경고를 보냅니다(Xcode 27 이상). `fold-state`는 iPhone Duo의 두 화면 중 어느 쪽이 켜져 있는지 알려주고, `fold --closed|--open|--angle`로 실제로 접고 펼 수 있습니다(simctl도 devicectl도 못 하는 일입니다). `--display inner|cover`로는 꺼진 쪽 화면도 캡처합니다. 전체 명령은 `sipi --help`를 참고하세요.

`sipi a11y-audit`는 부팅된 아무 simulator에서 현재 화면을 검사합니다. 너무 작은 터치 영역, 라벨 없는 컨트롤, 모호하게 중복된 라벨, 의미 없는 라벨, 잘린 텍스트를 찾아냅니다. Xcode 자체 접근성 감사는 UI 테스트 타깃 안에서만 실행됩니다.

앱 데이터 명령은 [App data and evidence commands](docs/data-artifacts.md)에 설명되어 있습니다.

## Xcode와 simulator 런타임

```bash
sipi xcode install 27B48
```

`sipi xcode list`([xcodereleases.com](https://xcodereleases.com)의 목록)에 나와 있는 빌드 번호를 넘기세요. developer.apple.com 창이 열리며, 그곳에서 로그인하면 창은 저절로 닫힙니다. 세션은 해당 실행 동안 메모리에만 존재하며 아무것도 저장되지 않습니다. 앱은 `/Applications/Xcode-<version>.app`(예: `Xcode-27.2.0-release.candidate.app`)으로 설치됩니다. 이를 선택하려면 root 권한이 필요하므로, `sipi`는 직접 실행할 `sudo xcode-select -s …`와 `sudo xcodebuild -runFirstLaunch` 명령을 출력합니다.

`sipi runtime list`는 Apple이 제공하는 simulator 런타임을 설치된 것에 표시를 달아 보여 줍니다(`xcodebuild`와 `simctl`로는 이 목록을 볼 수 없습니다). 설치는 `xcodebuild -downloadPlatform iOS -buildVersion <버전> -architectureVariant arm64`, 삭제는 `xcrun simctl runtime delete`, 기기 생성은 `xcrun simctl create`입니다. skill이 이 명령들을 알고 대신 실행합니다.

## 프로젝트 파일

SimPilot은 프로젝트에 두 개의 파일을 둡니다.

```text
.simpilot/
  config.json   # bundle ID와 앱 빌드 방법
  notes.md      # skill이 기록하는 앱별 조작 요령
```

둘 다 커밋해 둘 만합니다. 팀원이나 다른 에이전트에게 도움이 됩니다.

## 알려진 제한 사항

- 텍스트 입력은 기본적으로 필드의 접근성 값을 쓰는 방식(`set-text`)이며, 키보드가 필요 없고 어떤 문자 체계든 처리합니다. 키 단위 입력(`type`)은 기본적으로 클립보드(붙여넣기)를 거치며, 키 단위 직접 HID 입력은 미국식 키보드 레이아웃만 지원하고, 게스트에서 다른 레이아웃이 활성화되어 있으면 잘못된 문자가 입력됩니다
- **오래 사용한 simulator는 키보드 HID를 받지 않게 될 수 있습니다**(Xcode 27.0 beta 6에서 측정). 붙여넣기, 키 단위 입력, 전체 선택+삭제가 모두 무시되지만 터치 입력은 동작합니다. 이는 iOS 버전이 아니라 기기의 사용 기간에 따르며 `simctl erase`나 재부팅으로도 복구되지 않습니다. `type`은 이 상태를 감지해 성공으로 보고하지 않고 실패합니다. `set-text`는 영향을 받지 않습니다. `type --xcode-mcp`은 대신 Xcode 27의 서비스로 입력하며, 측정한 기기에서는 그것으로 성공했지만 대가가 있습니다(아래 참고)
- 접근성 트리에는 존재한다고 나오지만 실제로는 터치할 수 없는 요소를 탭해도 성공으로 보고됩니다. `describe-point`도 그 요소를 반환하므로 어느 계층에서도 구별할 수 없으며, Xcode 자체 도구도 동일하게 동작합니다
- 명암비와 말줄임표 없이 컨테이너에 잘려 가려진 텍스트는 `sipi a11y-audit`의 범위 밖입니다. 둘 다 렌더링된 프레임의 픽셀 분석이 필요합니다
- **iPhone Duo**(Xcode 27.2에서 측정): 탭·스와이프·텍스트 입력·하드웨어 버튼은 두 화면 모두에 닿습니다. 안쪽 화면은 접근성 hit-test에 아무것도 돌려주지 않으므로 셀렉터 지정 탭은 요소의 위치로 확인 없이 보내지고, `set-text` / `describe-point`는 커버 화면에서만 동작합니다. Device Hub가 열려 있는 동안에는 입력을 Device Hub가 가져가 안쪽 화면의 탭이 버려지고, 시뮬레이터의 페이스트보드가 Mac의 클립보드로 덮어써지므로 `type`은 붙여넣기를 거부합니다. `sipi doctor`가 이 상태를 알려 주며 `sipi repair-input`으로 입력을 되돌릴 수 있습니다. Duo simulator를 스크립트로 회전시키는 방법은 없으며, Device Hub의 회전 버튼을 사용합니다
- simulator만 지원하며 실제 기기는 지원하지 않습니다

## 키 입력을 받지 않게 된 simulator에 입력하기

simulator는 SimPilot이 주입하는 키보드 이벤트를 무시하는 상태가 될 수 있습니다. 터치는 계속 동작하고, 붙여넣기·키 단위 입력·전체 선택+삭제만 듣지 않습니다. SimPilot은 정상 기기와 완전히 동일한 이벤트를 보내므로 SimPilot 쪽에 고칠 부분은 없습니다. 반면 Xcode 27의 기기 상호작용 서비스는 다른 경로로 입력하며, 측정한 이 상태의 기기는 그 경로를 받아들였습니다(더 오래 쓴 기기는 그 경로도 무시했습니다). 게다가 이 경로는 게스트의 키보드 레이아웃에도 영향을 받지 않습니다.

`sipi type --xcode-mcp`로 이 경로를 선택합니다. SimPilot이 스스로 이 경로를 쓰는 일은 없습니다. iOS 27에서는 이 세션을 한 번 거치면 그 기기에서 이후 실행되는 모든 앱의 접근성 트리가 기기를 재시작(`simctl shutdown` + `boot`)할 때까지 비어 버리기 때문입니다. 마지막에 사용하거나, 다음 실행 전에 재시작하세요. SimPilot의 나머지 기능은 모두 이 설정 없이 동작하며, `set-text`는 애초에 키보드가 필요 없습니다.

세 가지 조건이 필요합니다.

```bash
xcode-select -p                    # Xcode 27.2 이상
sudo xcrun mcp-server enable       # headless 모드 활성화
sipi xcode-mcp --approve <.xcodeproj 또는 .xcworkspace 경로>
```

프로젝트는 Xcode의 승인 대화상자를 띄우기 위해서만 열고 곧바로 닫습니다. 설정 후 서비스가 실행 중이 아니면 sipi가 시작합니다. Xcode는 승인을 정확한 바이너리에 묶으므로 `sipi update`나 재빌드 후에는 승인 절차를 다시 거쳐야 합니다. 현재 상태(같은 경로에 있는 이전 빌드의 승인 포함)는 `sipi xcode-mcp`로, 이 경로의 사용 가능 여부는 `sipi doctor`로 확인할 수 있습니다.

`--clear`는 이 경로를 쓸 수 없습니다. 전체 선택과 삭제도 키 입력이며, 이 서비스는 입력은 해도 필드를 비우지는 못하기 때문입니다. 값을 통째로 바꾸려면 `sipi set-text`를 사용하세요.

대가의 원인은 입력이 아니라 세션 자체입니다. Xcode 27.2에서 탭 한 번만 한 세션으로 다시 측정해도, 이후 실행한 App의 접근성 트리는 기기를 재시작할 때까지 비어 있었습니다.


## Note

이 저장소는 주로 AI가 관리합니다. 이슈와 피드백은 환영하지만 pull request는 받지 않습니다. 필요하면 fork해서 자체 워크플로에 맞게 사용하세요.

## 면책 조항

SimPilot은 개발용 도구입니다. Apple의 **문서화되지 않은 비공개 프레임워크**를 통해 iOS 시뮬레이터를 제어하며, 이러한 프레임워크는 Xcode나 macOS 업데이트에서 Apple이 언제든 변경하거나 제거할 수 있습니다. 그럴 경우 예고 없이 SimPilot이 동작하지 않을 수 있습니다. 이 도구는 Apple과 제휴하거나 승인받은 관계가 아니며, App Store나 프로덕션 용도로 사용하기 위한 것이 아닙니다. 이 도구는 **있는 그대로(as-is) 어떠한 보증도 없이 제공되며, 사용에 따른 책임은 본인에게 있습니다.**

## License

MIT © 2026 hmhv. 자세한 내용은 [LICENSE](LICENSE)를 참고하세요.
