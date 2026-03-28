//! LINE_SEG 일치율 측정 통합 테스트
//!
//! HWP 파일을 로드하여 원본 LINE_SEG와 reflow_line_segs() 결과를 비교한다.
//! samples/ 디렉토리에 테스트 파일이 없으면 건너뜀.

#[cfg(test)]
mod tests {
    use std::path::Path;
    use crate::renderer::composer::lineseg_compare::*;
    use crate::renderer::composer::reflow_line_segs;
    use crate::renderer::page_layout::PageLayoutInfo;
    use crate::model::paragraph::LineSeg;

    /// HWP 파일을 파싱하여 Document + ResolvedStyleSet 반환
    fn load_raw(path: &str) -> Option<(crate::model::document::Document, crate::renderer::style_resolver::ResolvedStyleSet)> {
        let p = Path::new(path);
        if !p.exists() {
            eprintln!("테스트 파일 없음: {} — 건너뜀", path);
            return None;
        }
        let data = std::fs::read(p).ok()?;
        let document = crate::parser::parse_document(&data).ok()?;
        let styles = crate::renderer::style_resolver::resolve_styles(
            &document.doc_info,
            96.0, // DEFAULT_DPI
        );
        Some((document, styles))
    }

    /// 섹션의 모든 본문 문단에 대해 LINE_SEG 비교 수행
    fn compare_section(
        document: &mut crate::model::document::Document,
        styles: &crate::renderer::style_resolver::ResolvedStyleSet,
        section_idx: usize,
        dpi: f64,
    ) -> SectionLineSegReport {
        let section = &document.sections[section_idx];
        let page_def = &section.section_def.page_def;

        let total_paragraphs = section.paragraphs.len();
        let mut paragraph_diffs = Vec::new();
        let mut compared = 0usize;
        let mut line_count_match = 0usize;
        let mut line_break_match = 0usize;
        let mut all_match = 0usize;

        for para_idx in 0..total_paragraphs {
            let para = &section.paragraphs[para_idx];

            // 빈 문단이나 LINE_SEG가 없는 문단은 건너뜀
            if para.line_segs.is_empty() || para.text.is_empty() {
                continue;
            }

            // line_height가 0인 문단은 원본 LINE_SEG가 없는 것 (HWPX 등)
            if para.line_segs[0].line_height == 0 {
                continue;
            }

            // 원본 LINE_SEG 복사
            let original_line_segs: Vec<LineSeg> = para.line_segs.clone();

            // ColumnDef 조회
            let column_def = find_column_def_for_paragraph(&section.paragraphs, para_idx);
            let layout = PageLayoutInfo::from_page_def(page_def, &column_def, dpi);
            let col_area = &layout.column_areas[0]; // 기본 단

            // 문단 여백 계산
            let para_style = styles.para_styles.get(para.para_shape_id as usize);
            let margin_left = para_style.map(|s| s.margin_left).unwrap_or(0.0);
            let margin_right = para_style.map(|s| s.margin_right).unwrap_or(0.0);
            let available_width = col_area.width - margin_left - margin_right;

            // reflow 실행 (문단을 임시 clone하여 원본 보존)
            let mut para_clone = para.clone();
            reflow_line_segs(&mut para_clone, available_width, styles, dpi);

            // 비교
            let diff = compare_line_segs(para_idx, &original_line_segs, &para_clone.line_segs);

            compared += 1;
            if diff.line_count_match { line_count_match += 1; }
            if diff.line_breaks_match() { line_break_match += 1; }
            if diff.all_match() { all_match += 1; }

            paragraph_diffs.push(diff);
        }

        SectionLineSegReport {
            section_idx,
            total_paragraphs,
            compared_paragraphs: compared,
            line_count_match_count: line_count_match,
            line_break_match_count: line_break_match,
            all_match_count: all_match,
            paragraph_diffs,
        }
    }

    /// 문단에 적용되는 ColumnDef 찾기 (DocumentCore::find_column_def_for_paragraph와 동일 로직)
    fn find_column_def_for_paragraph(
        paragraphs: &[crate::model::paragraph::Paragraph],
        para_idx: usize,
    ) -> crate::model::page::ColumnDef {
        use crate::model::page::ColumnDef;
        use crate::model::control::Control;
        let mut last_cd = ColumnDef::default();
        for (i, para) in paragraphs.iter().enumerate() {
            if i > para_idx { break; }
            for ctrl in &para.controls {
                if let Control::ColumnDef(cd) = ctrl {
                    last_cd = cd.clone();
                }
            }
        }
        last_cd
    }

    /// 단일 HWP 파일에 대해 전체 섹션 LINE_SEG 비교 리포트 생성
    fn run_comparison(path: &str) -> Option<Vec<SectionLineSegReport>> {
        let (mut document, styles) = load_raw(path)?;
        let dpi = 96.0;
        let sec_count = document.sections.len();

        let mut reports = Vec::new();
        for sec_idx in 0..sec_count {
            let report = compare_section(&mut document, &styles, sec_idx, dpi);
            reports.push(report);
        }
        Some(reports)
    }

    // ─── 일치율 측정 테스트 ───

    #[test]
    fn test_lineseg_compare_basic() {
        let Some(reports) = run_comparison("samples/basic/BookReview.hwp") else { return };
        let report_text = format_report(&reports);
        eprintln!("\n=== BookReview.hwp ===\n{}", report_text);

        let total_compared: usize = reports.iter().map(|r| r.compared_paragraphs).sum();
        if total_compared == 0 {
            eprintln!("비교 대상 문단이 0개 — 건너뜀");
        }
    }

    #[test]
    fn test_lineseg_compare_table_test() {
        let Some(reports) = run_comparison("samples/hwp_table_test.hwp") else { return };
        let report_text = format_report(&reports);
        eprintln!("\n=== hwp_table_test.hwp ===\n{}", report_text);

        let total_compared: usize = reports.iter().map(|r| r.compared_paragraphs).sum();
        assert!(total_compared > 0, "비교 대상 문단이 0개");
    }

    #[test]
    fn test_lineseg_compare_hongbo() {
        let Some(reports) = run_comparison("samples/20250130-hongbo.hwp") else { return };
        let report_text = format_report(&reports);
        eprintln!("\n=== 20250130-hongbo.hwp ===\n{}", report_text);

        let total_compared: usize = reports.iter().map(|r| r.compared_paragraphs).sum();
        assert!(total_compared > 0, "비교 대상 문단이 0개");
    }

    // ─── 문자별 폭 진단 (Task 400) ───

    /// 줄별 텍스트를 추출하고 rhwp 측정 폭 vs available_width를 비교
    #[test]
    fn test_lineseg_width_diagnosis_basic() {
        use crate::renderer::layout::{estimate_text_width, resolved_to_text_style};
        use crate::renderer::style_resolver::detect_lang_category;
        use crate::renderer::composer::find_active_char_shape;

        let Some((document, styles)) = load_raw("samples/lseg-01-basic.hwp") else { return };
        let dpi = 96.0;
        let section = &document.sections[0];
        let page_def = &section.section_def.page_def;
        let column_def = find_column_def_for_paragraph(&section.paragraphs, 0);
        let layout = PageLayoutInfo::from_page_def(page_def, &column_def, dpi);
        let col_area = &layout.column_areas[0];

        for (pi, para) in section.paragraphs.iter().enumerate() {
            if para.line_segs.is_empty() || para.text.is_empty() { continue; }
            if para.line_segs[0].line_height == 0 { continue; }

            let para_style = styles.para_styles.get(para.para_shape_id as usize);
            let margin_left = para_style.map(|s| s.margin_left).unwrap_or(0.0);
            let margin_right = para_style.map(|s| s.margin_right).unwrap_or(0.0);
            let available_width = col_area.width - margin_left - margin_right;
            let available_hwp = crate::renderer::px_to_hwpunit(available_width, dpi);

            let text_chars: Vec<char> = para.text.chars().collect();

            eprintln!("\n=== 문단 {} (줄 {}개, 가용폭 {:.1}px = {} HU) ===",
                pi, para.line_segs.len(), available_width, available_hwp);

            for (li, ls) in para.line_segs.iter().enumerate() {
                let utf16_start = ls.text_start as usize;
                let utf16_end = if li + 1 < para.line_segs.len() {
                    para.line_segs[li + 1].text_start as usize
                } else {
                    para.char_offsets.last().map(|&o| o as usize + 1).unwrap_or(text_chars.len())
                };

                // UTF-16 offset → char index 변환
                let char_start = para.char_offsets.iter()
                    .position(|&o| o as usize >= utf16_start).unwrap_or(0);
                let char_end = para.char_offsets.iter()
                    .position(|&o| o as usize >= utf16_end).unwrap_or(text_chars.len());
                let line_text: String = text_chars[char_start..char_end.min(text_chars.len())].iter().collect();

                // TextStyle 생성
                let active_cs_id = find_active_char_shape(&para.char_shapes, char_start as u32);
                let first_ch = line_text.chars().next().unwrap_or('가');
                let lang = detect_lang_category(first_ch);
                let ts = resolved_to_text_style(&styles, active_cs_id as u32, lang);

                // 줄 전체 폭 측정
                let measured_width = estimate_text_width(&line_text, &ts);
                let measured_hwp = crate::renderer::px_to_hwpunit(measured_width, dpi);
                let orig_seg_width = ls.segment_width;

                // 문자별 개별 폭 합산
                let mut hangul_count = 0usize;
                let mut latin_count = 0usize;
                let mut space_count = 0usize;
                let mut punct_count = 0usize;
                let mut hangul_total = 0.0f64;
                let mut latin_total = 0.0f64;
                let mut space_total = 0.0f64;
                let mut punct_total = 0.0f64;

                for ch in line_text.chars() {
                    let cw = estimate_text_width(&ch.to_string(), &ts);
                    if ch >= '\u{AC00}' && ch <= '\u{D7AF}' {
                        hangul_count += 1; hangul_total += cw;
                    } else if ch.is_ascii_alphabetic() {
                        latin_count += 1; latin_total += cw;
                    } else if ch == ' ' {
                        space_count += 1; space_total += cw;
                    } else {
                        punct_count += 1; punct_total += cw;
                    }
                }

                eprintln!(
                    "  L{}: chars=[{}..{}) len={} | measured={:.1}px({}HU) seg_width={}HU delta={}",
                    li, char_start, char_end, line_text.chars().count(),
                    measured_width, measured_hwp, orig_seg_width,
                    measured_hwp - orig_seg_width
                );
                eprintln!(
                    "    font={} size={:.3}px bold={} ratio={:.2} ls={:.2}",
                    ts.font_family, ts.font_size, ts.bold, ts.ratio, ts.letter_spacing
                );
                eprintln!(
                    "    한글:{}자({:.1}px) 영문:{}자({:.1}px) 공백:{}자({:.1}px) 기타:{}자({:.1}px)",
                    hangul_count, hangul_total, latin_count, latin_total,
                    space_count, space_total, punct_count, punct_total
                );

                // 첫 5글자의 개별 폭 출력
                let detail_chars: Vec<(char, f64)> = line_text.chars().take(10)
                    .map(|ch| (ch, estimate_text_width(&ch.to_string(), &ts)))
                    .collect();
                let detail_str: Vec<String> = detail_chars.iter()
                    .map(|(c, w)| format!("'{}'{:.2}", c, w))
                    .collect();
                eprintln!("    처음10자: {}", detail_str.join(" "));
            }
        }
    }

    // ─── 통제된 샘플 (lseg-*) 개별 비교 ───

    #[test]
    fn test_lineseg_compare_lseg_samples() {
        let sample_files = [
            "samples/lseg-01-basic.hwp",
            "samples/lseg-02-mixed.hwp",
            "samples/lseg-03-spacing.hwp",
            "samples/lseg-04-indent.hwp",
            "samples/lseg-05-tab.hwp",
            "samples/lseg-06-multisize.hwp",
        ];

        for path in &sample_files {
            if let Some(reports) = run_comparison(path) {
                eprintln!("\n=== {} ===", path);
                for r in &reports {
                    eprintln!(
                        "  섹션{}: 문단 {}/{} | 줄수={:.0}% 줄바꿈={:.0}% 전체={:.0}%",
                        r.section_idx, r.compared_paragraphs, r.total_paragraphs,
                        r.line_count_match_rate(),
                        r.line_break_match_rate(),
                        r.all_match_rate(),
                    );
                    let avg = r.avg_field_deltas();
                    if avg.lines_compared > 0 {
                        eprintln!(
                            "    오차: ts={:.1} lh={:.1} bl={:.1} ls={:.1} sw={:.1}",
                            avg.text_start, avg.line_height, avg.baseline_distance, avg.line_spacing, avg.segment_width
                        );
                    }
                    // 불일치 문단 상세 출력
                    for pd in &r.paragraph_diffs {
                        if !pd.all_match() {
                            eprintln!(
                                "    pi={}: 줄 {}→{} {}",
                                pd.para_idx, pd.original_line_count, pd.reflow_line_count,
                                if pd.line_count_match { "필드차이" } else { "줄수불일치" }
                            );
                            for fd in &pd.field_diffs {
                                if !fd.all_match() {
                                    eprintln!(
                                        "      L{}: ts={} lh={} th={} bl={} ls={} sw={} vp={}",
                                        fd.line_idx, fd.text_start_delta, fd.line_height_delta,
                                        fd.text_height_delta, fd.baseline_distance_delta,
                                        fd.line_spacing_delta, fd.segment_width_delta,
                                        fd.vertical_pos_delta
                                    );
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// 전체 samples/ 대상 일괄 비교 (nocapture로 실행하여 리포트 확인)
    #[test]
    fn test_lineseg_compare_all_samples() {
        let sample_files = [
            "samples/basic/BookReview.hwp",
            "samples/basic/KTX.hwp",
            "samples/hwp_table_test.hwp",
            "samples/table-001.hwp",
            "samples/20250130-hongbo.hwp",
            "samples/field-01.hwp",
            "samples/inner-table-01.hwp",
            "samples/eq-01.hwp",
        ];

        let mut all_reports = Vec::new();

        for path in &sample_files {
            if let Some(reports) = run_comparison(path) {
                eprintln!("\n--- {} ---", path);
                for r in &reports {
                    eprintln!(
                        "  섹션{}: 줄수={:.0}% 줄바꿈={:.0}% 전체={:.0}% ({}/{})",
                        r.section_idx,
                        r.line_count_match_rate(),
                        r.line_break_match_rate(),
                        r.all_match_rate(),
                        r.all_match_count,
                        r.compared_paragraphs,
                    );
                }
                all_reports.extend(reports);
            }
        }

        if !all_reports.is_empty() {
            eprintln!("\n{}", format_report(&all_reports));
        }
    }
}
