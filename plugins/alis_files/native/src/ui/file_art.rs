use crate::model::{FileEntry, FileKind, is_trash_dir};
use crate::thumbnails::LruCache;
use crate::theme::{Rgba, current_palette, current_theme_gen};
use gtk4::cairo;
use gtk4::gdk;
use gtk4::glib;
use gtk4::prelude::*;
use std::cell::RefCell;
use std::f64::consts::PI;

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct FileArtKey {
    theme_gen: u64,
    is_dir: bool,
    kind_idx: u8,
    role: &'static str,
    ext: String,
    size: i32,
}

thread_local! {
    static ART_CACHE: RefCell<LruCache<FileArtKey, gdk::Texture>> = RefCell::new(LruCache::new(512));
}

fn kind_to_u8(k: FileKind) -> u8 {
    match k {
        FileKind::Directory => 0,
        FileKind::Image => 1,
        FileKind::Audio => 2,
        FileKind::Video => 3,
        FileKind::Pdf => 4,
        FileKind::Archive => 5,
        FileKind::Markdown => 6,
        FileKind::Code => 7,
        FileKind::Document => 8,
        FileKind::Text => 9,
        FileKind::Executable => 10,
        FileKind::Other => 11,
    }
}

fn folder_role(entry: &FileEntry) -> &'static str {
    if !entry.is_dir {
        return "";
    }
    if is_trash_dir(&entry.path) {
        return "trash";
    }
    match entry.name.as_str() {
        "Desktop" => "desktop",
        "Documents" => "documents",
        "Downloads" => "downloads",
        "Music" => "music",
        "Pictures" => "pictures",
        "Videos" => "videos",
        _ => {
            if entry.path == crate::config::home_dir() {
                "home"
            } else {
                ""
            }
        }
    }
}

fn short_ext(entry: &FileEntry) -> String {
    if entry.is_dir {
        return String::new();
    }
    entry
        .path
        .extension()
        .map(|e| e.to_string_lossy().to_uppercase())
        .filter(|e| !e.is_empty() && e.len() <= 5)
        .unwrap_or_default()
}

/// Render or retrieve cached `inir-files`-style drawn vector art (`FileArt.qml` design):
/// - Folders (`size >= 30`): back tab + back sheet (`folder_back`), tilted paper insert, front sheet (`folder_front`) + subtle role glyph
/// - Files (`size >= 30`): `paper` page with folded top-right corner (`paper_fold`), tinted kind symbol, and extension tag pill (`size >= 44`)
/// - Tiny (`size < 30`): clean tinted folder or file glyph
pub fn texture_for_entry(entry: &FileEntry, size: i32) -> Option<gdk::Texture> {
    let size = size.clamp(16, 512);
    let theme_gen = current_theme_gen();
    let role = folder_role(entry);
    let ext = short_ext(entry);
    let key = FileArtKey {
        theme_gen,
        is_dir: entry.is_dir,
        kind_idx: kind_to_u8(entry.kind),
        role,
        ext: ext.clone(),
        size,
    };

    if let Some(hit) = ART_CACHE.with(|c| c.borrow_mut().get(&key).cloned()) {
        return Some(hit);
    }

    let tex = render_art(entry.is_dir, entry.kind, role, &ext, size)?;
    ART_CACHE.with(|c| {
        c.borrow_mut().insert(key, tex.clone());
    });
    Some(tex)
}

fn set_source(cr: &cairo::Context, c: Rgba) {
    cr.set_source_rgba(c.r, c.g, c.b, c.a);
}

fn rounded_rect(cr: &cairo::Context, x: f64, y: f64, w: f64, h: f64, r: f64) {
    let r = r.min(w * 0.5).min(h * 0.5).max(0.0);
    cr.new_sub_path();
    cr.arc(x + w - r, y + r, r, -PI / 2.0, 0.0);
    cr.arc(x + w - r, y + h - r, r, 0.0, PI / 2.0);
    cr.arc(x + r, y + h - r, r, PI / 2.0, PI);
    cr.arc(x + r, y + r, r, PI, 3.0 * PI / 2.0);
    cr.close_path();
}

fn draw_kind_glyph(cr: &cairo::Context, kind: FileKind, cx: f64, cy: f64, s: f64, c: Rgba) {
    set_source(cr, c);
    cr.set_line_width((s * 0.12).max(1.3));
    cr.set_line_cap(cairo::LineCap::Round);
    cr.set_line_join(cairo::LineJoin::Round);
    let r = s * 0.36;
    match kind {
        FileKind::Image => {
            rounded_rect(cr, cx - r, cy - r * 0.8, r * 2.0, r * 1.6, s * 0.1);
            let _ = cr.stroke();
            cr.move_to(cx - r * 0.7, cy + r * 0.55);
            cr.line_to(cx - r * 0.15, cy - r * 0.05);
            cr.line_to(cx + r * 0.2, cy + r * 0.3);
            cr.line_to(cx + r * 0.55, cy - r * 0.15);
            cr.line_to(cx + r * 0.8, cy + r * 0.55);
            let _ = cr.stroke();
            cr.arc(cx - r * 0.35, cy - r * 0.28, s * 0.07, 0.0, 2.0 * PI);
            let _ = cr.fill();
        }
        FileKind::Video => {
            rounded_rect(cr, cx - r, cy - r * 0.78, r * 2.0, r * 1.56, s * 0.12);
            let _ = cr.stroke();
            cr.move_to(cx - r * 0.22, cy - r * 0.35);
            cr.line_to(cx + r * 0.38, cy);
            cr.line_to(cx - r * 0.22, cy + r * 0.35);
            cr.close_path();
            let _ = cr.fill();
        }
        FileKind::Audio => {
            cr.arc(cx - r * 0.3, cy + r * 0.45, r * 0.28, 0.0, 2.0 * PI);
            let _ = cr.fill();
            cr.move_to(cx - r * 0.04, cy + r * 0.42);
            cr.line_to(cx - r * 0.04, cy - r * 0.6);
            cr.line_to(cx + r * 0.55, cy - r * 0.42);
            let _ = cr.stroke();
        }
        FileKind::Code => {
            cr.move_to(cx - r * 0.32, cy - r * 0.42);
            cr.line_to(cx - r * 0.78, cy);
            cr.line_to(cx - r * 0.32, cy + r * 0.42);
            let _ = cr.stroke();
            cr.move_to(cx + r * 0.32, cy - r * 0.42);
            cr.line_to(cx + r * 0.78, cy);
            cr.line_to(cx + r * 0.32, cy + r * 0.42);
            let _ = cr.stroke();
        }
        FileKind::Archive => {
            rounded_rect(cr, cx - r * 0.78, cy - r * 0.72, r * 1.56, r * 1.44, s * 0.1);
            let _ = cr.stroke();
            cr.move_to(cx, cy - r * 0.7);
            cr.line_to(cx, cy + r * 0.7);
            let _ = cr.stroke();
        }
        FileKind::Executable => {
            rounded_rect(cr, cx - r, cy - r * 0.78, r * 2.0, r * 1.56, s * 0.12);
            let _ = cr.stroke();
            cr.move_to(cx - r * 0.45, cy - r * 0.25);
            cr.line_to(cx - r * 0.05, cy + r * 0.05);
            cr.line_to(cx - r * 0.45, cy + r * 0.35);
            cr.move_to(cx + r * 0.08, cy + r * 0.35);
            cr.line_to(cx + r * 0.55, cy + r * 0.35);
            let _ = cr.stroke();
        }
        _ => {
            // Document / PDF / Text / Markdown clean lines
            for (dy, w_frac) in [(-0.35, 1.3), (0.0, 1.3), (0.35, 0.85)] {
                cr.move_to(cx - r * 0.65, cy + r * dy);
                cr.line_to(cx - r * 0.65 + r * w_frac, cy + r * dy);
                let _ = cr.stroke();
            }
        }
    }
}

fn draw_folder_role_mark(cr: &cairo::Context, role: &str, cx: f64, cy: f64, s: f64, c: Rgba) {
    if role.is_empty() {
        return;
    }
    set_source(cr, c);
    cr.set_line_width((s * 0.095).max(1.2));
    cr.set_line_cap(cairo::LineCap::Round);
    cr.set_line_join(cairo::LineJoin::Round);
    let r = s * 0.42;
    match role {
        "downloads" => {
            cr.move_to(cx, cy - r * 0.65);
            cr.line_to(cx, cy + r * 0.45);
            cr.move_to(cx - r * 0.5, cy);
            cr.line_to(cx, cy + r * 0.52);
            cr.line_to(cx + r * 0.5, cy);
            cr.move_to(cx - r * 0.55, cy + r * 0.78);
            cr.line_to(cx + r * 0.55, cy + r * 0.78);
            let _ = cr.stroke();
        }
        "home" => {
            cr.move_to(cx - r * 0.7, cy);
            cr.line_to(cx, cy - r * 0.65);
            cr.line_to(cx + r * 0.7, cy);
            cr.move_to(cx - r * 0.45, cy - r * 0.15);
            cr.line_to(cx - r * 0.45, cy + r * 0.65);
            cr.line_to(cx + r * 0.45, cy + r * 0.65);
            cr.line_to(cx + r * 0.45, cy - r * 0.15);
            let _ = cr.stroke();
        }
        "pictures" => draw_kind_glyph(cr, FileKind::Image, cx, cy, s, c),
        "music" => draw_kind_glyph(cr, FileKind::Audio, cx, cy, s, c),
        "videos" => draw_kind_glyph(cr, FileKind::Video, cx, cy, s, c),
        _ => draw_kind_glyph(cr, FileKind::Document, cx, cy, s, c),
    }
}

fn render_art(
    is_dir: bool,
    kind: FileKind,
    role: &str,
    ext: &str,
    size: i32,
) -> Option<gdk::Texture> {
    let pal = current_palette();
    let s = size as f64;
    let mut surface = cairo::ImageSurface::create(cairo::Format::ARgb32, size, size).ok()?;
    {
        let cr = cairo::Context::new(&surface).ok()?;
        cr.set_antialias(cairo::Antialias::Best);

        if size < 30 {
            if is_dir {
                let side = (s * 0.08).round();
                let w = s - 2.0 * side;
                rounded_rect(&cr, side, (s * 0.16).round(), w * 0.44, (s * 0.22).round(), 2.0);
                set_source(&cr, pal.folder_back);
                let _ = cr.fill();
                rounded_rect(&cr, side, (s * 0.28).round(), w, (s * 0.56).round(), (s * 0.12).max(2.0));
                set_source(&cr, pal.folder_front);
                let _ = cr.fill();
            } else {
                let w = (s * 0.72).round();
                let h = (s * 0.88).round();
                let x0 = ((s - w) * 0.5).round();
                let y0 = ((s - h) * 0.5).round();
                rounded_rect(&cr, x0, y0, w, h, 2.5);
                set_source(&cr, pal.paper);
                let _ = cr.fill();
                draw_kind_glyph(&cr, kind, s * 0.5, s * 0.54, s * 0.46, pal.kind_color(kind));
            }
        } else if is_dir {
            let r = (s * 0.085).round().max(2.0);
            let side = (s * 0.04).round();
            let wide = s - 2.0 * side;
            let foot = (s * 0.87).round();

            // Tab + Back sheet
            let back_y = (s * 0.16).round();
            rounded_rect(&cr, side, (s * 0.10).round(), (s * 0.42).round(), (s * 0.20).round(), r);
            set_source(&cr, pal.folder_back);
            let _ = cr.fill();
            rounded_rect(&cr, side, back_y, wide, foot - back_y, r);
            set_source(&cr, pal.folder_back);
            let _ = cr.fill();

            // Tilted paper sheet inside the folder
            let px = (s * 0.12).round();
            let py = (s * 0.22).round();
            let pw = s - 2.0 * px;
            let ph = (s * 0.40).round();
            let _ = cr.save();
            cr.translate(px + pw * 0.5, py + ph * 0.5);
            cr.rotate(-0.045);
            rounded_rect(&cr, -pw * 0.5, -ph * 0.5, pw, ph, (r * 0.6).max(2.0));
            set_source(&cr, pal.paper);
            let _ = cr.fill();
            let _ = cr.restore();

            // Front sheet
            let front_y = (s * 0.31).round();
            rounded_rect(&cr, side, front_y, wide, foot - front_y, r);
            set_source(&cr, pal.folder_front);
            let _ = cr.fill();

            // Subtle light edge along top of front sheet
            set_source(
                &cr,
                Rgba::new(1.0, 1.0, 1.0, if pal.light { 0.55 } else { 0.30 }),
            );
            cr.rectangle(side + r, front_y, wide - 2.0 * r, (s / 96.0).max(1.0));
            let _ = cr.fill();

            if !role.is_empty() && size >= 40 {
                draw_folder_role_mark(
                    &cr,
                    role,
                    s * 0.5,
                    (front_y + foot) * 0.5,
                    s * 0.28,
                    pal.folder_mark,
                );
            }
        } else {
            // File page with folded corner (`FileArt.qml`)
            let w = (s * 0.72).round();
            let h = (s * 0.90).round();
            let x0 = ((s - w) / 2.0 + s * 0.02).round();
            let y0 = ((s - h) / 2.0).round();
            let f = (w * 0.30).round();
            let r = (s * 0.07).round().max(2.0);
            let tint = pal.kind_color(kind);

            cr.new_sub_path();
            cr.move_to(x0 + r, y0);
            cr.line_to(x0 + w - f, y0);
            cr.line_to(x0 + w, y0 + f);
            cr.arc(x0 + w - r, y0 + h - r, r, 0.0, PI / 2.0);
            cr.arc(x0 + r, y0 + h - r, r, PI / 2.0, PI);
            cr.arc(x0 + r, y0 + r, r, PI, 3.0 * PI / 2.0);
            cr.close_path();
            set_source(&cr, pal.paper);
            let _ = cr.fill_preserve();
            if pal.light {
                set_source(&cr, Rgba::new(0.0, 0.0, 0.0, 0.10));
                cr.set_line_width(1.0);
                let _ = cr.stroke();
            } else {
                cr.new_path();
            }

            // Folded corner triangle
            cr.move_to(x0 + w - f, y0);
            cr.line_to(x0 + w - f, y0 + f - r * 0.35);
            cr.arc_negative(x0 + w - f + r * 0.35, y0 + f - r * 0.35, r * 0.35, PI, PI / 2.0);
            cr.line_to(x0 + w, y0 + f);
            cr.close_path();
            set_source(&cr, pal.paper_fold);
            let _ = cr.fill();

            // Center kind glyph
            draw_kind_glyph(
                &cr,
                kind,
                x0 + w * 0.5,
                y0 + h * 0.42,
                s * 0.32,
                tint,
            );

            // Colored extension pill tag at lower-left (`size >= 44`)
            if size >= 44 && !ext.is_empty() && ext.len() <= 5 {
                let tag_h = (s * 0.175).round().max(11.0);
                let font_size = (s * 0.102).max(7.5);
                cr.select_font_face("sans-serif", cairo::FontSlant::Normal, cairo::FontWeight::Bold);
                cr.set_font_size(font_size);
                if let Ok(extents) = cr.text_extents(ext) {
                    let tag_w = (extents.width() + tag_h * 0.85).max(tag_h * 1.4);
                    let tag_x = (x0 - s * 0.04).max(1.0);
                    let tag_y = y0 + h * 0.69;
                    rounded_rect(&cr, tag_x, tag_y, tag_w, tag_h, tag_h * 0.32);
                    set_source(&cr, tint);
                    let _ = cr.fill();

                    let text_col = if tint.luminance() > 0.42 {
                        Rgba::from_hex("#101114").unwrap()
                    } else {
                        Rgba::new(1.0, 1.0, 1.0, 1.0)
                    };
                    set_source(&cr, text_col);
                    cr.move_to(
                        tag_x + (tag_w - extents.width()) * 0.5 - extents.x_bearing(),
                        tag_y + (tag_h + extents.height()) * 0.5 - 0.5,
                    );
                    let _ = cr.show_text(ext);
                }
            }
        }
    }

    surface.flush();
    let stride = surface.stride() as usize;
    let data = surface.data().ok()?;
    let bytes = glib::Bytes::from(&*data);
    let tex = gdk::MemoryTexture::new(
        size,
        size,
        gdk::MemoryFormat::B8g8r8a8Premultiplied,
        &bytes,
        stride,
    );
    Some(tex.upcast())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn renders_folder_and_file_art_textures_and_hits_cache() {
        let dir_entry = FileEntry {
            name: "Downloads".into(),
            path: PathBuf::from("/tmp/Downloads"),
            is_dir: true,
            is_symlink: false,
            is_broken_symlink: false,
            is_hidden: false,
            size: 0,
            modified: None,
            mode: 0o755,
            kind: FileKind::Directory,
            git_badge: None,
            trash_original_path: None,
        };
        let t_dir = texture_for_entry(&dir_entry, 72).expect("folder texture");
        assert_eq!(t_dir.width(), 72);
        assert_eq!(t_dir.height(), 72);

        let file_entry = FileEntry {
            name: "main.rs".into(),
            path: PathBuf::from("/tmp/main.rs"),
            is_dir: false,
            is_symlink: false,
            is_broken_symlink: false,
            is_hidden: false,
            size: 512,
            modified: None,
            mode: 0o644,
            kind: FileKind::Code,
            git_badge: None,
            trash_original_path: None,
        };
        let t1 = texture_for_entry(&file_entry, 72).expect("file texture");
        let t2 = texture_for_entry(&file_entry, 72).expect("cached file texture");
        assert_eq!(t1, t2);
        let t_tiny = texture_for_entry(&file_entry, 22).expect("tiny file texture");
        assert_eq!(t_tiny.width(), 22);
        let t_hidpi = texture_for_entry(&dir_entry, 384).expect("hidpi inspector folder texture");
        assert_eq!(t_hidpi.width(), 384);
        assert_eq!(t_hidpi.height(), 384);
    }
}
