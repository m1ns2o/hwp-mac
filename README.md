# hwp-mac

Rust 기반 `rhwp` 엔진 위에 macOS 전용 SwiftUI/AppKit HWP 편집기를 올리는 저장소입니다.

현재 방향은 다음과 같습니다.

- Rust `DocumentCore`를 문서의 단일 진실원으로 유지
- `src/native_api/`로 네이티브 세션/C ABI surface 제공
- `src/bin/rhwp-mcp.rs`로 AI 에이전트 제어용 MCP 서버 제공
- `hwp-mac/`에서 SwiftUI 셸 + AppKit 편집 표면으로 macOS 에디터 제공

## 현재 포함 범위

- HWP/HWPX 열기
- 빈 문서 생성
- HWP 저장
- 페이지 렌더 트리 기반 페이지 표시
- 클릭/드래그 selection
- 기본 입력, 백스페이스, 엔터, 방향키 이동
- 잘라내기/복사/붙여넣기
- 찾기/바꾸기
- 기본 글자 서식 토글
- 기본 문단 정렬
- 표 삽입, 행/열 추가 및 삭제
- snapshot 기반 undo/redo 골격
- MCP를 통한 문서 열기, 읽기, 배치 편집, 렌더 검증, 저장

## 워크스페이스 구성

```text
src/
├── document_core/        Rust 문서 모델, 파서, 조판, 렌더 질의
├── native_api/           세션 관리, semantic operation, C ABI
└── bin/rhwp-mcp.rs       MCP 서버

hwp-mac/
├── Package.swift
├── scripts/build-rust.sh
└── Sources/
    ├── CRhwpNative/      C 헤더와 shim
    └── HwpMacApp/
        ├── App/          앱 엔트리, 명령, 툴바, 메인 레이아웃
        ├── Bridge/       Rust FFI 세션 래퍼
        ├── Documents/    문서 상태, 편집 orchestration
        ├── Editor/       캔버스, 렌더러, 뷰포트, 명령 버스
        ├── Inspector/    우측 패널 view model
        ├── Models/       native payload 모델
        └── Support/      JSON, 색상 등 공용 유틸

skills/
└── rhwp-mcp/            문서 자동화용 skill 문서
```

## 요구 사항

- macOS 14+
- Xcode 16+ 또는 Swift 6.x
- Rust stable

확인 예시:

```bash
swift --version
rustc --version
cargo --version
```

## 빌드

### 1. Rust 네이티브 라이브러리 빌드

저장소 루트에서 실행합니다.

```bash
source "$HOME/.cargo/env"
./hwp-mac/scripts/build-rust.sh
export RHWP_LIB_SEARCH_PATH="$(pwd)/target/debug"
cd hwp-mac
swift build
```

릴리스 빌드:

```bash
source "$HOME/.cargo/env"
./hwp-mac/scripts/build-rust.sh release
export RHWP_LIB_SEARCH_PATH="$(pwd)/target/release"
cd hwp-mac
swift build -c release
```

## 실행

### macOS 앱 실행

`swift run HwpMacApp`로 직접 실행하면 터미널 자식 프로세스로 떠서 포커스나 상단 메뉴바가 불안정할 수 있습니다. macOS에서는 `.app` 번들로 여는 방식을 권장합니다.

문서 없이 실행:

```bash
source "$HOME/.cargo/env"
export RHWP_LIB_SEARCH_PATH="$(pwd)/target/debug"
./hwp-mac/scripts/run-app.sh
```

샘플 문서를 바로 열면서 실행:

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

### CLI 사용

문서 정보 확인:

```bash
source "$HOME/.cargo/env"
cargo run --bin rhwp -- info samples/re-align-left.hwp
```

SVG 내보내기:

```bash
source "$HOME/.cargo/env"
cargo run --bin rhwp -- export-svg samples/table-001.hwp -o output
```

### MCP 실행

```bash
source "$HOME/.cargo/env"
cargo run --bin rhwp-mcp
```

지원 도구:

- `open_document`
- `create_document`
- `read_document`
- `apply_operations`
- `render_page`
- `save_document`
- `close_document`

## 개발 흐름

권장 순서:

1. Rust 코어 또는 `native_api` 변경
2. `cargo build` 또는 필요한 CLI/MCP smoke test 실행
3. `hwp-mac/scripts/build-rust.sh`
4. `cd hwp-mac && swift build`
5. 샘플 문서로 렌더/편집 확인

개발용 watch 실행:

```bash
source "$HOME/.cargo/env"
export RHWP_LIB_SEARCH_PATH="$(pwd)/target/debug"
./hwp-mac/scripts/dev-watch.sh
```

## 현재 툴바 방향

macOS 툴바는 웹 버전의 `아이콘 바 + 서식 바` 구조를 유지하고, 표현만 macOS에 맞게 정리했습니다.

## 문서 자동화

외부 AI 에이전트는 UI 자동화보다 MCP를 우선 사용하는 방향으로 잡고 있습니다.

기본 워크플로:

1. `open_document`
2. `read_document`
3. `apply_operations`
4. `render_page`
5. `save_document`
6. `close_document`

자세한 워크플로는 [skills/rhwp-mcp/SKILL.md](skills/rhwp-mcp/SKILL.md)에서 볼 수 있습니다.

## 참고 문서

- mac 앱 개별 안내: [hwp-mac/README.md](hwp-mac/README.md)
- 기능 현황: [docs/feature-status.md](docs/feature-status.md)
- 기여/배경 문서: `CONTRIBUTING.md`, `CLAUDE.md`, `mydocs/`
