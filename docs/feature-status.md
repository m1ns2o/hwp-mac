# RHWP Mac Feature Status

## 구현된 기능

- HWP/HWPX 문서 열기
- 새 문서 생성
- HWP 저장
- 페이지 렌더 트리 기반 페이지 표시
- 클릭 이동, 드래그 선택, 방향키 이동
- 기본 텍스트 입력, 백스페이스, 엔터
- 잘라내기, 복사, 붙여넣기
- 찾기, 찾아 바꾸기
- 기본 글자 서식 토글
- 문단 정렬
- 표 삽입, 행/열 추가와 삭제
- snapshot 기반 undo/redo
- MCP 기반 문서 열기, 읽기, 수정, 렌더, 저장

## 현재 확인이 필요한 항목

- 한글 IME 조합 입력 안정성
- `cmd+a`, `cmd+c`, `cmd+v` 같은 기본 편집 단축키
- 빠른 타이핑 시 입력 지연
- 폰트 메트릭 차이로 인한 caret, baseline 정합성

## 다음 이식 우선순위

- 머리말/꼬리말 상세 편집
- 표/셀 속성 고도화
- 하이퍼링크, 문자표, 수식
- 검토 탭 기능
- 웹 버전과의 세부 UI/UX parity 정리

## 빌드와 실행

```bash
source "$HOME/.cargo/env"
./hwp-mac/scripts/build-rust.sh
export RHWP_LIB_SEARCH_PATH="$(pwd)/target/debug"
./hwp-mac/scripts/run-app.sh
```

## 빠른 개발 루프

진짜 hot reload는 아니지만, 소스 변경 시 다시 빌드하고 앱을 재실행하는 watch 스크립트를 쓸 수 있습니다.

```bash
source "$HOME/.cargo/env"
export RHWP_LIB_SEARCH_PATH="$(pwd)/target/debug"
./hwp-mac/scripts/dev-watch.sh
```
