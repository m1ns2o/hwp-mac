#!/bin/bash
# npm 배포 전 pkg/ 디렉토리 보완
# wasm-pack build 후 실행

set -e

PKG_DIR="pkg"
VERSION=$(grep '^version' Cargo.toml | head -1 | sed 's/.*"\(.*\)".*/\1/')

echo "📦 npm 패키지 준비 (v${VERSION})"

# package.json 보완
cat > "${PKG_DIR}/package.json" << EOF
{
  "name": "rhwp",
  "version": "${VERSION}",
  "description": "HWP/HWPX file parser and renderer — Rust + WebAssembly",
  "type": "module",
  "main": "rhwp.js",
  "types": "rhwp.d.ts",
  "files": [
    "rhwp_bg.wasm",
    "rhwp.js",
    "rhwp.d.ts",
    "rhwp_bg.wasm.d.ts"
  ],
  "keywords": [
    "hwp",
    "hwpx",
    "hancom",
    "hangul",
    "한글",
    "document",
    "parser",
    "renderer",
    "wasm",
    "webassembly",
    "rust"
  ],
  "repository": {
    "type": "git",
    "url": "https://github.com/edwardkim/rhwp"
  },
  "homepage": "https://edwardkim.github.io/rhwp/",
  "bugs": {
    "url": "https://github.com/edwardkim/rhwp/issues"
  },
  "license": "MIT",
  "author": "Edward Kim",
  "sideEffects": [
    "./snippets/*"
  ]
}
EOF

# npm 패키지용 README
cat > "${PKG_DIR}/README.md" << 'EOF'
# rhwp

**알(R), 모두의 한글** — HWP/HWPX 파일 파서 & 렌더러 (Rust + WebAssembly)

[![npm](https://img.shields.io/npm/v/rhwp)](https://www.npmjs.com/package/rhwp)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## 설치

```bash
npm install rhwp
```

## 사용법

```javascript
import init, { HwpDocument } from 'rhwp';

// WASM 초기화
await init();

// HWP 파일 로드
const response = await fetch('document.hwp');
const buffer = new Uint8Array(await response.arrayBuffer());
const doc = HwpDocument.load(buffer, 'document.hwp');

// 문서 정보
console.log(doc.pageCount);

// SVG 렌더링
const svg = doc.renderPageToSvg(0); // 첫 번째 페이지
document.getElementById('viewer').innerHTML = svg;
```

## Canvas 렌더링

```javascript
import init, { HwpDocument } from 'rhwp';

await init();
const doc = HwpDocument.load(buffer, 'document.hwp');

// Canvas에 렌더링
const canvas = document.getElementById('canvas');
const ctx = canvas.getContext('2d');
doc.renderPageToCanvas(0, ctx, canvas.width, canvas.height);
```

## 기능

- **HWP 5.0** (바이너리) + **HWPX** (XML) 파싱
- 문단, 표, 수식, 이미지, 차트 렌더링
- 페이지네이션 (다단, 표 분할)
- SVG / Canvas 출력
- 머리말/꼬리말/바탕쪽/각주

## 링크

- [온라인 데모](https://edwardkim.github.io/rhwp/)
- [GitHub](https://github.com/edwardkim/rhwp)
- [VS Code 확장](https://marketplace.visualstudio.com/items?itemName=edwardkim.rhwp-vscode)

## Notice

본 제품은 한글과컴퓨터의 한글 문서 파일(.hwp) 공개 문서를 참고하여 개발하였습니다.

## License

MIT
EOF

echo "✅ 완료: ${PKG_DIR}/package.json + README.md"
