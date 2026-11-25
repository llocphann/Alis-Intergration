use crate::model::{FileEntry, FileKind, format_size, format_time};
use gtk4::gdk;
use gtk4::glib;
use gtk4::prelude::*;
use std::cell::Cell;
use std::fs;
use std::io::Read;
use std::path::Path;
use std::rc::Rc;

pub type QuickLookIndexCallback = Rc<dyn Fn(&FileEntry)>;

/// Open instant `inir-files`-style Quick Look cinema overlay (`Space`):
/// dark `#0b0b0d` canvas, minimal 56px header, Left/Right stepping across items in the folder,
/// multi-page PDF stepping, video/audio playback, and text/code preview.
pub fn open_quicklook_items(
    parent: &gtk4::ApplicationWindow,
    items: Vec<FileEntry>,
    initial_idx: usize,
    on_index_changed: Option<QuickLookIndexCallback>,
) {
    if items.is_empty() {
        return;
    }
    let idx = Rc::new(Cell::new(initial_idx.min(items.len() - 1)));
    let items_rc = Rc::new(items);

    let win = gtk4::Window::builder()
        .title("Quick Look")
        .transient_for(parent)
        .modal(true)
        .default_width(880)
        .default_height(660)
        .build();
    win.set_decorated(false);
    win.add_css_class("alis-quicklook-surface");

    let root = gtk4::Box::new(gtk4::Orientation::Vertical, 0);

    // 56px Minimal Top Bar inside WindowHandle
    let handle = gtk4::WindowHandle::new();
    let top = gtk4::Box::new(gtk4::Orientation::Horizontal, 10);
    top.set_size_request(-1, 56);
    top.set_margin_start(20);
    top.set_margin_end(14);

    let title_col = gtk4::Box::new(gtk4::Orientation::Vertical, 2);
    title_col.set_valign(gtk4::Align::Center);
    title_col.set_hexpand(true);
    let title = gtk4::Label::new(None);
    title.set_xalign(0.0);
    title.set_ellipsize(gtk4::pango::EllipsizeMode::Middle);
    title.add_css_class("title-4");
    let meta_lbl = gtk4::Label::new(None);
    meta_lbl.set_xalign(0.0);
    meta_lbl.set_opacity(0.65);
    title_col.append(&title);
    title_col.append(&meta_lbl);
    top.append(&title_col);

    let open_btn = gtk4::Button::from_icon_name("document-open-symbolic");
    open_btn.add_css_class("alis-act-btn");
    open_btn.add_css_class("round");
    open_btn.set_focus_on_click(false);
    open_btn.set_tooltip_text(Some("Open"));
    {
        let items_c = items_rc.clone();
        let idx_c = idx.clone();
        let w = win.clone();
        open_btn.connect_clicked(move |_| {
            let entry = &items_c[idx_c.get()];
            let _ = crate::alis_actions::open_with_default_app(&entry.path);
            w.close();
        });
    }
    top.append(&open_btn);

    let close_btn = gtk4::Button::from_icon_name("window-close-symbolic");
    close_btn.add_css_class("alis-act-btn");
    close_btn.add_css_class("round");
    close_btn.set_focus_on_click(false);
    close_btn.set_tooltip_text(Some("Close (Space / Esc)"));
    {
        let w = win.clone();
        close_btn.connect_clicked(move |_| w.close());
    }
    top.append(&close_btn);
    handle.set_child(Some(&top));
    root.append(&handle);

    // Center stage with Left / Right step chevrons overlaid
    let overlay = gtk4::Overlay::new();
    overlay.set_hexpand(true);
    overlay.set_vexpand(true);

    let body_box = gtk4::Box::new(gtk4::Orientation::Vertical, 0);
    body_box.set_hexpand(true);
    body_box.set_vexpand(true);
    body_box.set_margin_start(56);
    body_box.set_margin_end(56);
    body_box.set_margin_bottom(24);
    overlay.set_child(Some(&body_box));

    let prev_item_btn = gtk4::Button::from_icon_name("go-previous-symbolic");
    prev_item_btn.add_css_class("alis-act-btn");
    prev_item_btn.add_css_class("round");
    prev_item_btn.set_halign(gtk4::Align::Start);
    prev_item_btn.set_valign(gtk4::Align::Center);
    prev_item_btn.set_margin_start(14);
    prev_item_btn.set_focus_on_click(false);
    overlay.add_overlay(&prev_item_btn);

    let next_item_btn = gtk4::Button::from_icon_name("go-next-symbolic");
    next_item_btn.add_css_class("alis-act-btn");
    next_item_btn.add_css_class("round");
    next_item_btn.set_halign(gtk4::Align::End);
    next_item_btn.set_valign(gtk4::Align::Center);
    next_item_btn.set_margin_end(14);
    next_item_btn.set_focus_on_click(false);
    overlay.add_overlay(&next_item_btn);

    root.append(&overlay);

    let active_video: Rc<std::cell::RefCell<Option<gtk4::Video>>> =
        Rc::new(std::cell::RefCell::new(None));

    let render_current = {
        let items_c = items_rc.clone();
        let idx_c = idx.clone();
        let title_c = title.clone();
        let meta_c = meta_lbl.clone();
        let body_c = body_box.clone();
        let prev_c = prev_item_btn.clone();
        let next_c = next_item_btn.clone();
        let vid_slot = active_video.clone();
        let w_c = win.clone();
        let cb_opt = on_index_changed.clone();
        Rc::new(move || {
            if let Some(prev_vid) = vid_slot.borrow_mut().take() {
                prev_vid.set_file(gtk4::gio::File::NONE);
            }
            while let Some(child) = body_c.first_child() {
                body_c.remove(&child);
            }
            let cur_i = idx_c.get().min(items_c.len() - 1);
            let entry = &items_c[cur_i];
            if let Some(ref cb) = cb_opt {
                cb(entry);
            }
            w_c.set_title(Some(&format!("Quick Look — {}", entry.name)));
            title_c.set_text(&entry.name);
            meta_c.set_text(&format!(
                "{}  •  {}  •  {}  •  {} / {}",
                entry.kind_label(),
                if entry.is_dir {
                    "Folder".into()
                } else {
                    format_size(entry.size)
                },
                format_time(entry.modified),
                cur_i + 1,
                items_c.len()
            ));
            prev_c.set_visible(cur_i > 0);
            next_c.set_visible(cur_i + 1 < items_c.len());

            match entry.kind {
                FileKind::Image => build_image_preview(&body_c, &entry.path),
                FileKind::Pdf => build_pdf_preview(&body_c, &entry.path),
                FileKind::Video | FileKind::Audio => {
                    let v = build_video_preview(&body_c, &entry.path);
                    *vid_slot.borrow_mut() = Some(v);
                }
                FileKind::Markdown | FileKind::Code | FileKind::Text => {
                    build_text_preview(&body_c, &entry.path)
                }
                _ => build_generic_preview(&body_c, entry),
            }
        })
    };

    render_current();

    {
        let idx_c = idx.clone();
        let rc_render = render_current.clone();
        prev_item_btn.connect_clicked(move |_| {
            let cur = idx_c.get();
            if cur > 0 {
                idx_c.set(cur - 1);
                rc_render();
            }
        });
    }
    {
        let idx_c = idx.clone();
        let len = items_rc.len();
        let rc_render = render_current.clone();
        next_item_btn.connect_clicked(move |_| {
            let cur = idx_c.get();
            if cur + 1 < len {
                idx_c.set(cur + 1);
                rc_render();
            }
        });
    }
    {
        let vid_slot = active_video.clone();
        win.connect_close_request(move |_| {
            if let Some(v) = vid_slot.borrow_mut().take() {
                v.set_file(gtk4::gio::File::NONE);
            }
            glib::Propagation::Proceed
        });
    }

    // Capture phase keyboard handling: Space/Esc closes, Left/Up & Right/Down step items
    let key_ctrl = gtk4::EventControllerKey::new();
    key_ctrl.set_propagation_phase(gtk4::PropagationPhase::Capture);
    {
        let w = win.clone();
        let idx_c = idx.clone();
        let items_c = items_rc.clone();
        let rc_render = render_current.clone();
        key_ctrl.connect_key_pressed(move |_, key, _, _| match key {
            gdk::Key::Escape | gdk::Key::space => {
                w.close();
                glib::Propagation::Stop
            }
            gdk::Key::Left | gdk::Key::Up => {
                let cur = idx_c.get();
                if cur > 0 {
                    idx_c.set(cur - 1);
                    rc_render();
                }
                glib::Propagation::Stop
            }
            gdk::Key::Right | gdk::Key::Down => {
                let cur = idx_c.get();
                if cur + 1 < items_c.len() {
                    idx_c.set(cur + 1);
                    rc_render();
                }
                glib::Propagation::Stop
            }
            gdk::Key::Return | gdk::Key::KP_Enter => {
                let entry = &items_c[idx_c.get()];
                let _ = crate::alis_actions::open_with_default_app(&entry.path);
                w.close();
                glib::Propagation::Stop
            }
            _ => glib::Propagation::Proceed,
        });
    }
    win.add_controller(key_ctrl);

    win.set_child(Some(&root));
    win.present();
}

fn build_image_preview(container: &gtk4::Box, path: &Path) {
    let pic = gtk4::Picture::new();
    pic.set_hexpand(true);
    pic.set_vexpand(true);
    pic.set_can_shrink(true);
    pic.set_content_fit(gtk4::ContentFit::Contain);
    container.append(&pic);

    let p = path.to_path_buf();
    let pic_ui = pic.clone();
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let decoded = crate::thumbnails::decode_scaled_image_buffer(&p, 2048);
        let _ = tx.send((decoded, p));
    });
    glib::timeout_add_local(std::time::Duration::from_millis(20), move || match rx.try_recv() {
        Ok((Some(buf), _)) => {
            if pic_ui.parent().is_some() {
                let tex = crate::thumbnails::texture_from_scaled_buffer(buf);
                pic_ui.set_paintable(Some(&tex));
            }
            glib::ControlFlow::Break
        }
        Ok((None, fallback_path)) => {
            if pic_ui.parent().is_some()
                && let Some(tex) = crate::thumbnails::load_texture_from_path(&fallback_path)
            {
                pic_ui.set_paintable(Some(&tex));
            }
            glib::ControlFlow::Break
        }
        Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
        Err(std::sync::mpsc::TryRecvError::Empty) => {
            if pic_ui.parent().is_none() {
                glib::ControlFlow::Break
            } else {
                glib::ControlFlow::Continue
            }
        }
    });
}

fn build_pdf_preview(container: &gtk4::Box, path: &Path) {
    let total_pages = Rc::new(Cell::new(1u32));
    let current_page = Rc::new(Cell::new(1u32));

    let nav = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
    nav.set_halign(gtk4::Align::Center);
    nav.set_margin_bottom(8);
    let prev_btn = gtk4::Button::with_label("Previous");
    prev_btn.add_css_class("alis-flat-btn");
    let page_lbl = gtk4::Label::new(Some("Page 1 / …"));
    let next_btn = gtk4::Button::with_label("Next");
    next_btn.add_css_class("alis-flat-btn");
    nav.append(&prev_btn);
    nav.append(&page_lbl);
    nav.append(&next_btn);
    container.append(&nav);

    let scroll = gtk4::ScrolledWindow::new();
    scroll.set_hexpand(true);
    scroll.set_vexpand(true);
    let pic = gtk4::Picture::new();
    pic.set_can_shrink(true);
    pic.set_content_fit(gtk4::ContentFit::Contain);
    scroll.set_child(Some(&pic));
    container.append(&scroll);

    let render_gen = Rc::new(Cell::new(0u64));
    let render_page = {
        let p = path.to_path_buf();
        let pic = pic.clone();
        let lbl = page_lbl.clone();
        let rgen = render_gen.clone();
        let tp = total_pages.clone();
        Rc::new(move |page: u32| {
            let seq = rgen.get().wrapping_add(1);
            rgen.set(seq);
            let total = tp.get();
            lbl.set_text(&format!("Page {page} / {total} (rendering…)"));
            let path_bg = p.clone();
            let pic_ui = pic.clone();
            let lbl_ui = lbl.clone();
            let rgen_ui = rgen.clone();
            let tp_ui = tp.clone();
            let (tx, rx) = std::sync::mpsc::channel();
            std::thread::spawn(move || {
                let count = if page == 1 {
                    crate::thumbnails::pdf_page_count(&path_bg)
                } else {
                    None
                };
                let rendered = crate::thumbnails::render_pdf_page(&path_bg, page, 1200);
                let _ = tx.send((count, rendered));
            });
            glib::timeout_add_local(std::time::Duration::from_millis(30), move || {
                if rgen_ui.get() != seq {
                    return glib::ControlFlow::Break;
                }
                match rx.try_recv() {
                    Ok((count, Some(png))) => {
                        if let Some(c) = count {
                            tp_ui.set(c.max(1));
                        }
                        if let Some(tex) = crate::thumbnails::load_texture_from_path(&png) {
                            pic_ui.set_paintable(Some(&tex));
                        }
                        lbl_ui.set_text(&format!("Page {page} / {}", tp_ui.get()));
                        glib::ControlFlow::Break
                    }
                    Ok((count, None)) => {
                        if let Some(c) = count {
                            tp_ui.set(c.max(1));
                        }
                        lbl_ui.set_text(&format!("Page {page} / {} (preview unavailable)", tp_ui.get()));
                        glib::ControlFlow::Break
                    }
                    Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                        lbl_ui.set_text(&format!("Page {page} / {} (preview unavailable)", tp_ui.get()));
                        glib::ControlFlow::Break
                    }
                    Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                }
            });
        })
    };

    render_page(1);

    {
        let cp = current_page.clone();
        let rp = render_page.clone();
        prev_btn.connect_clicked(move |_| {
            let cur = cp.get();
            if cur > 1 {
                cp.set(cur - 1);
                rp(cur - 1);
            }
        });
    }
    {
        let cp = current_page.clone();
        let tp = total_pages.clone();
        let rp = render_page.clone();
        next_btn.connect_clicked(move |_| {
            let cur = cp.get();
            if cur < tp.get() {
                cp.set(cur + 1);
                rp(cur + 1);
            }
        });
    }
}

fn build_video_preview(container: &gtk4::Box, path: &Path) -> gtk4::Video {
    let gfile = gtk4::gio::File::for_path(path);
    let video = gtk4::Video::for_file(Some(&gfile));
    video.set_hexpand(true);
    video.set_vexpand(true);
    video.set_autoplay(true);
    container.append(&video);
    video
}

fn build_text_preview(container: &gtk4::Box, path: &Path) {
    let scroll = gtk4::ScrolledWindow::new();
    scroll.set_hexpand(true);
    scroll.set_vexpand(true);

    let tv = gtk4::TextView::new();
    tv.set_editable(false);
    tv.set_cursor_visible(false);
    tv.set_monospace(true);
    tv.set_wrap_mode(gtk4::WrapMode::WordChar);
    tv.add_css_class("alis-code-view");
    tv.set_top_margin(12);
    tv.set_bottom_margin(12);
    tv.set_left_margin(14);
    tv.set_right_margin(14);

    const MAX_BYTES: usize = 256 * 1024;
    let is_regular = fs::metadata(path).map(|m| m.is_file()).unwrap_or(false);
    let content = if !is_regular {
        "Special file — preview unavailable".to_string()
    } else {
        match fs::File::open(path) {
            Ok(mut f) => {
                let mut buf = vec![0u8; MAX_BYTES];
                let n = f.read(&mut buf).unwrap_or(0);
                buf.truncate(n);
                if buf.contains(&0) {
                    "Binary file — text preview unavailable".to_string()
                } else {
                    let mut s = String::from_utf8_lossy(&buf).into_owned();
                    if n == MAX_BYTES {
                        s.push_str("\n\n— Preview truncated at 256 KB —");
                    }
                    s
                }
            }
            Err(e) => format!("Could not read file: {e}"),
        }
    };
    tv.buffer().set_text(&content);
    scroll.set_child(Some(&tv));
    container.append(&scroll);
}

fn build_generic_preview(container: &gtk4::Box, entry: &FileEntry) {
    let center = gtk4::Box::new(gtk4::Orientation::Vertical, 12);
    center.set_vexpand(true);
    center.set_valign(gtk4::Align::Center);
    center.set_halign(gtk4::Align::Center);

    let pic = gtk4::Picture::new();
    pic.set_size_request(112, 112);
    pic.set_content_fit(gtk4::ContentFit::Contain);
    if let Some(art) = crate::ui::file_art::texture_for_entry(entry, 112) {
        pic.set_paintable(Some(&art));
    }
    center.append(&pic);

    let lbl = gtk4::Label::new(Some(&entry.name));
    lbl.add_css_class("title-2");
    center.append(&lbl);

    let sub = gtk4::Label::new(Some(&format!(
        "{} — {}",
        entry.kind_label(),
        format_size(entry.size)
    )));
    sub.set_opacity(0.65);
    center.append(&sub);

    container.append(&center);
}
