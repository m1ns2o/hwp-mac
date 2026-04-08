# HwpMacApp

`HwpMacApp`은 Rust `rhwp` 엔진을 사용해 macOS에서 HWP/HWPX 문서를 열고 편집하기 위한 SwiftUI/AppKit 에디터입니다.

## 아키텍처

- `SwiftUI`: 앱 셸, 상단 툴바, 인스펙터, 상태바
- `AppKit`: 실제 편집 캔버스, 키 입력, IME, selection drag
- `EditorSession`: Rust C ABI를 감싸는 단일 세션 래퍼
- `DocumentController`: 문서 상태, 편집 명령, undo/redo, 저장 orchestration
- `PageRenderer`: Rust `PageRenderTree`를 macOS 그래픽 컨텍스트에 렌더

## 폴더 구조

```text
Sources/
├── CRhwpNative/
│   ├── include/rhwp_native.h
│   └── shim.c
└── HwpMacApp/
    ├── App/
    ├── Bridge/
    ├── Documents/
    ├── Editor/
    ├── Inspector/
    ├── Models/
    └── Support/
```

## 구현 상태

- HWP/HWPX 열기
- 빈 문서 생성
- HWP 저장
- 클릭 이동, 방향키 이동, 기본 입력
- drag selection / selection highlight
- 잘라내기 / 복사 / 붙여넣기
- 찾기 / 바꾸기
- 기본 글자 서식 토글
- 문단 정렬
- 표 삽입, 행/열 추가 및 삭제
- snapshot 기반 undo/redo

## 빌드

저장소 루트에서 Rust 라이브러리를 먼저 빌드합니다.

```bash
source "$HOME/.cargo/env"
./hwp-mac/scripts/build-rust.sh
export RHWP_LIB_SEARCH_PATH="$(pwd)/target/debug"
cd hwp-mac
swift build
```

릴리스:

```bash
source "$HOME/.cargo/env"
./hwp-mac/scripts/build-rust.sh release
export RHWP_LIB_SEARCH_PATH="$(pwd)/target/release"
cd hwp-mac
swift build -c release
```

## 실행

`swift run HwpMacApp`로 직접 실행하면 터미널 자식 프로세스로 떠서 포커스나 상단 메뉴바가 불안정할 수 있습니다. macOS에서는 `.app` 번들로 여는 방식이 더 안전합니다.

문서 없이 실행:

```bash
source "$HOME/.cargo/env"
export RHWP_LIB_SEARCH_PATH="$(pwd)/target/debug"
./hwp-mac/scripts/run-app.sh
```

문서를 바로 열면서 실행:

```bash
source "$HOME/.cargo/env"
export RHWP_LIB_SEARCH_PATH="$(pwd)/target/debug"
./hwp-mac/scripts/run-app.sh samples/re-align-left.hwp
```

릴리스 실행:

```bash
source "$HOME/.cargo/env"
export RHWP_LIB_SEARCH_PATH="$(pwd)/target/release"
./hwp-mac/scripts/run-app.sh --release
```

개발 중 빠르게 다시 확인하려면:

```bash
source "$HOME/.cargo/env"
export RHWP_LIB_SEARCH_PATH="$(pwd)/target/debug"
./hwp-mac/scripts/dev-watch.sh
```

## 개발 메모

- `Package.swift`는 존재하는 Rust 라이브러리 경로만 링커에 전달합니다.
- 메뉴 명령은 활성 `DocumentController`에 연결됩니다.
- 툴바는 웹 버전의 2단 레이아웃을 유지하되 macOS 컨트롤 톤으로 다시 구성했습니다.
- 자세한 기능 현황은 `../docs/feature-status.md`에 정리합니다.

## 다음 후보 작업

- 표 병합/분할 및 셀 속성 패널
- 더 정교한 폰트/자간/베이스라인 보정
- 중첩 셀/글상자 `cellPath` 완전 지원
- `.app` 패키징과 실제 창 기반 검증 자동화
