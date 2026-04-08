# SplitViewBrowser

macOS용 SwiftUI + `WKWebView` 기반 스플릿뷰 브라우저입니다. 여러 AI 웹앱을 나란히 열고, 답변을 수집한 뒤 원하는 패널로 다시 전송할 수 있습니다.

## 지원 서비스
- ChatGPT
- Gemini
- Perplexity
- Claude
- Grok
- Custom Sites

## 실행 방법

### Xcode
1. `SplitViewBrowser.xcodeproj`를 엽니다.
2. 스킴 `SplitViewBrowser`를 선택합니다.
3. `My Mac` 대상으로 실행합니다.

### CLI 빌드
```bash
xcodebuild -project SplitViewBrowser.xcodeproj \
  -scheme SplitViewBrowser \
  -destination 'platform=macOS' \
  build
```

### 실행용 앱
```bash
open -na ./SplitViewBrowser.app
```

## 사용 방법
1. 상단에서 패널 수를 `1~5` 중 선택합니다.
2. 각 패널 상단 드롭다운에서 서비스를 고릅니다.
3. 필요하면 프리셋 버튼으로 현재 구성을 저장합니다.
4. 답변을 수집하려면 각 서비스 페이지의 복사 버튼을 누르거나 패널의 복사 버튼을 사용합니다.
5. 분석 대상으로 쓸 패널에서 수집 답변 전송 버튼을 눌러, 수집한 내용을 해당 패널로 전송합니다.
6. 프롬프트 저장소와 설정은 상단 아이콘으로 엽니다.

## 주요 동작
- 패널은 가로 배치만 지원합니다.
- 링크는 앱 내부가 아니라 macOS 기본 브라우저로 열립니다.
- 프리셋에는 패널 수, 패널별 서비스, 창 크기가 저장됩니다.
- 상태는 재실행 후에도 복원됩니다.

## DMG 생성
```bash
./scripts/build_release_app.sh
./scripts/create_dmg.sh ./SplitViewBrowser.app ./SplitViewBrowser-Installer.dmg
```

## 참고
- 일부 사이트의 로그인, 캡차, 보안 정책은 `WKWebView` 환경에서 다르게 동작할 수 있습니다.
- 답변 수집/자동 전송은 각 사이트의 DOM 구조에 의존하므로, 사이트 UI가 바뀌면 조정이 필요할 수 있습니다.
