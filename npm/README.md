# @rhwp/core

**알(R), 모두의 한글** — 브라우저에서 HWP 파일을 열어보세요

[![npm](https://img.shields.io/npm/v/@rhwp/core)](https://www.npmjs.com/package/@rhwp/core)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Rust + WebAssembly 기반 HWP/HWPX 파서 & 렌더러입니다.
설치 한 줄, 코드 몇 줄이면 웹 페이지에서 HWP 문서를 렌더링할 수 있습니다.

> **[온라인 데모](https://edwardkim.github.io/rhwp/)** 에서 바로 체험해보세요.

## 빠른 시작 — 처음부터 따라하기

### 1. 프로젝트 생성

```bash
mkdir my-hwp-viewer
cd my-hwp-viewer
npm init -y
npm install @rhwp/core
npm install vite --save-dev
```

### 2. WASM 파일 복사

`@rhwp/core`에 포함된 WASM 바이너리를 웹 서버가 제공할 수 있는 위치에 복사합니다.

```bash
mkdir public
cp node_modules/@rhwp/core/rhwp_bg.wasm public/
```

### 3. HTML 작성 — `index.html`

```html
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8" />
  <title>HWP 뷰어</title>
</head>
<body>
  <input type="file" id="file-input" accept=".hwp,.hwpx" />
  <div id="viewer"></div>
  <script type="module" src="/main.js"></script>
</body>
</html>
```

### 4. JavaScript 작성 — `main.js`

```javascript
import init, { HwpDocument } from '@rhwp/core';

// ① 텍스트 폭 측정 함수 등록 (필수)
// WASM 내부에서 텍스트 레이아웃 계산 시 브라우저의 Canvas API를 사용합니다.
globalThis.measureTextWidth = (font, text) => {
  const ctx = document.createElement('canvas').getContext('2d');
  ctx.font = font;
  return ctx.measureText(text).width;
};

// ② WASM 초기화
await init({ module_or_path: '/rhwp_bg.wasm' });

// ③ 파일 선택 시 렌더링
document.getElementById('file-input').addEventListener('change', async (e) => {
  const file = e.target.files[0];
  if (!file) return;

  const buffer = new Uint8Array(await file.arrayBuffer());
  const doc = new HwpDocument(buffer);

  // SVG로 첫 페이지 렌더링
  const svg = doc.renderPageSvg(0);
  document.getElementById('viewer').innerHTML = svg;

  console.log(`${file.name}: ${doc.pageCount()}페이지`);
});
```

### 5. 실행

```bash
npx vite --port 3000
```

브라우저에서 `http://localhost:3000` 을 열고, HWP 파일을 선택하면 렌더링됩니다.

## API

### 초기화

```javascript
import init, { HwpDocument } from '@rhwp/core';

// WASM 초기화 (페이지 로드 시 1회)
await init({ module_or_path: '/rhwp_bg.wasm' });
```

### 문서 로드

```javascript
// ArrayBuffer에서 로드
const doc = new HwpDocument(new Uint8Array(buffer));

// fetch로 로드
const resp = await fetch('/sample.hwp');
const buf = new Uint8Array(await resp.arrayBuffer());
const doc = new HwpDocument(buf);
```

### SVG 렌더링

```javascript
const pageCount = doc.pageCount();
const svg = doc.renderPageSvg(0);          // 0번째 페이지
document.getElementById('viewer').innerHTML = svg;
```

### 페이지 네비게이션

```javascript
for (let i = 0; i < doc.pageCount(); i++) {
  const svg = doc.renderPageSvg(i);
  // ... 각 페이지 처리
}
```

## 필수 설정: measureTextWidth

WASM 내부에서 텍스트 레이아웃(줄바꿈, 정렬 등)을 계산할 때 브라우저의 Canvas 텍스트 측정 API가 필요합니다.
**문서 로드 전에 반드시 등록**해야 합니다.

```javascript
// 성능 최적화 버전 (Canvas 컨텍스트 재사용)
let ctx = null;
let lastFont = '';
globalThis.measureTextWidth = (font, text) => {
  if (!ctx) ctx = document.createElement('canvas').getContext('2d');
  if (font !== lastFont) { ctx.font = font; lastFont = font; }
  return ctx.measureText(text).width;
};
```

## 지원 기능

- **HWP 5.0** (바이너리) + **HWPX** (XML) 파싱
- 문단, 표, 수식, 이미지, 차트, 도형 렌더링
- 페이지네이션 (다단, 표 행 분할)
- SVG 출력
- 머리말/꼬리말/바탕쪽/각주/미주

## 링크

- [온라인 데모](https://edwardkim.github.io/rhwp/)
- [GitHub](https://github.com/edwardkim/rhwp)
- [VS Code 확장](https://marketplace.visualstudio.com/items?itemName=edwardkim.rhwp-vscode)

## Notice

본 제품은 한글과컴퓨터의 한글 문서 파일(.hwp) 공개 문서를 참고하여 개발하였습니다.

## License

MIT
