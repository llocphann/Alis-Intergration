use gtk4::gdk;
use gtk4::gio;
use gtk4::glib;
use gtk4::prelude::*;
use serde_json::Value;
use std::cell::RefCell;
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

static THEME_GEN: AtomicU64 = AtomicU64::new(1);

thread_local! {
    static CURRENT_PALETTE: RefCell<AlisPalette> = RefCell::new(AlisPalette::default());
}

pub fn current_theme_gen() -> u64 {
    THEME_GEN.load(Ordering::Relaxed)
}

pub fn current_palette() -> AlisPalette {
    CURRENT_PALETTE.with(|p| p.borrow().clone())
}

#[derive(Debug, Clone, Copy)]
pub struct Rgba {
    pub r: f64,
    pub g: f64,
    pub b: f64,
    pub a: f64,
}

impl Rgba {
    pub const fn new(r: f64, g: f64, b: f64, a: f64) -> Self {
        Self { r, g, b, a }
    }

    pub fn from_hex(hex: &str) -> Option<Self> {
        let s = hex.trim().strip_prefix('#')?;
        match s.len() {
            3 => {
                let r = u8::from_str_radix(&s[0..1], 16).ok()? * 17;
                let g = u8::from_str_radix(&s[1..2], 16).ok()? * 17;
                let b = u8::from_str_radix(&s[2..3], 16).ok()? * 17;
                Some(Self::new(r as f64 / 255.0, g as f64 / 255.0, b as f64 / 255.0, 1.0))
            }
            6 => {
                let r = u8::from_str_radix(&s[0..2], 16).ok()?;
                let g = u8::from_str_radix(&s[2..4], 16).ok()?;
                let b = u8::from_str_radix(&s[4..6], 16).ok()?;
                Some(Self::new(r as f64 / 255.0, g as f64 / 255.0, b as f64 / 255.0, 1.0))
            }
            8 => {
                let r = u8::from_str_radix(&s[0..2], 16).ok()?;
                let g = u8::from_str_radix(&s[2..4], 16).ok()?;
                let b = u8::from_str_radix(&s[4..6], 16).ok()?;
                let a = u8::from_str_radix(&s[6..8], 16).ok()?;
                Some(Self::new(
                    r as f64 / 255.0,
                    g as f64 / 255.0,
                    b as f64 / 255.0,
                    a as f64 / 255.0,
                ))
            }
            _ => None,
        }
    }

    pub fn parse(raw: &str) -> Option<Self> {
        let t = raw.trim();
        if t.starts_with('#') {
            return Self::from_hex(t);
        }
        if let Some(inner) = t.strip_prefix("rgb(").and_then(|s| s.strip_suffix(')')) {
            let parts: Vec<f64> = inner
                .split(',')
                .filter_map(|p| p.trim().parse::<f64>().ok())
                .collect();
            if parts.len() == 3 {
                return Some(Self::new(
                    (parts[0] / 255.0).clamp(0.0, 1.0),
                    (parts[1] / 255.0).clamp(0.0, 1.0),
                    (parts[2] / 255.0).clamp(0.0, 1.0),
                    1.0,
                ));
            }
        }
        if let Some(inner) = t.strip_prefix("rgba(").and_then(|s| s.strip_suffix(')')) {
            let parts: Vec<f64> = inner
                .split(',')
                .filter_map(|p| p.trim().parse::<f64>().ok())
                .collect();
            if parts.len() == 4 {
                return Some(Self::new(
                    (parts[0] / 255.0).clamp(0.0, 1.0),
                    (parts[1] / 255.0).clamp(0.0, 1.0),
                    (parts[2] / 255.0).clamp(0.0, 1.0),
                    parts[3].clamp(0.0, 1.0),
                ));
            }
        }
        None
    }

    pub fn mix(self, other: Self, t: f64) -> Self {
        let t = t.clamp(0.0, 1.0);
        Self {
            r: self.r + (other.r - self.r) * t,
            g: self.g + (other.g - self.g) * t,
            b: self.b + (other.b - self.b) * t,
            a: self.a + (other.a - self.a) * t,
        }
    }

    pub fn with_alpha(self, a: f64) -> Self {
        Self {
            a: a.clamp(0.0, 1.0),
            ..self
        }
    }

    pub fn luminance(self) -> f64 {
        let lin = |x: f64| {
            if x <= 0.04045 {
                x / 12.92
            } else {
                ((x + 0.055) / 1.055).powf(2.4)
            }
        };
        0.2126 * lin(self.r) + 0.7152 * lin(self.g) + 0.0722 * lin(self.b)
    }

    pub fn contrast(self, other: Self) -> f64 {
        let la = self.luminance();
        let lb = other.luminance();
        (la.max(lb) + 0.05) / (la.min(lb) + 0.05)
    }

    pub fn to_css(self) -> String {
        let r = (self.r.clamp(0.0, 1.0) * 255.0).round() as u8;
        let g = (self.g.clamp(0.0, 1.0) * 255.0).round() as u8;
        let b = (self.b.clamp(0.0, 1.0) * 255.0).round() as u8;
        if (self.a - 1.0).abs() < 0.004 {
            format!("#{r:02x}{g:02x}{b:02x}")
        } else {
            format!("rgba({r}, {g}, {b}, {:.3})", self.a.clamp(0.0, 1.0))
        }
    }
}

/// Complete `inir-files` derived palette grounded from Alis's live `colors.json`,
/// `app-palette.json`, `theme-meta.json`, and `app-look.json`.
#[derive(Debug, Clone)]
pub struct AlisPalette {
    pub light: bool,
    pub rail: Rgba,
    pub aside_card: Rgba,
    pub canvas: Rgba,
    pub card: Rgba,
    pub raised: Rgba,
    pub line: Rgba,
    pub fill: Rgba,
    pub fill_hover: Rgba,
    pub fill_press: Rgba,
    pub inset: Rgba,
    pub inset_shadow: Rgba,
    pub inset_light: Rgba,
    pub edge: Rgba,
    pub ink: Rgba,
    pub ink2: Rgba,
    pub ink3: Rgba,
    pub ink_nav: Rgba,
    pub accent: Rgba,
    pub ink_accent: Rgba,
    pub accent_ink: Rgba,
    pub accent_plate: Rgba,
    pub secondary_container: Rgba,
    pub selection: Rgba,
    pub selection_hover: Rgba,
    pub secondary: Rgba,
    pub tertiary: Rgba,
    pub danger: Rgba,
    pub warning: Rgba,
    pub success: Rgba,
    pub folder_front: Rgba,
    pub folder_back: Rgba,
    pub folder_mark: Rgba,
    pub paper: Rgba,
    pub paper_fold: Rgba,
    pub sans_font: String,
    pub mono_font: String,
    pub canvas_radius: i32,
    pub radius: i32,
}

impl Default for AlisPalette {
    fn default() -> Self {
        Self::derive(&HashMap::new(), false, "sans-serif", "monospace", 1.0)
    }
}

impl AlisPalette {
    pub fn derive(
        map: &HashMap<String, String>,
        light: bool,
        sans_font: &str,
        mono_font: &str,
        rounding_scale: f64,
    ) -> Self {
        let pick = |keys: &[&str], dark_fb: &str, light_fb: &str| -> Rgba {
            for k in keys {
                if let Some(raw) = map.get(*k)
                    && let Some(c) = Rgba::parse(raw)
                {
                    return c;
                }
            }
            Rgba::from_hex(if light { light_fb } else { dark_fb })
                .unwrap_or(Rgba::new(0.1, 0.1, 0.12, 1.0))
        };

        let white = Rgba::new(1.0, 1.0, 1.0, 1.0);
        let black = Rgba::new(0.0, 0.0, 0.0, 1.0);

        // Exact M3 surface hierarchy matching Alis Overlay (`colLayer0`, `colLayer1`, `colLayer2`, `colLayer3`)
        let surface = pick(&["surface", "background", "app_window_bg"], "#0a0f0d", "#f8f9fb");
        let high = pick(&["surface_container_high", "app_dialog_bg", "app_popover_bg"], "#19211e", "#e1e3e8");
        let card_base = pick(&["surface_container", "app_card_bg", "app_surface"], "#141b18", "#e8e9ee");
        let low_opt = ["surface_container_low", "app_view_bg"]
            .iter()
            .find_map(|k| map.get(*k).and_then(|raw| Rgba::parse(raw)));
        let surface_low = low_opt.unwrap_or_else(|| {
            if light {
                surface.mix(white, 0.5)
            } else {
                surface.mix(high, 0.38)
            }
        });

        let rail = surface;
        let canvas = if light {
            surface.mix(white, 0.45)
        } else {
            surface_low
        };
        let aside_card = canvas;
        let card = if light {
            white
        } else {
            card_base
        };
        let ink = pick(&["on_surface", "app_foreground", "on_background"], "#e6e7eb", "#1a1b1f");
        let raised = if light {
            white
        } else {
            high
        };

        let line = if light {
            black.with_alpha(0.09)
        } else {
            white.with_alpha(0.08)
        };
        let fill = if light {
            black.with_alpha(0.05)
        } else {
            white.with_alpha(0.06)
        };
        let fill_hover = if light {
            black.with_alpha(0.085)
        } else {
            white.with_alpha(0.10)
        };
        let fill_press = if light {
            black.with_alpha(0.12)
        } else {
            white.with_alpha(0.14)
        };

        let inset = if light {
            black.with_alpha(0.05)
        } else {
            rail
        };
        let inset_shadow = if light {
            black.with_alpha(0.10)
        } else {
            black.with_alpha(0.42)
        };
        let inset_light = if light {
            white.with_alpha(0.90)
        } else {
            white.with_alpha(0.08)
        };
        let edge = if light {
            white.with_alpha(0.90)
        } else {
            white.with_alpha(0.085)
        };

        // WCAG >= 4.5:1 legible secondary & tertiary ink on card, aside_card, and canvas
        let legible = |start_share: f64| -> Rgba {
            let mut at = start_share;
            while at < 1.0 {
                let c = card.mix(ink, at);
                if c.contrast(card) >= 4.5 && c.contrast(aside_card) >= 4.5 && c.contrast(canvas) >= 4.5 {
                    return c;
                }
                at += 0.04;
            }
            ink
        };
        let ink2 = legible(0.70);
        let ink3 = legible(0.56);
        let ink_nav = aside_card.mix(ink, 0.88);

        let accent = pick(&["primary", "app_accent"], "#a8c7fa", "#2f62c9");
        let ink_accent = pick(
            &["on_primary", "app_on_accent"],
            if accent.luminance() > 0.4 { "#0d0e11" } else { "#ffffff" },
            if accent.luminance() > 0.4 { "#0d0e11" } else { "#ffffff" },
        );
        let secondary_container = pick(&["secondary_container"], "#294038", "#d7e6de");
        let raw_on_sec = pick(&["on_secondary_container"], "#abc5ba", "#1a332a");
        let on_secondary_container = if raw_on_sec.contrast(secondary_container) >= 4.5 {
            raw_on_sec
        } else if ink.contrast(secondary_container) >= 4.5 {
            ink
        } else if accent.contrast(secondary_container) >= 4.5 {
            accent
        } else {
            white
        };
        let accent_ink = {
            let mut chosen = ink;
            for cand in [accent, on_secondary_container, ink] {
                if cand.contrast(secondary_container) >= 4.5
                    && cand.contrast(aside_card) >= 4.5
                    && cand.contrast(canvas) >= 4.5
                {
                    chosen = cand;
                    break;
                }
            }
            chosen
        };
        let accent_plate = secondary_container;
        let selection = accent.with_alpha(if light { 0.20 } else { 0.24 });
        let selection_hover = accent.with_alpha(if light { 0.27 } else { 0.31 });

        let secondary = pick(&["secondary"], "#bfc6dc", "#565e71");
        let tertiary = pick(&["tertiary", "app_warning"], "#debcdf", "#715573");
        let danger = pick(&["error", "app_error"], "#ff453a", "#d70015");
        let warning = Rgba::from_hex(if light { "#b25000" } else { "#ffb340" }).unwrap();
        let success = pick(&["success", "app_success"], "#30d158", "#248a3d");

        // Folders & paper colors matching Theme.qml
        let folder_front = if light { accent.mix(white, 0.42) } else { accent };
        let folder_back = if light {
            accent.mix(white, 0.18)
        } else {
            accent.mix(black, 0.28)
        };
        let folder_mark = folder_front.mix(black, 0.55).with_alpha(0.55);
        let paper = if light { white } else { surface.mix(ink, 0.16) };
        let paper_fold = if light {
            white.mix(black, 0.10)
        } else {
            surface.mix(ink, 0.28)
        };

        let shape = rounding_scale.clamp(0.0, 2.0);
        let radius = (12.0 * shape).round().max(4.0) as i32;
        let canvas_radius = (18.0 * shape).round().max(8.0) as i32;

        Self {
            light,
            rail,
            aside_card,
            canvas,
            card,
            raised,
            line,
            fill,
            fill_hover,
            fill_press,
            inset,
            inset_shadow,
            inset_light,
            edge,
            ink,
            ink2,
            ink3,
            ink_nav,
            accent,
            ink_accent,
            accent_ink,
            accent_plate,
            secondary_container,
            selection,
            selection_hover,
            secondary,
            tertiary,
            danger,
            warning,
            success,
            folder_front,
            folder_back,
            folder_mark,
            paper,
            paper_fold,
            sans_font: sans_font.to_string(),
            mono_font: mono_font.to_string(),
            canvas_radius,
            radius,
        }
    }

    pub fn kind_color(&self, kind: crate::model::FileKind) -> Rgba {
        use crate::model::FileKind;
        match kind {
            FileKind::Image | FileKind::Video => self.tertiary,
            FileKind::Audio | FileKind::Archive => self.secondary,
            FileKind::Pdf | FileKind::Document | FileKind::Executable => self.accent,
            _ => self.ink3,
        }
    }

    pub fn to_css(&self) -> String {
        let knob_bg = if self.light {
            "#ffffff".to_string()
        } else {
            self.rail.mix(self.ink, 0.16).to_css()
        };
        let tab_active_bg = if self.light {
            "#ffffff".to_string()
        } else {
            self.canvas.mix(self.ink, 0.08).to_css()
        };
        let badge_fg = if self.light { "#ffffff" } else { "#0f1013" };
        let sel_focus_border = self.accent.with_alpha(0.7).to_css();
        let focus_soft = self.accent.with_alpha(0.55).to_css();
        let pane_focus_border = self.aside_card.mix(self.ink, 0.13).to_css();
        let split_focus_line = self.canvas.mix(self.ink, 0.16).to_css();
        let rail_kbd_border = self.aside_card.mix(self.ink, 0.16).to_css();
        let glass_ring_bg = "rgba(0, 0, 0, 0.32)";
        let tooltip_border = self.accent.with_alpha(0.28).to_css();

        format!(
            r#"
/* Alis Files — inir-files visual architecture over live Alis palette */
window.alis-files-window,
.alis-files-window {{
    background-color: {rail};
    color: {ink};
    font-family: "{sans}", sans-serif;
}}

/* Frameless rounded workspace card floating over the Rail backdrop */
.alis-canvas-card {{
    background-color: {canvas};
    border-radius: {canvas_radius}px;
    border: 1px solid transparent;
    margin-top: 8px;
    margin-bottom: 8px;
}}

/* Unified TabStrip at top of canvas (auto-hidden when 1 single tab) */
.alis-tabstrip {{
    background-color: transparent;
    padding: 6px 10px 0px 10px;
}}

.alis-tab-btn {{
    background-color: transparent;
    color: {ink2};
    border-radius: 10px;
    padding: 4px 8px;
    min-height: 28px;
    border: 1px solid transparent;
    box-shadow: none;
    transition: background-color 80ms ease-out;
}}

.alis-tab-btn:hover {{
    background-color: {fill};
    color: {ink};
}}

.alis-tab-btn.tab-active {{
    background-color: {accent_plate};
    color: {accent_ink};
    font-weight: 600;
    border-color: {sel_focus_border};
}}

.alis-split-tab-group {{
    background-color: {fill};
    border: 1px solid {line};
    border-radius: 11px;
    padding: 2px;
    transition: background-color 80ms ease-out, border-color 110ms ease-out;
}}

.alis-split-tab-group.tab-active {{
    background-color: {tab_active_bg};
    border: 1px solid {accent};
}}

.alis-split-tab-half {{
    background-color: transparent;
    color: {ink2};
    border-radius: 8px;
    padding: 2px 6px;
    min-height: 24px;
    border: none;
    box-shadow: none;
    transition: background-color 80ms ease-out;
}}

.alis-split-tab-half:hover {{
    background-color: {fill_hover};
    color: {ink};
}}

.alis-split-tab-half.half-active {{
    background-color: {accent_plate};
    color: {accent_ink};
    font-weight: 600;
}}

.alis-split-tab-sep {{
    background-color: {line};
    min-width: 1px;
    margin: 4px 1px;
}}

.alis-tab-close {{
    background-color: transparent;
    color: {ink3};
    border-radius: 999px;
    min-width: 20px;
    min-height: 20px;
    padding: 0px;
    border: none;
    box-shadow: none;
}}

.alis-tab-close:hover {{
    background-color: {fill_hover};
    color: {ink};
}}

/* Directional Alt+h/j/k/l Pane Focus Borders (unchanged background, low-contrast border) */
.alis-sidebar.pane-focused,
.alis-aside-card.pane-focused,
.alis-canvas-card.pane-focused {{
    border: 1px solid {pane_focus_border};
}}

.alis-pane.pane-split-focused {{
    border-top: 1px solid {split_focus_line};
}}

.alis-pane.pane-inactive {{
    border-top: 1px solid transparent;
}}

.alis-sidebar-row.rail-kbd-focus {{
    outline: 1px solid {rail_kbd_border};
    outline-offset: -1px;
}}

/* Head bar (58px, WindowHandle empty-drag surface, zero OS titlebar) */
.alis-head {{
    background-color: transparent;
    padding: 10px 10px 8px 10px;
    min-height: 38px;
}}

/* Quiet Act glyph buttons */
.alis-act-btn,
.alis-tool-btn {{
    background-color: transparent;
    color: {ink2};
    border-radius: {radius}px;
    min-width: 32px;
    min-height: 32px;
    padding: 4px 6px;
    border: none;
    box-shadow: none;
    transition: background-color 80ms ease-out;
}}

.alis-act-btn:hover,
.alis-tool-btn:hover {{
    background-color: {fill};
    color: {ink};
}}

.alis-act-btn:active,
.alis-tool-btn:active {{
    background-color: {fill_press};
}}

.alis-act-btn.toggled,
.alis-tool-btn.toggled {{
    background-color: {accent_plate};
    color: {accent_ink};
}}

.alis-act-btn.round {{
    border-radius: 999px;
}}

.alis-act-btn:disabled,
.alis-tool-btn:disabled {{
    opacity: 0.38;
}}

/* Recessed Inset PathBar & Search Field */
.alis-inset {{
    background-color: {inset};
    border-radius: {radius}px;
    border-top: 1px solid {inset_shadow};
    border-bottom: 1px solid {inset_light};
    border-left: 1px solid transparent;
    border-right: 1px solid transparent;
    padding: 2px 6px;
    min-height: 32px;
}}

.alis-inset.focused {{
    border: 2px solid {sel_focus_border};
}}

.alis-crumb-btn {{
    background-color: transparent;
    color: {ink2};
    border-radius: 8px;
    padding: 3px 8px;
    min-height: 24px;
    border: none;
    box-shadow: none;
    transition: background-color 65ms ease-out;
}}

.alis-crumb-btn:hover {{
    background-color: {fill};
    color: {ink};
}}

.alis-crumb-btn.crumb-current {{
    color: {ink};
    font-weight: 600;
}}

.alis-crumb-sep {{
    color: {ink3};
    font-size: 12px;
}}

entry.alis-path-entry,
searchentry.alis-path-entry {{
    background-color: {inset};
    color: {ink};
    border-radius: {radius}px;
    border-top: 1px solid {inset_shadow};
    border-bottom: 1px solid {inset_light};
    border-left: none;
    border-right: none;
    padding: 4px 10px;
    min-height: 30px;
    box-shadow: none;
}}

entry.alis-path-entry:focus,
searchentry.alis-path-entry:focus {{
    outline: 2px solid {sel_focus_border};
}}

/* Recessed Pill Segments View Switcher */
.alis-segments {{
    background-color: {inset};
    border-radius: 999px;
    border-top: 1px solid {inset_shadow};
    border-bottom: 1px solid {inset_light};
    padding: 3px;
    min-height: 28px;
}}

.alis-seg-btn {{
    background-color: transparent;
    color: {ink2};
    border-radius: 999px;
    padding: 3px 10px;
    min-width: 28px;
    min-height: 24px;
    border: none;
    border-top: 1px solid transparent;
    box-shadow: none;
    transition: background-color 110ms ease-out;
}}

.alis-seg-btn:hover {{
    color: {ink};
}}

.alis-seg-btn.active {{
    background-color: {knob_bg};
    color: {ink};
    font-weight: 600;
    border-top: 1px solid {edge};
}}

/* Left Places Rail as independent floating card */
.alis-sidebar {{
    background-color: {aside_card};
    border-radius: 16px;
    border: 1px solid transparent;
    padding: 8px 6px;
    margin: 8px 0px 8px 8px;
}}

.alis-sidebar-section-btn {{
    background-color: transparent;
    color: {ink3};
    font-size: 11px;
    font-weight: 700;
    letter-spacing: 0.05em;
    padding: 8px 12px 4px 12px;
    border: none;
    border-radius: 8px;
    box-shadow: none;
}}

.alis-sidebar-section-btn:hover {{
    color: {ink2};
}}

.alis-sidebar-section-title {{
    color: {ink3};
    font-size: 11px;
    font-weight: 700;
    letter-spacing: 0.05em;
    padding: 8px 12px 4px 12px;
}}

.alis-sidebar-row {{
    border-radius: 10px;
    padding: 6px 8px;
    margin: 1px 2px;
    min-width: 0;
    min-height: 22px;
    color: {ink_nav};
    background-color: transparent;
    border: none;
    box-shadow: none;
    transition: background-color 65ms ease-out;
}}

.alis-sidebar-row:hover {{
    background-color: {fill};
    color: {ink};
}}

.alis-sidebar-row.active-place {{
    background-color: {accent_plate};
    color: {accent_ink};
    font-weight: 600;
}}

.alis-drive-bar,
.alis-drive-bar trough {{
    min-width: 0;
    min-height: 3px;
    border-radius: 99px;
    background-color: {fill_press};
}}

.alis-drive-bar progress {{
    min-height: 3px;
    border-radius: 99px;
    background-color: {accent};
}}

/* Panes inside Canvas (no harsh top border; inactive uses muted fill_press selection) */
.alis-pane {{
    background-color: transparent;
}}

.alis-resize-handle {{
    min-width: 8px;
    background-color: transparent;
}}

.alis-resize-grip {{
    min-width: 2px;
    min-height: 44px;
    border-radius: 999px;
    background-color: {accent};
    opacity: 0.0;
    transition: opacity 140ms ease, background-color 140ms ease;
}}

.alis-resize-handle:hover .alis-resize-grip,
.alis-resize-handle.dragging .alis-resize-grip {{
    background-color: {accent};
    opacity: 1.0;
}}

paned > separator {{
    min-width: 6px;
    min-height: 6px;
    background-color: transparent;
    background-image: linear-gradient(to right, transparent 2px, {line} 2px, {line} 4px, transparent 4px);
    transition: background-image 140ms ease;
}}

paned > separator:hover,
paned > separator:active {{
    background-image: linear-gradient(to right, transparent 2px, {accent} 2px, {accent} 4px, transparent 4px);
}}

/* List view headings & rows (Line.qml + ListPane.qml) */
.alis-list-header {{
    background-color: transparent;
    border-bottom: 1px solid {line};
    padding: 2px 10px;
    min-height: 28px;
    color: {ink3};
    font-size: 12px;
    font-weight: 600;
}}

.alis-list-header button {{
    background-color: transparent;
    color: {ink3};
    border-radius: 7px;
    padding: 2px 8px;
    border: none;
    box-shadow: none;
}}

.alis-list-header button:hover {{
    background-color: {fill};
    color: {ink2};
}}

.alis-list-header button.sorted-col {{
    color: {ink};
}}

.alis-file-list {{
    background-color: transparent;
    padding: 4px 6px;
}}

listview.alis-file-list > row {{
    background-color: transparent;
    padding: 0px;
    margin: 1px 2px;
    border-radius: 8px;
}}

listview.alis-file-list > row:hover {{
    background-color: {fill};
}}

listview.alis-file-list > row:selected {{
    background-color: {selection};
    color: {ink};
}}

listview.alis-file-list > row:focus,
listview.alis-file-list > row:focus-visible {{
    outline: none;
    outline-width: 0px;
    outline-color: transparent;
}}

listview.alis-file-list > row:focus:not(:selected) {{
    background-color: {fill};
}}

.alis-pane.pane-inactive listview.alis-file-list > row:selected {{
    background-color: {fill_press};
}}

.alis-list-row-inner {{
    padding: 4px 10px;
    border-radius: 8px;
}}

/* Grid view (Cell.qml): transparent cell wrapper, translucent tint strictly on plate + pill */
.alis-file-grid {{
    background-color: transparent;
    padding: 10px 12px;
}}

gridview.alis-file-grid > child {{
    background-color: transparent;
    border-radius: 14px;
    padding: 0px;
    margin: 2px;
    color: {ink};
}}

.alis-grid-plate {{
    background-color: transparent;
    border-radius: 16px;
    padding: 8px;
    transition: background-color 65ms ease-out;
}}

gridview.alis-file-grid > child:hover .alis-grid-plate {{
    background-color: {fill};
}}

gridview.alis-file-grid > child:focus,
gridview.alis-file-grid > child:focus-visible {{
    outline: none;
    outline-width: 0px;
    outline-color: transparent;
}}

gridview.alis-file-grid > child:focus:not(:selected) .alis-grid-plate {{
    background-color: {fill};
}}

gridview.alis-file-grid > child:selected .alis-grid-plate {{
    background-color: {selection};
}}

gridview.alis-file-grid > child:selected:hover .alis-grid-plate {{
    background-color: {selection_hover};
}}

.alis-pane.pane-inactive gridview.alis-file-grid > child:selected .alis-grid-plate {{
    background-color: {fill_press};
}}

.alis-grid-pill {{
    border-radius: 8px;
    padding: 2px 7px;
    color: {ink};
    background-color: transparent;
}}

gridview.alis-file-grid > child:selected .alis-grid-pill {{
    background-color: {selection};
}}

.alis-pane.pane-inactive gridview.alis-file-grid > child:selected .alis-grid-pill {{
    background-color: {fill_press};
}}

/* Gallery view (Tile.qml): crisp square tile with circular check ring */
.alis-gallery-tile {{
    background-color: {fill};
    border-radius: 10px;
    padding: 0px;
    transition: background-color 65ms ease-out;
}}

gridview.alis-file-grid > child:hover .alis-gallery-tile {{
    background-color: {fill_hover};
}}

gridview.alis-file-grid > child:selected .alis-gallery-tile {{
    background-color: {selection};
    padding: 6px;
}}

.alis-pane.pane-inactive gridview.alis-file-grid > child:selected .alis-gallery-tile {{
    background-color: {fill_press};
}}

.alis-gallery-ring {{
    background-color: {glass_ring_bg};
    color: #ffffff;
    border: 1.5px solid #ffffff;
    border-radius: 999px;
    min-width: 22px;
    min-height: 22px;
    font-size: 12px;
    font-weight: 700;
    opacity: 0;
}}

gridview.alis-file-grid > child:hover .alis-gallery-ring {{
    opacity: 1;
}}

gridview.alis-file-grid > child:selected .alis-gallery-ring {{
    opacity: 1;
    background-color: {accent};
    color: {ink_accent};
    border-color: transparent;
}}

.alis-video-badge {{
    background-color: rgba(8, 8, 10, 0.70);
    color: #ffffff;
    border-radius: 999px;
    padding: 2px 6px;
    font-size: 10px;
    font-weight: 700;
}}

.alis-drop-target {{
    outline: 2px solid {accent};
    background-color: {selection_hover};
}}

.alis-drop-target-focus {{
    outline: 2px solid {focus_soft};
}}

.alis-item-cut {{
    opacity: 0.48;
}}

/* Independent Preview & Properties Aside Cards */
.alis-inspector {{
    background-color: transparent;
    padding: 8px 8px 8px 0px;
}}

.alis-aside-card {{
    background-color: {aside_card};
    border-radius: 16px;
    border: 1px solid transparent;
    padding: 10px;
}}

.alis-preview-card {{
    background-color: {card};
    border-radius: 12px;
    padding: 10px;
}}

.alis-inspector-action-btn {{
    background-color: {card};
    color: {ink};
    border-radius: 999px;
    padding: 5px 8px;
    min-width: 0;
    min-height: 28px;
    font-size: 12px;
    border: none;
    box-shadow: none;
}}

.alis-inspector-action-btn:hover {{
    background-color: {fill_hover};
}}

.alis-inspector-paned > separator {{
    min-height: 8px;
    background-color: transparent;
    background-image: none;
    border: none;
    margin: 0px;
}}

.alis-inspector-paned > separator:hover {{
    background-color: {accent};
    border-radius: 999px;
}}

.alis-props-tabs {{
    background-color: {inset};
    border-radius: 10px;
    padding: 2px;
}}

.alis-props-tab-btn {{
    background-color: transparent;
    color: {ink2};
    border-radius: 8px;
    padding: 4px 3px;
    min-width: 0;
    min-height: 24px;
    font-size: 11px;
    font-weight: 500;
    border: none;
    box-shadow: none;
}}

.alis-props-tab-btn:hover {{
    background-color: {fill};
    color: {ink};
}}

.alis-props-tab-btn:checked {{
    background-color: {card};
    color: {ink};
    font-weight: 600;
}}

.alis-props-card {{
    background-color: {card};
    border-radius: 12px;
    padding: 8px 10px;
}}

.alis-perm-toggle {{
    background-color: {card};
    color: {ink2};
    border-radius: 7px;
    padding: 3px 6px;
    min-width: 24px;
    min-height: 24px;
    font-size: 11px;
    font-weight: 600;
    border: none;
    box-shadow: none;
}}

.alis-perm-toggle:hover {{
    background-color: {fill_hover};
    color: {ink};
}}

.alis-perm-toggle:checked {{
    background-color: {secondary_container};
    color: {accent_ink};
}}

.alis-exec-toggle {{
    padding: 5px 10px;
    min-height: 28px;
    border-radius: 8px;
    font-size: 12px;
}}

.alis-props-mono {{
    font-family: "{mono}", monospace;
    font-size: 11px;
    color: {ink2};
}}

.alis-props-match {{
    color: {success};
    font-size: 11px;
    font-weight: 600;
}}

.alis-props-mismatch {{
    color: {danger};
    font-size: 11px;
    font-weight: 600;
}}

/* Abyss Panel Style Tooltips */
tooltip,
tooltip.background {{
    background-color: {raised};
    color: {ink};
    border-radius: 999px;
    border: 1px solid {tooltip_border};
    padding: 4px 10px;
    box-shadow: 0 4px 14px rgba(0, 0, 0, 0.36);
}}

tooltip label {{
    color: {ink};
    font-size: 12px;
}}

/* Status bar (Status.qml, 36px height) */
.alis-statusbar {{
    background-color: transparent;
    border-top: 1px solid {line};
    padding: 4px 14px;
    min-height: 28px;
    color: {ink2};
    font-size: 12.5px;
}}

.alis-status-toast-label {{
    color: {ink};
    font-size: 12.5px;
}}

.alis-status-toast-label.alis-status-toast-error {{
    color: {danger};
    font-weight: 500;
}}

.alis-status-undo-btn {{
    background-color: {accent};
    color: {ink_accent};
    border-radius: 999px;
    padding: 2px 10px;
    min-height: 20px;
    font-size: 11px;
    font-weight: 600;
    border: none;
    box-shadow: none;
}}

.alis-status-undo-btn:hover {{
    opacity: 0.92;
}}

.alis-zoom-scale {{
    padding: 4px 2px;
}}

.alis-zoom-scale trough {{
    min-height: 4px;
    border-radius: 99px;
    background-color: {fill_press};
}}

.alis-zoom-scale highlight {{
    min-height: 4px;
    border-radius: 99px;
    background-color: {accent};
}}

.alis-zoom-scale slider {{
    min-width: 14px;
    min-height: 14px;
    margin: -5px;
    border-radius: 99px;
    background-color: {knob_bg};
    border: 1px solid {line};
}}

.alis-vim-pill {{
    background-color: {accent_plate};
    color: {accent_ink};
    border-radius: 999px;
    padding: 2px 8px;
    font-size: 11px;
    font-weight: 700;
}}

.alis-subtext {{
    color: {ink2};
    font-size: 12px;
}}

.alis-muted {{
    color: {ink3};
    font-size: 12px;
}}

.alis-dim {{
    color: {ink2};
}}

.alis-git-badge {{
    font-size: 10px;
    font-weight: 700;
    border-radius: 6px;
    padding: 1px 5px;
}}

.alis-git-modified {{
    background-color: {warning};
    color: {badge_fg};
}}

.alis-git-added,
.alis-git-untracked {{
    background-color: {success};
    color: {badge_fg};
}}

.alis-git-deleted,
.alis-git-conflict {{
    background-color: {danger};
    color: {badge_fg};
}}

.alis-git-ignored {{
    background-color: {fill_press};
    color: {ink3};
}}

.alis-filter-bar {{
    background-color: transparent;
    border-bottom: 1px solid {line};
    padding: 6px 12px;
}}

/* Raised Popovers, Command Palette, Toast & Sheets */
.alis-toast {{
    background-color: {raised};
    color: {ink};
    border: 1px solid {line};
    border-top: 1px solid {edge};
    border-radius: 14px;
    padding: 8px 14px;
}}

popover.menu contents,
popover contents {{
    background-color: {raised};
    color: {ink};
    border: 1px solid {line};
    border-radius: 14px;
    padding: 6px;
}}

.alis-dialog-surface {{
    background-color: {raised};
    color: {ink};
    border-radius: 16px;
}}

.alis-card {{
    background-color: {card};
    border-top: 1px solid {edge};
    border-radius: 16px;
    padding: 12px;
}}

.alis-accent-btn {{
    background-color: {accent};
    color: {ink_accent};
    border-radius: 999px;
    padding: 6px 16px;
    font-weight: 600;
    border: none;
    box-shadow: none;
}}

.alis-accent-btn:hover {{
    opacity: 0.92;
}}

.alis-flat-btn {{
    background-color: {fill};
    color: {ink};
    border-radius: 999px;
    padding: 6px 14px;
    border: none;
    box-shadow: none;
}}

.alis-flat-btn:hover {{
    background-color: {fill_hover};
}}

.alis-danger-btn {{
    background-color: {danger};
    color: {badge_fg};
    border-radius: 999px;
    padding: 6px 16px;
    font-weight: 600;
    border: none;
}}

.alis-quicklook-surface {{
    background-color: #0b0b0d;
    color: #f4f5f7;
}}

.alis-code-view,
.alis-code-view text {{
    background-color: {canvas};
    color: {ink};
    font-family: "{mono}", monospace;
    font-size: 13px;
}}

.alis-disk-bar trough {{
    min-height: 8px;
    border-radius: 99px;
    background-color: {fill_press};
}}

.alis-disk-bar progress {{
    min-height: 8px;
    border-radius: 99px;
    background-color: {accent};
}}

scrollbar slider {{
    background-color: {fill_press};
    border-radius: 99px;
    min-width: 6px;
    min-height: 6px;
}}

scrollbar slider:hover {{
    background-color: {ink3};
}}
"#,
            rail = self.rail.to_css(),
            aside_card = self.aside_card.to_css(),
            canvas = self.canvas.to_css(),
            pane_focus_border = pane_focus_border,
            split_focus_line = split_focus_line,
            rail_kbd_border = rail_kbd_border,
            card = self.card.to_css(),
            raised = self.raised.to_css(),
            line = self.line.to_css(),
            fill = self.fill.to_css(),
            fill_hover = self.fill_hover.to_css(),
            fill_press = self.fill_press.to_css(),
            inset = self.inset.to_css(),
            inset_shadow = self.inset_shadow.to_css(),
            inset_light = self.inset_light.to_css(),
            edge = self.edge.to_css(),
            ink = self.ink.to_css(),
            ink2 = self.ink2.to_css(),
            ink3 = self.ink3.to_css(),
            ink_nav = self.ink_nav.to_css(),
            accent = self.accent.to_css(),
            ink_accent = self.ink_accent.to_css(),
            accent_ink = self.accent_ink.to_css(),
            accent_plate = self.accent_plate.to_css(),
            secondary_container = self.secondary_container.to_css(),
            tooltip_border = tooltip_border,
            selection = self.selection.to_css(),
            selection_hover = self.selection_hover.to_css(),
            danger = self.danger.to_css(),
            warning = self.warning.to_css(),
            success = self.success.to_css(),
            sans = self.sans_font.replace('"', ""),
            mono = self.mono_font.replace('"', ""),
            canvas_radius = self.canvas_radius,
            radius = self.radius,
        )
    }
}

pub fn generated_theme_dir() -> PathBuf {
    crate::config::state_dir().join("quickshell/user/generated")
}

pub fn load_palette_from_dir(dir: &Path) -> AlisPalette {
    let mut map = HashMap::<String, String>::new();
    for filename in ["colors.json", "app-palette.json"] {
        let p = dir.join(filename);
        if let Ok(raw) = fs::read_to_string(&p)
            && let Ok(Value::Object(obj)) = serde_json::from_str::<Value>(&raw)
        {
            for (k, v) in obj {
                if let Some(s) = v.as_str()
                    && Rgba::parse(s).is_some()
                {
                    map.insert(k, s.to_string());
                }
            }
        }
    }

    let mut light = false;
    if let Ok(raw) = fs::read_to_string(dir.join("theme-meta.json"))
        && let Ok(Value::Object(meta)) = serde_json::from_str::<Value>(&raw)
        && meta.get("mode").and_then(|v| v.as_str()) == Some("light")
    {
        light = true;
    } else if let Some(bg) = map
        .get("surface")
        .or_else(|| map.get("background"))
        .or_else(|| map.get("app_window_bg"))
        .and_then(|s| Rgba::parse(s))
    {
        light = bg.luminance() > 0.45;
    }

    let mut sans = "sans-serif".to_string();
    let mut mono = "monospace".to_string();
    let mut rounding_scale = 1.0;
    if let Ok(raw) = fs::read_to_string(dir.join("app-look.json"))
        && let Ok(Value::Object(look)) = serde_json::from_str::<Value>(&raw)
    {
        if let Some(f) = look.get("font").and_then(|v| v.as_str())
            && !f.trim().is_empty()
        {
            sans = f.trim().to_string();
        }
        if let Some(m) = look.get("mono").and_then(|v| v.as_str())
            && !m.trim().is_empty()
        {
            mono = m.trim().to_string();
        }
        if let Some(r) = look.get("rounding").and_then(|v| v.as_f64()) {
            rounding_scale = r;
        }
    }

    AlisPalette::derive(&map, light, &sans, &mono, rounding_scale)
}

fn apply_palette_to_provider(prov: &gtk4::CssProvider, dir: &Path) {
    let palette = load_palette_from_dir(dir);
    CURRENT_PALETTE.with(|p| *p.borrow_mut() = palette.clone());
    THEME_GEN.fetch_add(1, Ordering::Relaxed);
    prov.load_from_string(&palette.to_css());
}

pub struct LiveThemeHandle {
    _monitor: Option<gio::FileMonitor>,
    _provider: gtk4::CssProvider,
}

/// Installs the live Alis theme CssProvider on the default display and watches
/// `~/.local/state/quickshell/user/generated/` so atomic renames from `switchwall.sh`
/// immediately re-theme every open window.
pub fn install_live_theme() -> LiveThemeHandle {
    let provider = gtk4::CssProvider::new();
    let dir = generated_theme_dir();
    apply_palette_to_provider(&provider, &dir);

    if let Some(display) = gdk::Display::default() {
        gtk4::style_context_add_provider_for_display(
            &display,
            &provider,
            gtk4::STYLE_PROVIDER_PRIORITY_APPLICATION,
        );
    }

    let _ = fs::create_dir_all(&dir);
    let gdir = gio::File::for_path(&dir);
    let monitor = gdir
        .monitor_directory(gio::FileMonitorFlags::NONE, gio::Cancellable::NONE)
        .ok();
    if let Some(ref mon) = monitor {
        let prov_clone = provider.clone();
        let dir_clone = dir.clone();
        let pending = std::rc::Rc::new(std::cell::Cell::new(false));
        mon.connect_changed(move |_, file, other, event| {
            let matches_palette = |f: &gio::File| {
                f.basename()
                    .and_then(|n| n.into_os_string().into_string().ok())
                    .map(|n| {
                        matches!(
                            n.as_str(),
                            "app-palette.json" | "colors.json" | "theme-meta.json" | "app-look.json"
                        )
                    })
                    .unwrap_or(false)
            };
            let relevant = matches_palette(file)
                || other.map(matches_palette).unwrap_or(false)
                || matches!(
                    event,
                    gio::FileMonitorEvent::Renamed
                        | gio::FileMonitorEvent::MovedIn
                        | gio::FileMonitorEvent::ChangesDoneHint
                );
            if !relevant || pending.get() {
                return;
            }
            pending.set(true);
            let prov = prov_clone.clone();
            let d = dir_clone.clone();
            let pend = pending.clone();
            glib::timeout_add_local_once(std::time::Duration::from_millis(80), move || {
                pend.set(false);
                apply_palette_to_provider(&prov, &d);
            });
        });
    }

    LiveThemeHandle {
        _monitor: monitor,
        _provider: provider,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn palette_derives_inir_stepped_surfaces_and_wcag_contrast() {
        let dir = std::env::temp_dir().join(format!("alis-files-theme-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        fs::write(
            dir.join("colors.json"),
            r##"{"surface":"#141218","surface_container_high":"#211f26","surface_container_highest":"#2b2930","primary":"#d0bcff","on_surface":"#e6e0e9","secondary":"#ccc2dc","tertiary":"#efb8c8"}"##,
        )
        .unwrap();
        fs::write(
            dir.join("app-palette.json"),
            r##"{"app_accent":"#ffb4ac","app_border_subtle":"not-a-color"}"##,
        )
        .unwrap();
        let p = load_palette_from_dir(&dir);
        assert!(!p.light);
        // Dark mode: canvas should be slightly lighter than outer rail backdrop (Overlay colLayer1 > colLayer0)
        assert!(p.canvas.luminance() > p.rail.luminance());
        // Secondary ink & active badges must maintain WCAG >= 4.5 contrast over canvas, aside_card, and secondary_container
        assert!(p.ink2.contrast(p.canvas) >= 4.5);
        assert!(p.ink2.contrast(p.aside_card) >= 4.5);
        assert!(p.accent_ink.contrast(p.canvas) >= 4.5);
        assert!(p.accent_ink.contrast(p.secondary_container) >= 4.5);
        let css = p.to_css();
        assert!(css.contains(".alis-canvas-card"));
        assert!(css.contains(".alis-aside-card"));
        assert!(css.contains("tooltip.background"));
        assert!(css.contains(".alis-segments"));
        assert!(css.contains(".alis-inset"));
        assert!(css.contains(".alis-gallery-tile"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn light_mode_palette_detects_theme_meta() {
        let dir = std::env::temp_dir().join(format!("alis-files-light-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("theme-meta.json"), r#"{"mode":"light"}"#).unwrap();
        fs::write(
            dir.join("colors.json"),
            r##"{"surface":"#f8f9fb","primary":"#2f62c9","on_surface":"#1a1b1f"}"##,
        )
        .unwrap();
        let p = load_palette_from_dir(&dir);
        assert!(p.light);
        assert!(p.canvas.luminance() > 0.7);
        assert!(p.ink2.contrast(p.canvas) >= 4.5);
        let _ = fs::remove_dir_all(&dir);
    }
}
