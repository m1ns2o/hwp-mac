//! 역공학용 HWP 샘플 자동 생성 테스트
//!
//! 기존 HWP 파일을 템플릿으로 로드하고 텍스트를 교체하여
//! 통제된 역공학 샘플을 생성한다.
//! 생성된 파일은 작업지시자가 한컴에서 열어 검증한다.

#[cfg(test)]
mod tests {
    use std::path::Path;
    use std::fs;

    /// 템플릿 HWP 로드 → 텍스트 교체 → 저장
    fn generate_sample(
        template_path: &str,
        output_path: &str,
        texts: &[&str],
    ) -> Result<(), String> {
        generate_sample_with_options(template_path, output_path, texts, None, None)
    }

    /// 폰트를 코드로 변경 (한컴의 방식을 재현)
    /// ko_font: 한글 폰트, en_font: 영문 폰트 (None이면 한글과 동일)
    fn apply_font(core: &mut crate::document_core::DocumentCore, ko_font: &str, en_font: Option<&str>) {
        let en = en_font.unwrap_or(ko_font);
        let doc = &mut core.document;

        // 1. font_faces에 새 폰트 추가 (이미 있으면 인덱스 반환)
        let add_font = |fonts: &mut Vec<crate::model::style::Font>, name: &str| -> u16 {
            if let Some(idx) = fonts.iter().position(|f| f.name == name) {
                return idx as u16;
            }
            fonts.push(crate::model::style::Font {
                raw_data: None,
                name: name.to_string(),
                alt_type: 0,
                alt_name: None,
                default_name: None,
            });
            (fonts.len() - 1) as u16
        };

        // 모든 언어 카테고리에 폰트 추가
        let mut ko_ids = [0u16; 7];
        let mut en_ids = [0u16; 7];
        for (lang_idx, lang_fonts) in doc.doc_info.font_faces.iter_mut().enumerate() {
            ko_ids[lang_idx] = add_font(lang_fonts, ko_font);
            en_ids[lang_idx] = add_font(lang_fonts, en);
        }

        // 2. CharShape의 font_ids 설정
        // 문단이 참조하는 CharShape를 찾아 font_ids 변경
        let para_cs_id = doc.sections[0].paragraphs[0].char_shapes
            .first().map(|cs| cs.char_shape_id as usize).unwrap_or(0);

        if para_cs_id < doc.doc_info.char_shapes.len() {
            let cs = &mut doc.doc_info.char_shapes[para_cs_id];
            for lang in 0..7 {
                cs.font_ids[lang] = if lang == 1 { en_ids[lang] } else { ko_ids[lang] };
            }
            cs.raw_data = None;
        }

        // 3. raw_stream 무효화
        doc.doc_info.raw_stream = None;
        doc.doc_info.raw_stream_dirty = true;
    }

    /// 폰트 지정 샘플 생성
    fn generate_sample_with_font(
        _template_path: &str,
        output_path: &str,
        texts: &[&str],
        font_name: Option<&str>,
    ) -> Result<(), String> {
        generate_sample_with_font_pair(output_path, texts, font_name, None, None)
    }

    /// 한글/영문 폰트 별도 지정 샘플 생성
    fn generate_sample_with_font_pair(
        output_path: &str,
        texts: &[&str],
        ko_font: Option<&str>,
        en_font: Option<&str>,
        alignment: Option<crate::model::style::Alignment>,
    ) -> Result<(), String> {
        generate_sample_with_options("template/empty.hwp", output_path, texts, ko_font, alignment)?;

        // 폰트 적용이 필요한 경우 저장된 파일을 다시 로드하여 폰트 변경
        if let Some(ko) = ko_font {
            let data = fs::read(output_path).map_err(|e| e.to_string())?;
            let mut core = crate::document_core::DocumentCore::from_bytes(&data)
                .map_err(|e| format!("{:?}", e))?;
            apply_font(&mut core, ko, en_font);
            core.document.sections[0].raw_stream = None;

            // LINE_SEG 채워진 버전 저장
            let bytes = crate::serializer::serialize_document(&core.document)
                .map_err(|e| format!("{:?}", e))?;
            fs::write(output_path, &bytes).map_err(|e| e.to_string())?;

            // LINE_SEG 비운 버전 저장
            let empty_path = output_path.replace(".hwp", "-empty.hwp");
            for para in &mut core.document.sections[0].paragraphs {
                para.line_segs = vec![crate::model::paragraph::LineSeg::default()];
            }
            core.document.sections[0].raw_stream = None;
            let empty_bytes = crate::serializer::serialize_document(&core.document)
                .map_err(|e| format!("{:?}", e))?;
            fs::write(&empty_path, &empty_bytes).map_err(|e| e.to_string())?;
            eprintln!("생성: {} (폰트: ko={}, en={})", output_path, ko, en_font.unwrap_or(ko));
        }
        Ok(())
    }

    /// 템플릿에 DocumentCore API로 텍스트 삽입하여 샘플 생성
    fn generate_sample_with_options(
        template_path: &str,
        output_path: &str,
        texts: &[&str],
        _font_name: Option<&str>,  // 미사용 (폰트는 템플릿으로 결정)
        alignment: Option<crate::model::style::Alignment>,
    ) -> Result<(), String> {
        let tmpl = Path::new(template_path);
        if !tmpl.exists() {
            return Err(format!("템플릿 없음: {}", template_path));
        }
        let data = fs::read(tmpl).map_err(|e| e.to_string())?;
        let mut core = crate::document_core::DocumentCore::from_bytes(&data)
            .map_err(|e| format!("{:?}", e))?;

        // 정렬 변경
        if let Some(align) = alignment {
            let para = &core.document.sections[0].paragraphs[0];
            let ps_id = para.para_shape_id as usize;
            if ps_id < core.document.doc_info.para_shapes.len() {
                core.document.doc_info.para_shapes[ps_id].alignment = align;
                core.document.doc_info.para_shapes[ps_id].raw_data = None;
                core.document.doc_info.raw_stream = None;
                core.document.doc_info.raw_stream_dirty = true;
            }
        }

        // 첫 문단에 텍스트 삽입 (DocumentCore API 사용)
        if let Some(first_text) = texts.first() {
            let _ = core.insert_text_native(0, 0, 0, first_text);
        }

        // 추가 문단: Enter로 문단 분할 후 텍스트 삽입
        for (i, text) in texts.iter().enumerate().skip(1) {
            // 이전 문단 끝에서 Enter
            let prev_para = &core.document.sections[0].paragraphs[i - 1];
            let end_pos = prev_para.text.chars().count();
            let _ = core.split_paragraph_native(0, i - 1, end_pos);
            // 새 문단에 텍스트 삽입
            let _ = core.insert_text_native(0, i, 0, text);
        }

        // raw_stream 무효화
        core.document.sections[0].raw_stream = None;

        // 1. LINE_SEG가 채워진 버전 저장 (rhwp 렌더링 확인용)
        let bytes = crate::serializer::serialize_document(&core.document)
            .map_err(|e| format!("{:?}", e))?;
        fs::write(output_path, &bytes).map_err(|e| e.to_string())?;
        eprintln!("생성: {} ({}문단)", output_path, texts.len());

        // 2. LINE_SEG를 비운 버전 저장 (한컴 역공학용: *-empty.hwp)
        let empty_path = output_path.replace(".hwp", "-empty.hwp");
        for para in &mut core.document.sections[0].paragraphs {
            para.line_segs = vec![crate::model::paragraph::LineSeg::default()];
        }
        core.document.sections[0].raw_stream = None;
        let empty_bytes = crate::serializer::serialize_document(&core.document)
            .map_err(|e| format!("{:?}", e))?;
        fs::write(&empty_path, &empty_bytes).map_err(|e| e.to_string())?;
        eprintln!("생성: {} (LINE_SEG 비움)", empty_path);

        Ok(())
    }

    /// 한글만 반복하여 지정 길이의 텍스트 생성
    fn hangul_repeat(pattern: &str, target_chars: usize) -> String {
        let chars: Vec<char> = pattern.chars().collect();
        let mut result = String::new();
        for i in 0..target_chars {
            result.push(chars[i % chars.len()]);
        }
        result
    }

    /// 한글+공백 패턴 생성 ("가 나 다 라 ...")
    fn hangul_with_spaces(pattern: &str, target_chars: usize) -> String {
        let chars: Vec<char> = pattern.chars().collect();
        let mut result = String::new();
        let mut count = 0;
        let mut ci = 0;
        while count < target_chars {
            result.push(chars[ci % chars.len()]);
            count += 1;
            if count < target_chars {
                result.push(' ');
                count += 1;
            }
            ci += 1;
        }
        result
    }

    // ─── 1차 샘플: 기본 폭 측정 ───

    #[test]
    fn test_gen_re01_hangul_only() {
        // 한글만 반복 (공백 없음), 2~3줄 분량
        // A4 바탕체 10pt: 한 줄 약 43자 → 100자면 ~2.3줄
        let text = hangul_repeat("가나다라마바사아자차카타파하", 100);
        let result = generate_sample(
            "samples/lseg-01-basic.hwp",
            "samples/re-01-hangul-only.hwp",
            &[&text],
        );
        if let Err(e) = result {
            eprintln!("re-01 생성 실패: {}", e);
        }
    }

    #[test]
    fn test_gen_re02_space_count() {
        // 한글+공백 ("가 나 다 라 ..."), 2~3줄
        let text = hangul_with_spaces("가나다라마바사아자차카타파하", 100);
        let result = generate_sample(
            "samples/lseg-01-basic.hwp",
            "samples/re-02-space-count.hwp",
            &[&text],
        );
        if let Err(e) = result {
            eprintln!("re-02 생성 실패: {}", e);
        }
    }

    #[test]
    fn test_gen_re03_latin_only() {
        // 영문만 반복, 2~3줄
        let text = "abcdefghijklmnopqrstuvwxyz".repeat(8); // 208자
        let result = generate_sample(
            "samples/lseg-01-basic.hwp",
            "samples/re-03-latin-only.hwp",
            &[&text],
        );
        if let Err(e) = result {
            eprintln!("re-03 생성 실패: {}", e);
        }
    }

    #[test]
    fn test_gen_re04_digit_only() {
        // 숫자만 반복, 2~3줄
        let text = "1234567890".repeat(20); // 200자
        let result = generate_sample(
            "samples/lseg-01-basic.hwp",
            "samples/re-04-digit-only.hwp",
            &[&text],
        );
        if let Err(e) = result {
            eprintln!("re-04 생성 실패: {}", e);
        }
    }

    #[test]
    fn test_gen_re05_mixed_koen() {
        // 한영 혼합 반복, 2~3줄
        let base = "한글English한글English";
        let text = base.repeat(8);
        let result = generate_sample(
            "samples/lseg-01-basic.hwp",
            "samples/re-05-mixed-koen.hwp",
            &[&text],
        );
        if let Err(e) = result {
            eprintln!("re-05 생성 실패: {}", e);
        }
    }

    #[test]
    fn test_gen_re06_punctuation() {
        // 구두점 포함 한글, 2~3줄
        let base = "가,나.다!라?마(바)사[아]자{차}";
        let text = base.repeat(5);
        let result = generate_sample(
            "samples/lseg-01-basic.hwp",
            "samples/re-06-punctuation.hwp",
            &[&text],
        );
        if let Err(e) = result {
            eprintln!("re-06 생성 실패: {}", e);
        }
    }

    // ─── 폰트별 샘플 ───

    #[test]
    fn test_gen_re_font_variations() {
        let fonts = [
            ("batang", "바탕"),
            ("batangche", "바탕체"),
            ("gulim", "굴림"),
            ("gulimche", "굴림체"),
            ("dotum", "돋움"),
            ("dotumche", "돋움체"),
            ("malgun", "맑은 고딕"),
        ];

        // 동일한 테스트 텍스트 (한글+영문+숫자+구두점 혼합)
        let text = "가나다라 English 12345 가,나.다! 마바사아 test 67890 자차카타파하";
        let long_text = format!("{} {}", text, text); // 2줄 이상

        for (suffix, font_name) in &fonts {
            let output = format!("samples/re-font-{}.hwp", suffix);
            let result = generate_sample_with_font(
                "samples/lseg-01-basic.hwp",
                &output,
                &[&long_text],
                Some(font_name),
            );
            match result {
                Ok(()) => eprintln!("생성: {} (폰트: {})", output, font_name),
                Err(e) => eprintln!("실패: {} — {}", output, e),
            }
        }
    }

    // ─── 정렬별 샘플 ───

    #[test]
    fn test_gen_re_alignment_variations() {
        use crate::model::style::Alignment;

        let aligns = [
            ("justify", Alignment::Justify),
            ("left", Alignment::Left),
            ("center", Alignment::Center),
            ("right", Alignment::Right),
        ];

        let text = hangul_repeat("가나다라마바사아자차카타파하", 100);

        for (suffix, alignment) in &aligns {
            let output = format!("samples/re-align-{}.hwp", suffix);
            let result = generate_sample_with_options(
                "samples/lseg-01-basic.hwp",
                &output,
                &[&text],
                None,
                Some(*alignment),
            );
            match result {
                Ok(()) => eprintln!("생성: {} (정렬: {:?})", output, alignment),
                Err(e) => eprintln!("실패: {} — {}", output, e),
            }
        }
    }

    // ─── 폰트 설정 분석 (Task 404) ───

    #[test]
    fn test_analyze_font_config() {
        let templates = [
            "template/empty.hwp",
            "template/blank-batang.hwp",
            "template/blank-dotum.hwp",
            "template/blank-batangche.hwp",
            "template/blank-malgun.hwp",
            "samples/re-eng-mixed-batang-arial-empty.hwp",
        ];

        for path in &templates {
            let p = Path::new(path);
            if !p.exists() { continue; }
            let data = fs::read(p).unwrap();
            let doc = crate::parser::parse_document(&data).unwrap();

            eprintln!("\n=== {} ===", path);

            // font_faces: 7개 언어 카테고리별 폰트 목록
            let lang_names = ["한글", "영어", "한자", "일어", "기타", "기호", "사용자"];
            for (li, fonts) in doc.doc_info.font_faces.iter().enumerate() {
                let lang = if li < lang_names.len() { lang_names[li] } else { "?" };
                let names: Vec<&str> = fonts.iter().map(|f| f.name.as_str()).collect();
                eprintln!("  font_faces[{}]({}): {:?}", li, lang, names);
            }

            // char_shapes: font_ids 확인
            for (ci, cs) in doc.doc_info.char_shapes.iter().enumerate() {
                eprintln!("  char_shapes[{}]: font_ids={:?} base_size={}", ci, cs.font_ids, cs.base_size);
            }
        }
    }

    // ─── 영문 폰트별 샘플 (Task 404) ───

    #[test]
    fn test_gen_re_english_font_variations() {
        // 가변폭 + 고정폭 폰트로 순수 영문 테스트
        // 한글/영문 폰트 조합 테스트
        let fonts: Vec<(&str, &str, Option<&str>)> = vec![
            // (접미사, 한글폰트, 영문폰트)
            ("batang", "바탕", None),              // 한영 동일: 바탕
            ("batangche", "바탕체", None),          // 한영 동일: 바탕체 (고정폭)
            ("dotum", "돋움", None),               // 한영 동일: 돋움
            ("malgun", "맑은 고딕", None),          // 한영 동일: 맑은 고딕
            ("batang-arial", "바탕", Some("Arial")), // 한글=바탕, 영문=Arial
            ("dotum-times", "돋움", Some("Times New Roman")), // 한글=돋움, 영문=Times
            ("malgun-courier", "맑은 고딕", Some("Courier New")), // 한글=맑은고딕, 영문=Courier(고정폭)
        ];

        // 순수 영문 (공백 없이 연속 — char_level_break 경로)
        let latin_nospace = "abcdefghijklmnopqrstuvwxyz".repeat(8);
        // 영문 단어 (공백 포함 — 정상 줄바꿈 경로)
        let latin_words = "The quick brown fox jumps over the lazy dog and then runs back again to test line breaking behavior in this sample document ";
        let latin_words_long = latin_words.repeat(3);
        // 한영 혼합
        let mixed = "한글과English가Mixed된Text입니다Test문장Sentence한글English한글English";
        let mixed_long = mixed.repeat(3);

        for (suffix, ko_font, en_font) in &fonts {
            // 영문 연속 (공백 없음)
            let output = format!("samples/re-eng-nospace-{}.hwp", suffix);
            let _ = generate_sample_with_font_pair(&output, &[&latin_nospace], Some(ko_font), *en_font, None);

            // 영문 단어 (공백 있음)
            let output = format!("samples/re-eng-words-{}.hwp", suffix);
            let _ = generate_sample_with_font_pair(&output, &[&latin_words_long], Some(ko_font), *en_font, None);

            // 한영 혼합
            let output = format!("samples/re-eng-mixed-{}.hwp", suffix);
            let _ = generate_sample_with_font_pair(&output, &[&mixed_long], Some(ko_font), *en_font, None);
        }
    }

    // ─── 일괄 생성 ───

    #[test]
    fn test_gen_all_re_samples() {
        test_gen_re01_hangul_only();
        test_gen_re02_space_count();
        test_gen_re03_latin_only();
        test_gen_re04_digit_only();
        test_gen_re05_mixed_koen();
        test_gen_re06_punctuation();
        eprintln!("\n=== 1차 샘플 생성 완료 ===");
        eprintln!("검증 필요: samples/re-01 ~ re-06.hwp를 한컴에서 열어 확인");
    }
}
