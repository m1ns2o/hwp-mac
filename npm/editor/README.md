# @rhwp/editor

**알(R), 모두의 한글** — 3줄로 HWP 에디터를 웹 페이지에 임베드

[![npm](https://img.shields.io/npm/v/@rhwp/editor)](https://www.npmjs.com/package/@rhwp/editor)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

웹 페이지에 HWP 에디터를 통째로 임베드합니다.
메뉴, 툴바, 서식, 표 편집 — rhwp-studio의 모든 기능을 그대로 사용할 수 있습니다.

> **[온라인 데모](https://edwardkim.github.io/rhwp/)** 에서 먼저 체험해보세요.

## 설치

```bash
npm install @rhwp/editor
```

## 빠른 시작 — 3줄이면 충분합니다

```html
<!DOCTYPE html>
<html>
<head>
  <title>내 HWP 에디터</title>
  <style>
    #editor { width: 100%; height: 100vh; }
  </style>
</head>
<body>
  <div id="editor"></div>
  <script type="module">
    import { createEditor } from '@rhwp/editor';

    const editor = await createEditor('#editor');
  </script>
</body>
</html>
```

이것만으로 메뉴바, 툴바, 편집 영역, 상태 표시줄이 포함된 완전한 HWP 에디터가 표시됩니다.

## HWP 파일 로드

```javascript
import { createEditor } from '@rhwp/editor';

const editor = await createEditor('#editor');

// 파일 선택 또는 fetch로 HWP 데이터 가져오기
const response = await fetch('document.hwp');
const buffer = await response.arrayBuffer();

// 에디터에 로드
const result = await editor.loadFile(buffer, 'document.hwp');
console.log(`${result.pageCount}페이지 로드 완료`);
```

## API

### createEditor(container, options?)

에디터를 생성하고 컨테이너에 마운트합니다.

```javascript
const editor = await createEditor('#editor');
// 또는
const editor = await createEditor(document.getElementById('editor'));
```

**옵션:**

| 옵션 | 기본값 | 설명 |
|------|--------|------|
| `studioUrl` | `https://edwardkim.github.io/rhwp/` | rhwp-studio URL |
| `width` | `'100%'` | iframe 너비 |
| `height` | `'100%'` | iframe 높이 |

### editor.loadFile(data, fileName?)

HWP 파일을 로드합니다.

```javascript
const result = await editor.loadFile(buffer, 'sample.hwp');
// result = { pageCount: 5 }
```

### editor.pageCount()

현재 문서의 페이지 수를 반환합니다.

```javascript
const count = await editor.pageCount();
```

### editor.getPageSvg(page?)

특정 페이지를 SVG 문자열로 렌더링합니다.

```javascript
const svg = await editor.getPageSvg(0); // 첫 페이지
```

### editor.destroy()

에디터를 제거합니다.

```javascript
editor.destroy();
```

## 셀프 호스팅

기본적으로 `https://edwardkim.github.io/rhwp/`에 호스팅된 에디터를 사용합니다.
자체 서버에서 호스팅하려면:

```bash
# rhwp-studio 빌드
cd rhwp-studio
npm install
npx vite build --base=/your-path/

# 빌드 결과물(dist/)을 서버에 배포
```

```javascript
const editor = await createEditor('#editor', {
  studioUrl: 'https://your-domain.com/your-path/'
});
```

## 패키지 비교

| 패키지 | 용도 |
|--------|------|
| **@rhwp/core** | WASM 파서/렌더러 (직접 API 호출) |
| **@rhwp/editor** | 완전한 에디터 UI (iframe 임베드) |

- 뷰어만 필요하면 → `@rhwp/core`
- 편집 기능이 필요하면 → `@rhwp/editor`

## Notice

본 제품은 한글과컴퓨터의 한글 문서 파일(.hwp) 공개 문서를 참고하여 개발하였습니다.

## License

MIT
