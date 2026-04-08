use base64::Engine;
use serde_json::{json, Value};

use crate::document_core::helpers::color_ref_to_css;
use crate::renderer::layout::compute_char_positions;
use crate::renderer::render_tree::{
    BoundingBox, EllipseNode, FieldMarkerType, FormObjectNode, ImageNode, LineNode, PageBackgroundImage,
    PageBackgroundNode, PageNode, PathNode, RenderNode, RenderNodeType, ShapeTransform, TableCellNode,
    TableNode, TextLineNode, TextRunNode,
};
use crate::renderer::{
    ArrowStyle, GradientFillInfo, LineRenderType, LineStyle, PathCommand, PatternFillInfo, ShadowStyle,
    ShapeStyle, StrokeDash, TabLeaderInfo, TabStop, TextStyle,
};

pub fn serialize_page_tree(root: &RenderNode) -> String {
    render_node_to_value(root).to_string()
}

fn render_node_to_value(node: &RenderNode) -> Value {
    let mut value = json!({
        "id": node.id,
        "type": node_type_name(&node.node_type),
        "bbox": bounding_box_value(node.bbox),
        "visible": node.visible,
        "dirty": node.dirty,
        "children": node.children.iter().map(render_node_to_value).collect::<Vec<_>>(),
    });

    let payload = match &node.node_type {
        RenderNodeType::Page(page) => json!({ "page": page_value(page) }),
        RenderNodeType::PageBackground(background) => json!({ "pageBackground": page_background_value(background) }),
        RenderNodeType::MasterPage => json!({}),
        RenderNodeType::Header => json!({}),
        RenderNodeType::Footer => json!({}),
        RenderNodeType::Body { clip_rect } => json!({
            "body": {
                "clipRect": clip_rect.map(|bbox| bounding_box_value(bbox)),
            }
        }),
        RenderNodeType::Column(column_index) => json!({ "column": { "index": column_index } }),
        RenderNodeType::FootnoteArea => json!({}),
        RenderNodeType::TextLine(line) => json!({ "textLine": text_line_value(line) }),
        RenderNodeType::TextRun(run) => json!({ "textRun": text_run_value(run) }),
        RenderNodeType::Table(table) => json!({ "table": table_value(table) }),
        RenderNodeType::TableCell(cell) => json!({ "tableCell": table_cell_value(cell) }),
        RenderNodeType::Line(line) => json!({ "line": line_value(line) }),
        RenderNodeType::Rectangle(rect) => json!({ "rectangle": shape_node_value(rect.corner_radius, &rect.style, rect.gradient.as_deref(), rect.section_index, rect.para_index, rect.control_index, rect.transform) }),
        RenderNodeType::Ellipse(ellipse) => json!({ "ellipse": ellipse_value(ellipse) }),
        RenderNodeType::Path(path) => json!({ "path": path_value(path) }),
        RenderNodeType::Image(image) => json!({ "image": image_value(image) }),
        RenderNodeType::Group(group) => json!({
            "group": {
                "sectionIndex": group.section_index,
                "paraIndex": group.para_index,
                "controlIndex": group.control_index,
            }
        }),
        RenderNodeType::TextBox => json!({}),
        RenderNodeType::Equation(equation) => json!({
            "equation": {
                "svgContent": equation.svg_content,
                "color": equation.color_str,
                "fontSize": equation.font_size,
                "sectionIndex": equation.section_index,
                "paraIndex": equation.para_index,
                "controlIndex": equation.control_index,
                "cellIndex": equation.cell_index,
                "cellParaIndex": equation.cell_para_index,
            }
        }),
        RenderNodeType::FormObject(form) => json!({ "formObject": form_value(form) }),
        RenderNodeType::FootnoteMarker(marker) => json!({
            "footnoteMarker": {
                "number": marker.number,
                "text": marker.text,
                "fontFamily": marker.font_family,
                "baseFontSize": marker.base_font_size,
                "color": color_ref_to_css(marker.color),
                "sectionIndex": marker.section_index,
                "paraIndex": marker.para_index,
                "controlIndex": marker.control_index,
            }
        }),
    };

    if let Some(object) = value.as_object_mut() {
        if let Some(payload_object) = payload.as_object() {
            for (key, nested_value) in payload_object {
                object.insert(key.clone(), nested_value.clone());
            }
        }
    }

    value
}

fn node_type_name(node_type: &RenderNodeType) -> &'static str {
    match node_type {
        RenderNodeType::Page(_) => "Page",
        RenderNodeType::PageBackground(_) => "PageBackground",
        RenderNodeType::MasterPage => "MasterPage",
        RenderNodeType::Header => "Header",
        RenderNodeType::Footer => "Footer",
        RenderNodeType::Body { .. } => "Body",
        RenderNodeType::Column(_) => "Column",
        RenderNodeType::FootnoteArea => "FootnoteArea",
        RenderNodeType::TextLine(_) => "TextLine",
        RenderNodeType::TextRun(_) => "TextRun",
        RenderNodeType::Table(_) => "Table",
        RenderNodeType::TableCell(_) => "TableCell",
        RenderNodeType::Line(_) => "Line",
        RenderNodeType::Rectangle(_) => "Rectangle",
        RenderNodeType::Ellipse(_) => "Ellipse",
        RenderNodeType::Path(_) => "Path",
        RenderNodeType::Image(_) => "Image",
        RenderNodeType::Group(_) => "Group",
        RenderNodeType::TextBox => "TextBox",
        RenderNodeType::Equation(_) => "Equation",
        RenderNodeType::FormObject(_) => "FormObject",
        RenderNodeType::FootnoteMarker(_) => "FootnoteMarker",
    }
}

fn bounding_box_value(bbox: BoundingBox) -> Value {
    json!({
        "x": bbox.x,
        "y": bbox.y,
        "width": bbox.width,
        "height": bbox.height,
    })
}

fn page_value(page: &PageNode) -> Value {
    json!({
        "pageIndex": page.page_index,
        "width": page.width,
        "height": page.height,
        "sectionIndex": page.section_index,
    })
}

fn page_background_value(background: &PageBackgroundNode) -> Value {
    json!({
        "backgroundColor": background.background_color.map(color_ref_to_css),
        "borderColor": background.border_color.map(color_ref_to_css),
        "borderWidth": background.border_width,
        "gradient": background.gradient.as_deref().map(gradient_value),
        "image": background.image.as_ref().map(page_background_image_value),
    })
}

fn page_background_image_value(image: &PageBackgroundImage) -> Value {
    json!({
        "fillMode": format!("{:?}", image.fill_mode),
        "dataBase64": base64::engine::general_purpose::STANDARD.encode(&image.data),
    })
}

fn text_line_value(line: &TextLineNode) -> Value {
    json!({
        "lineHeight": line.line_height,
        "baseline": line.baseline,
        "sectionIndex": line.section_index,
        "paraIndex": line.para_index,
    })
}

fn text_run_value(run: &TextRunNode) -> Value {
    let char_positions = compute_char_positions(&run.text, &run.style);
    json!({
        "text": run.text,
        "charX": char_positions,
        "style": text_style_value(&run.style),
        "charShapeId": run.char_shape_id,
        "paraShapeId": run.para_shape_id,
        "sectionIndex": run.section_index,
        "paraIndex": run.para_index,
        "charStart": run.char_start,
        "cellContext": run.cell_context.as_ref().map(|context| {
            json!({
                "parentParaIndex": context.parent_para_index,
                "path": context.path.iter().map(|entry| {
                    json!({
                        "controlIndex": entry.control_index,
                        "cellIndex": entry.cell_index,
                        "cellParaIndex": entry.cell_para_index,
                        "textDirection": entry.text_direction,
                    })
                }).collect::<Vec<_>>(),
            })
        }),
        "isParaEnd": run.is_para_end,
        "isLineBreakEnd": run.is_line_break_end,
        "rotation": run.rotation,
        "isVertical": run.is_vertical,
        "borderFillId": run.border_fill_id,
        "baseline": run.baseline,
        "fieldMarker": field_marker_value(run.field_marker),
    })
}

fn field_marker_value(marker: FieldMarkerType) -> Value {
    match marker {
        FieldMarkerType::None => json!({ "type": "None" }),
        FieldMarkerType::FieldBegin => json!({ "type": "FieldBegin" }),
        FieldMarkerType::FieldEnd => json!({ "type": "FieldEnd" }),
        FieldMarkerType::FieldBeginEnd => json!({ "type": "FieldBeginEnd" }),
        FieldMarkerType::ShapeMarker(position) => json!({ "type": "ShapeMarker", "position": position }),
    }
}

fn table_value(table: &TableNode) -> Value {
    json!({
        "rowCount": table.row_count,
        "colCount": table.col_count,
        "borderFillId": table.border_fill_id,
        "sectionIndex": table.section_index,
        "paraIndex": table.para_index,
        "controlIndex": table.control_index,
    })
}

fn table_cell_value(cell: &TableCellNode) -> Value {
    json!({
        "column": cell.col,
        "row": cell.row,
        "colSpan": cell.col_span,
        "rowSpan": cell.row_span,
        "borderFillId": cell.border_fill_id,
        "textDirection": cell.text_direction,
        "clip": cell.clip,
        "modelCellIndex": cell.model_cell_index,
    })
}

fn line_value(line: &LineNode) -> Value {
    json!({
        "x1": line.x1,
        "y1": line.y1,
        "x2": line.x2,
        "y2": line.y2,
        "style": line_style_value(&line.style),
        "sectionIndex": line.section_index,
        "paraIndex": line.para_index,
        "controlIndex": line.control_index,
        "transform": transform_value(line.transform),
    })
}

fn ellipse_value(ellipse: &EllipseNode) -> Value {
    json!({
        "style": shape_style_value(&ellipse.style),
        "gradient": ellipse.gradient.as_deref().map(gradient_value),
        "sectionIndex": ellipse.section_index,
        "paraIndex": ellipse.para_index,
        "controlIndex": ellipse.control_index,
        "transform": transform_value(ellipse.transform),
    })
}

fn path_value(path: &PathNode) -> Value {
    json!({
        "commands": path.commands.iter().map(path_command_value).collect::<Vec<_>>(),
        "style": shape_style_value(&path.style),
        "gradient": path.gradient.as_deref().map(gradient_value),
        "sectionIndex": path.section_index,
        "paraIndex": path.para_index,
        "controlIndex": path.control_index,
        "transform": transform_value(path.transform),
        "connectorEndpoints": path.connector_endpoints.map(|(x1, y1, x2, y2)| {
            json!({
                "x1": x1,
                "y1": y1,
                "x2": x2,
                "y2": y2,
            })
        }),
        "lineStyle": path.line_style.as_ref().map(line_style_value),
    })
}

fn image_value(image: &ImageNode) -> Value {
    json!({
        "binDataId": image.bin_data_id,
        "dataBase64": image.data.as_ref().map(|data| base64::engine::general_purpose::STANDARD.encode(data)),
        "sectionIndex": image.section_index,
        "paraIndex": image.para_index,
        "controlIndex": image.control_index,
        "fillMode": image.fill_mode.map(|mode| format!("{:?}", mode)),
        "originalSize": image.original_size.map(|(width, height)| json!({ "width": width, "height": height })),
        "transform": transform_value(image.transform),
        "crop": image.crop.map(|(left, top, right, bottom)| {
            json!({
                "left": left,
                "top": top,
                "right": right,
                "bottom": bottom,
            })
        }),
    })
}

fn form_value(form: &FormObjectNode) -> Value {
    json!({
        "formType": format!("{:?}", form.form_type),
        "caption": form.caption,
        "text": form.text,
        "foregroundColor": form.fore_color,
        "backgroundColor": form.back_color,
        "value": form.value,
        "enabled": form.enabled,
        "sectionIndex": form.section_index,
        "paraIndex": form.para_index,
        "controlIndex": form.control_index,
        "name": form.name,
    })
}

fn shape_node_value(
    corner_radius: f64,
    style: &ShapeStyle,
    gradient: Option<&GradientFillInfo>,
    section_index: Option<usize>,
    para_index: Option<usize>,
    control_index: Option<usize>,
    transform: ShapeTransform,
) -> Value {
    json!({
        "cornerRadius": corner_radius,
        "style": shape_style_value(style),
        "gradient": gradient.map(gradient_value),
        "sectionIndex": section_index,
        "paraIndex": para_index,
        "controlIndex": control_index,
        "transform": transform_value(transform),
    })
}

fn text_style_value(style: &TextStyle) -> Value {
    json!({
        "fontFamily": style.font_family,
        "fontSize": style.font_size,
        "color": color_ref_to_css(style.color),
        "bold": style.bold,
        "italic": style.italic,
        "underline": format!("{:?}", style.underline),
        "strikethrough": style.strikethrough,
        "letterSpacing": style.letter_spacing,
        "ratio": style.ratio,
        "defaultTabWidth": style.default_tab_width,
        "tabStops": style.tab_stops.iter().map(tab_stop_value).collect::<Vec<_>>(),
        "autoTabRight": style.auto_tab_right,
        "availableWidth": style.available_width,
        "lineXOffset": style.line_x_offset,
        "tabLeaders": style.tab_leaders.iter().map(tab_leader_value).collect::<Vec<_>>(),
        "inlineTabs": style.inline_tabs.iter().map(|tab| json!(tab)).collect::<Vec<_>>(),
        "extraWordSpacing": style.extra_word_spacing,
        "extraCharSpacing": style.extra_char_spacing,
        "outlineType": style.outline_type,
        "shadowType": style.shadow_type,
        "shadowColor": color_ref_to_css(style.shadow_color),
        "shadowOffsetX": style.shadow_offset_x,
        "shadowOffsetY": style.shadow_offset_y,
        "emboss": style.emboss,
        "engrave": style.engrave,
        "superscript": style.superscript,
        "subscript": style.subscript,
        "emphasisDot": style.emphasis_dot,
        "underlineShape": style.underline_shape,
        "strikeShape": style.strike_shape,
        "underlineColor": color_ref_to_css(style.underline_color),
        "strikeColor": color_ref_to_css(style.strike_color),
        "shadeColor": color_ref_to_css(style.shade_color),
    })
}

fn tab_stop_value(tab_stop: &TabStop) -> Value {
    json!({
        "position": tab_stop.position,
        "tabType": tab_stop.tab_type,
        "fillType": tab_stop.fill_type,
    })
}

fn tab_leader_value(leader: &TabLeaderInfo) -> Value {
    json!({
        "startX": leader.start_x,
        "endX": leader.end_x,
        "fillType": leader.fill_type,
    })
}

fn shape_style_value(style: &ShapeStyle) -> Value {
    json!({
        "fillColor": style.fill_color.map(color_ref_to_css),
        "pattern": style.pattern.map(pattern_fill_value),
        "strokeColor": style.stroke_color.map(color_ref_to_css),
        "strokeWidth": style.stroke_width,
        "strokeDash": stroke_dash_name(style.stroke_dash),
        "opacity": style.opacity,
        "shadow": style.shadow.as_ref().map(shadow_value),
    })
}

fn pattern_fill_value(pattern: PatternFillInfo) -> Value {
    json!({
        "patternType": pattern.pattern_type,
        "patternColor": color_ref_to_css(pattern.pattern_color),
        "backgroundColor": color_ref_to_css(pattern.background_color),
    })
}

fn shadow_value(shadow: &ShadowStyle) -> Value {
    json!({
        "shadowType": shadow.shadow_type,
        "color": color_ref_to_css(shadow.color),
        "offsetX": shadow.offset_x,
        "offsetY": shadow.offset_y,
        "alpha": shadow.alpha,
    })
}

fn gradient_value(gradient: &GradientFillInfo) -> Value {
    json!({
        "gradientType": gradient.gradient_type,
        "angle": gradient.angle,
        "centerX": gradient.center_x,
        "centerY": gradient.center_y,
        "colors": gradient.colors.iter().map(|color| color_ref_to_css(*color)).collect::<Vec<_>>(),
        "positions": gradient.positions,
    })
}

fn line_style_value(style: &LineStyle) -> Value {
    json!({
        "color": color_ref_to_css(style.color),
        "width": style.width,
        "dash": stroke_dash_name(style.dash),
        "lineType": line_render_type_name(style.line_type),
        "startArrow": arrow_style_name(style.start_arrow),
        "endArrow": arrow_style_name(style.end_arrow),
        "startArrowSize": style.start_arrow_size,
        "endArrowSize": style.end_arrow_size,
        "shadow": style.shadow.as_ref().map(shadow_value),
    })
}

fn path_command_value(command: &PathCommand) -> Value {
    match command {
        PathCommand::MoveTo(x, y) => json!({ "type": "MoveTo", "x": x, "y": y }),
        PathCommand::LineTo(x, y) => json!({ "type": "LineTo", "x": x, "y": y }),
        PathCommand::CurveTo(x1, y1, x2, y2, x, y) => {
            json!({ "type": "CurveTo", "x1": x1, "y1": y1, "x2": x2, "y2": y2, "x": x, "y": y })
        }
        PathCommand::ArcTo(rx, ry, rotation, large_arc, sweep, x, y) => {
            json!({
                "type": "ArcTo",
                "rx": rx,
                "ry": ry,
                "rotation": rotation,
                "largeArc": large_arc,
                "sweep": sweep,
                "x": x,
                "y": y,
            })
        }
        PathCommand::ClosePath => json!({ "type": "ClosePath" }),
    }
}

fn transform_value(transform: ShapeTransform) -> Value {
    json!({
        "rotation": transform.rotation,
        "horzFlip": transform.horz_flip,
        "vertFlip": transform.vert_flip,
    })
}

fn stroke_dash_name(dash: StrokeDash) -> &'static str {
    match dash {
        StrokeDash::Solid => "Solid",
        StrokeDash::Dash => "Dash",
        StrokeDash::Dot => "Dot",
        StrokeDash::DashDot => "DashDot",
        StrokeDash::DashDotDot => "DashDotDot",
    }
}

fn line_render_type_name(line_type: LineRenderType) -> &'static str {
    match line_type {
        LineRenderType::Single => "Single",
        LineRenderType::Double => "Double",
        LineRenderType::ThinThickDouble => "ThinThickDouble",
        LineRenderType::ThickThinDouble => "ThickThinDouble",
        LineRenderType::ThinThickThinTriple => "ThinThickThinTriple",
    }
}

fn arrow_style_name(style: ArrowStyle) -> &'static str {
    match style {
        ArrowStyle::None => "None",
        ArrowStyle::Arrow => "Arrow",
        ArrowStyle::ConcaveArrow => "ConcaveArrow",
        ArrowStyle::OpenDiamond => "OpenDiamond",
        ArrowStyle::OpenCircle => "OpenCircle",
        ArrowStyle::OpenSquare => "OpenSquare",
        ArrowStyle::Diamond => "Diamond",
        ArrowStyle::Circle => "Circle",
        ArrowStyle::Square => "Square",
    }
}
