use crate::model::{FileEntry, FileKind, format_size};
use crate::properties::{self, ItemProperties};
use gtk4::glib;
use gtk4::prelude::*;
use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

#[derive(Clone)]
pub struct InspectorPanel {
    pub root: gtk4::ScrolledWindow,
    paned: gtk4::Paned,
    preview_card_wrap: gtk4::Box,
    props_outer: gtk4::Box,
    preview_scroll: gtk4::ScrolledWindow,
    props_scroll: gtk4::ScrolledWindow,
    preview_pic: gtk4::Picture,
    title_label: gtk4::Label,
    kind_label: gtk4::Label,
    actions_box: gtk4::Box,
    props_tabs_row: gtk4::Box,
    general_tab_btn: gtk4::ToggleButton,
    props_stack: gtk4::Stack,
    general_box: gtk4::Box,
    permissions_box: gtk4::Box,
    checksums_box: gtk4::Box,
    details_box: gtk4::Box,
    current_path: Rc<RefCell<Option<PathBuf>>>,
    generation: Rc<Cell<u64>>,
    dir_size_cancel: Rc<RefCell<Option<Arc<AtomicBool>>>>,
    ratio_milli: Rc<Cell<u16>>,
    suppress_ratio_save: Rc<Cell<bool>>,
    on_open: Rc<dyn Fn(PathBuf)>,
    on_quicklook: Rc<dyn Fn(PathBuf)>,
    on_permissions_changed: Rc<dyn Fn(PathBuf)>,
    on_toast: Rc<dyn Fn(String)>,
}

impl InspectorPanel {
    pub fn new(
        on_open: Rc<dyn Fn(PathBuf)>,
        on_quicklook: Rc<dyn Fn(PathBuf)>,
        on_permissions_changed: Rc<dyn Fn(PathBuf)>,
        on_toast: Rc<dyn Fn(String)>,
        on_ratio_changed: Rc<dyn Fn(u16)>,
        initial_ratio_milli: u16,
    ) -> Self {
        let root = gtk4::ScrolledWindow::new();
        root.set_hscrollbar_policy(gtk4::PolicyType::External);
        root.set_vscrollbar_policy(gtk4::PolicyType::Never);
        root.set_propagate_natural_width(false);
        root.set_propagate_natural_height(false);
        root.set_width_request(296);
        root.set_hexpand(false);
        root.set_vexpand(true);

        let paned = gtk4::Paned::new(gtk4::Orientation::Vertical);
        paned.add_css_class("alis-inspector");
        paned.add_css_class("alis-inspector-paned");
        paned.set_hexpand(true);
        paned.set_vexpand(true);
        paned.set_wide_handle(false);
        paned.set_resize_start_child(true);
        paned.set_resize_end_child(true);
        paned.set_shrink_start_child(true);
        paned.set_shrink_end_child(true);

        // ── Top Independent Card: Preview Pane ───────────────────────────
        let preview_card_wrap = gtk4::Box::new(gtk4::Orientation::Vertical, 0);
        preview_card_wrap.add_css_class("alis-aside-card");
        preview_card_wrap.set_hexpand(true);
        preview_card_wrap.set_vexpand(true);

        let preview_scroll = gtk4::ScrolledWindow::new();
        preview_scroll.set_hscrollbar_policy(gtk4::PolicyType::Never);
        preview_scroll.set_vscrollbar_policy(gtk4::PolicyType::Automatic);
        preview_scroll.set_propagate_natural_width(false);
        preview_scroll.set_propagate_natural_height(false);
        preview_scroll.set_vexpand(true);

        let preview_top = gtk4::Box::new(gtk4::Orientation::Vertical, 8);
        preview_top.set_hexpand(true);

        let preview_card = gtk4::Box::new(gtk4::Orientation::Vertical, 0);
        preview_card.add_css_class("alis-preview-card");
        preview_card.set_size_request(-1, 118);
        preview_card.set_hexpand(true);
        preview_card.set_vexpand(false);
        preview_card.set_halign(gtk4::Align::Fill);

        let preview_pic = gtk4::Picture::new();
        preview_pic.set_size_request(-1, 102);
        preview_pic.set_hexpand(true);
        preview_pic.set_vexpand(false);
        preview_pic.set_can_shrink(true);
        preview_pic.set_content_fit(gtk4::ContentFit::Contain);
        preview_card.append(&preview_pic);
        preview_top.append(&preview_card);

        let title_label = gtk4::Label::new(Some("No selection"));
        title_label.set_wrap(true);
        title_label.set_wrap_mode(gtk4::pango::WrapMode::WordChar);
        title_label.set_width_chars(1);
        title_label.set_max_width_chars(1);
        title_label.set_xalign(0.0);
        title_label.set_selectable(true);
        title_label.add_css_class("title-4");
        preview_top.append(&title_label);

        let kind_label = gtk4::Label::new(Some("Select an item to preview"));
        kind_label.set_xalign(0.0);
        kind_label.set_width_chars(1);
        kind_label.set_max_width_chars(1);
        kind_label.set_ellipsize(gtk4::pango::EllipsizeMode::End);
        kind_label.add_css_class("alis-subtext");
        preview_top.append(&kind_label);

        let actions_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 6);
        actions_box.set_homogeneous(true);
        actions_box.set_hexpand(true);
        let current_path: Rc<RefCell<Option<PathBuf>>> = Rc::new(RefCell::new(None));

        let open_btn = make_action_btn("Open", "Open selected item");
        {
            let cp = current_path.clone();
            let cb = on_open.clone();
            open_btn.connect_clicked(move |_| {
                if let Some(p) = cp.borrow().clone() {
                    cb(p);
                }
            });
        }
        let ql_btn = make_action_btn("Preview", "Quick Look (Alt+Space)");
        {
            let cp = current_path.clone();
            let cb = on_quicklook.clone();
            ql_btn.connect_clicked(move |_| {
                if let Some(p) = cp.borrow().clone() {
                    cb(p);
                }
            });
        }
        actions_box.append(&open_btn);
        actions_box.append(&ql_btn);
        actions_box.set_sensitive(false);
        preview_top.append(&actions_box);
        preview_scroll.set_child(Some(&preview_top));
        preview_card_wrap.append(&preview_scroll);

        // ── Bottom Independent Card: Live Properties Pane ────────────────
        let props_outer = gtk4::Box::new(gtk4::Orientation::Vertical, 8);
        props_outer.add_css_class("alis-aside-card");
        props_outer.set_hexpand(true);
        props_outer.set_vexpand(true);

        let props_tabs_row = gtk4::Box::new(gtk4::Orientation::Horizontal, 2);
        props_tabs_row.add_css_class("alis-props-tabs");
        props_tabs_row.set_homogeneous(true);
        props_tabs_row.set_hexpand(true);

        let props_stack = gtk4::Stack::new();
        props_stack.set_hhomogeneous(false);
        props_stack.set_vhomogeneous(false);
        props_stack.set_hexpand(true);
        props_stack.set_vexpand(true);

        let general_box = gtk4::Box::new(gtk4::Orientation::Vertical, 6);
        let permissions_box = gtk4::Box::new(gtk4::Orientation::Vertical, 8);
        let checksums_box = gtk4::Box::new(gtk4::Orientation::Vertical, 8);
        let details_box = gtk4::Box::new(gtk4::Orientation::Vertical, 6);

        props_stack.add_named(&general_box, Some("general"));
        props_stack.add_named(&permissions_box, Some("permissions"));
        props_stack.add_named(&checksums_box, Some("checksums"));
        props_stack.add_named(&details_box, Some("details"));

        let general_tab_btn = make_tab_btn("General", "General information", None);
        general_tab_btn.set_active(true);
        let perms_tab_btn = make_tab_btn("Permissions", "Permissions", Some(&general_tab_btn));
        let hashes_tab_btn = make_tab_btn("Checksums", "Checksums", Some(&general_tab_btn));
        let details_tab_btn = make_tab_btn("Details", "Details", Some(&general_tab_btn));

        for (btn, name) in [
            (&general_tab_btn, "general"),
            (&perms_tab_btn, "permissions"),
            (&hashes_tab_btn, "checksums"),
            (&details_tab_btn, "details"),
        ] {
            let st = props_stack.clone();
            btn.connect_toggled(move |b| {
                if b.is_active() {
                    st.set_visible_child_name(name);
                }
            });
            props_tabs_row.append(btn);
        }
        props_outer.append(&props_tabs_row);

        let props_scroll = gtk4::ScrolledWindow::new();
        props_scroll.set_hscrollbar_policy(gtk4::PolicyType::Never);
        props_scroll.set_vscrollbar_policy(gtk4::PolicyType::Automatic);
        props_scroll.set_propagate_natural_width(false);
        props_scroll.set_propagate_natural_height(false);
        props_scroll.set_hexpand(true);
        props_scroll.set_vexpand(true);
        props_scroll.set_child(Some(&props_stack));
        props_outer.append(&props_scroll);

        paned.set_start_child(Some(&preview_card_wrap));
        paned.set_end_child(Some(&props_outer));
        root.set_child(Some(&paned));

        let ratio_milli = Rc::new(Cell::new(initial_ratio_milli.clamp(220, 720)));
        let suppress_ratio_save = Rc::new(Cell::new(false));
        let last_alloc_h = Rc::new(Cell::new(0i32));
        let save_timer: Rc<RefCell<Option<glib::SourceId>>> = Rc::new(RefCell::new(None));

        // Maintain target ratio across initial layout & height resizes, and persist user drags.
        {
            let p_ref = paned.clone();
            let rm = ratio_milli.clone();
            let sup = suppress_ratio_save.clone();
            let lah = last_alloc_h.clone();
            let st_cell = save_timer.clone();
            let on_rc = on_ratio_changed;
            glib::timeout_add_local(std::time::Duration::from_millis(80), move || {
                if !p_ref.is_visible() {
                    return glib::ControlFlow::Continue;
                }
                let h = p_ref.height();
                if h > 80 && lah.get() != h {
                    lah.set(h);
                    sup.set(true);
                    let pos = ((h as f64) * (rm.get() as f64 / 1000.0)).round() as i32;
                    p_ref.set_position(pos.clamp((h as f64 * 0.22) as i32, (h as f64 * 0.72) as i32));
                    sup.set(false);
                }
                glib::ControlFlow::Continue
            });

            let rm2 = ratio_milli.clone();
            let sup2 = suppress_ratio_save.clone();
            let lah2 = last_alloc_h.clone();
            paned.connect_position_notify(move |p| {
                if sup2.get() {
                    return;
                }
                let h = p.height();
                if h <= 80 || lah2.get() != h {
                    return;
                }
                let raw = ((p.position() as f64 / h as f64) * 1000.0).round() as i32;
                let clamped = raw.clamp(220, 720) as u16;
                if rm2.get() == clamped {
                    return;
                }
                rm2.set(clamped);
                if let Some(old) = st_cell.borrow_mut().take() {
                    old.remove();
                }
                let cb = on_rc.clone();
                let st_inner = st_cell.clone();
                let id = glib::timeout_add_local_once(
                    std::time::Duration::from_millis(200),
                    move || {
                        *st_inner.borrow_mut() = None;
                        cb(clamped);
                    },
                );
                *st_cell.borrow_mut() = Some(id);
            });
        }

        Self {
            root,
            paned,
            preview_card_wrap,
            props_outer,
            preview_scroll,
            props_scroll,
            preview_pic,
            title_label,
            kind_label,
            actions_box,
            props_tabs_row,
            general_tab_btn,
            props_stack,
            general_box,
            permissions_box,
            checksums_box,
            details_box,
            current_path,
            generation: Rc::new(Cell::new(0)),
            dir_size_cancel: Rc::new(RefCell::new(None)),
            ratio_milli,
            suppress_ratio_save,
            on_open,
            on_quicklook,
            on_permissions_changed,
            on_toast,
        }
    }

    pub fn set_focused_card(&self, card: Option<&str>) {
        if card == Some("preview") {
            self.preview_card_wrap.add_css_class("pane-focused");
        } else {
            self.preview_card_wrap.remove_css_class("pane-focused");
        }
        if card == Some("properties") {
            self.props_outer.add_css_class("pane-focused");
        } else {
            self.props_outer.remove_css_class("pane-focused");
        }
    }

    pub fn cycle_props_tab(&self, delta: i32) {
        const ORDER: [&str; 4] = ["general", "permissions", "checksums", "details"];
        let cur = self
            .props_stack
            .visible_child_name()
            .map(|g| g.to_string())
            .unwrap_or_else(|| "general".into());
        let idx = ORDER.iter().position(|n| *n == cur).unwrap_or(0) as isize;
        let next = (idx + delta as isize).rem_euclid(ORDER.len() as isize) as usize;
        self.focus_properties_tab(ORDER[next]);
    }

    pub fn scroll_card(&self, card: &str, delta_px: f64) {
        let sc = if card == "preview" {
            &self.preview_scroll
        } else {
            &self.props_scroll
        };
        let adj = sc.vadjustment();
        let max_v = (adj.upper() - adj.page_size()).max(0.0);
        adj.set_value((adj.value() + delta_px).clamp(0.0, max_v));
    }

    pub fn trigger_open(&self) {
        if let Some(p) = self.current_path.borrow().clone() {
            (self.on_open)(p);
        }
    }

    pub fn trigger_quicklook(&self) {
        if let Some(p) = self.current_path.borrow().clone() {
            (self.on_quicklook)(p);
        }
    }

    pub fn attach_focus_clicks(
        &self,
        on_focus_preview: Rc<dyn Fn()>,
        on_focus_props: Rc<dyn Fn()>,
    ) {
        let c1 = gtk4::GestureClick::new();
        c1.set_button(0);
        c1.set_propagation_phase(gtk4::PropagationPhase::Capture);
        c1.connect_pressed(move |_, _, _, _| on_focus_preview());
        self.preview_card_wrap.add_controller(c1);

        let c2 = gtk4::GestureClick::new();
        c2.set_button(0);
        c2.set_propagation_phase(gtk4::PropagationPhase::Capture);
        c2.connect_pressed(move |_, _, _, _| on_focus_props());
        self.props_outer.add_controller(c2);
    }

    pub fn set_preview_ratio_milli(&self, ratio: u16) {
        let clamped = ratio.clamp(220, 720);
        self.ratio_milli.set(clamped);
        let h = self.paned.height();
        if h > 80 {
            self.suppress_ratio_save.set(true);
            let pos = ((h as f64) * (clamped as f64 / 1000.0)).round() as i32;
            self.paned.set_position(pos);
            self.suppress_ratio_save.set(false);
        }
    }

    pub fn focus_properties_tab(&self, tab: &str) {
        let name = match tab {
            "permissions" | "checksums" | "details" => tab,
            _ => "general",
        };
        self.props_stack.set_visible_child_name(name);
        if name == "general" {
            self.general_tab_btn.set_active(true);
        } else if let Some(child) = self.props_tabs_row.first_child() {
            let mut cur = Some(child);
            let idx = match name {
                "permissions" => 1,
                "checksums" => 2,
                "details" => 3,
                _ => 0,
            };
            for _ in 0..idx {
                cur = cur.and_then(|w| w.next_sibling());
            }
            if let Some(btn) = cur.and_then(|w| w.downcast::<gtk4::ToggleButton>().ok()) {
                btn.set_active(true);
            }
        }
    }

    fn cancel_dir_size(&self) {
        if let Some(prev) = self.dir_size_cancel.borrow_mut().take() {
            prev.store(true, Ordering::Relaxed);
        }
    }

    pub fn inspect_folder(&self, dir: &Path, item_count: usize) {
        if let Ok(fe) = FileEntry::from_path(dir.to_path_buf()) {
            self.inspect_entry(&fe, false);
            self.kind_label.set_text(&format!(
                "Folder  •  {} {}",
                item_count,
                if item_count == 1 { "item" } else { "items" }
            ));
            return;
        }
        self.cancel_dir_size();
        *self.current_path.borrow_mut() = None;
        self.generation.set(self.generation.get().wrapping_add(1));
        self.preview_pic.set_paintable(None::<&gtk4::gdk::Paintable>);
        self.title_label.set_text("Folder");
        self.kind_label.set_text(&format!("{item_count} items"));
        clear_box(&self.general_box);
        clear_box(&self.permissions_box);
        clear_box(&self.checksums_box);
        clear_box(&self.details_box);
        self.actions_box.set_sensitive(false);
    }

    pub fn show_multi_entries(&self, entries: &[FileEntry]) {
        self.cancel_dir_size();
        *self.current_path.borrow_mut() = None;
        self.generation.set(self.generation.get().wrapping_add(1));
        if let Some(first) = entries.first()
            && let Some(art) = crate::ui::file_art::texture_for_entry(first, 384)
        {
            self.preview_pic.set_paintable(Some(&art));
        } else {
            self.preview_pic.set_paintable(None::<&gtk4::gdk::Paintable>);
        }

        let total_bytes: u64 = entries.iter().filter(|e| !e.is_dir).map(|e| e.size).sum();
        self.title_label.set_text(&format!("{} items selected", entries.len()));
        self.kind_label
            .set_text(&format!("Total file size: {}", format_size(total_bytes)));
        self.actions_box.set_sensitive(false);

        clear_box(&self.general_box);
        add_section_header(&self.general_box, "Selection");
        add_meta_row(&self.general_box, "Items", &entries.len().to_string());
        add_meta_row(&self.general_box, "Files size", &format_size(total_bytes));

        add_section_header(&self.general_box, "Kinds");
        let mut counts: HashMap<&'static str, usize> = HashMap::new();
        for e in entries {
            *counts.entry(e.kind_label()).or_insert(0) += 1;
        }
        let mut sorted: Vec<_> = counts.into_iter().collect();
        sorted.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0)));
        for (kind, count) in sorted {
            add_meta_row(&self.general_box, kind, &count.to_string());
        }

        clear_box(&self.permissions_box);
        add_muted_note(&self.permissions_box, "Select a single item to edit permissions.");
        clear_box(&self.checksums_box);
        add_muted_note(&self.checksums_box, "Select a single file to compute checksums.");
        clear_box(&self.details_box);
        add_muted_note(&self.details_box, "Multiple items selected.");
    }

    pub fn inspect_entry(&self, entry: &FileEntry, thumbnails_enabled: bool) {
        self.cancel_dir_size();
        *self.current_path.borrow_mut() = Some(entry.path.clone());
        let seq = self.generation.get().wrapping_add(1);
        self.generation.set(seq);

        self.title_label.set_text(&entry.name);
        self.kind_label.set_text(&if entry.is_dir {
            "Folder".to_string()
        } else {
            format!("{}  •  {}", entry.kind_label(), format_size(entry.size))
        });

        if let Some(art) = crate::ui::file_art::texture_for_entry(entry, 384) {
            self.preview_pic.set_paintable(Some(&art));
        } else {
            self.preview_pic.set_paintable(None::<&gtk4::gdk::Paintable>);
        }
        self.actions_box.set_sensitive(true);

        let git_desc = entry.git_badge.map(|b| b.description().to_string());
        let props = properties::inspect_item(&entry.path, git_desc).ok();
        self.populate_properties(entry, props.as_ref(), seq);

        if thumbnails_enabled && matches!(entry.kind, FileKind::Image | FileKind::Pdf | FileKind::Video)
        {
            let path = entry.path.clone();
            let kind = entry.kind;
            let pic = self.preview_pic.clone();
            let gen_cell = self.generation.clone();
            let (tx, rx) = std::sync::mpsc::channel();
            std::thread::spawn(move || {
                let thumb = crate::thumbnails::ensure_thumbnail_file(&path, kind, 512);
                let _ = tx.send(thumb);
            });
            glib::timeout_add_local(std::time::Duration::from_millis(30), move || {
                if gen_cell.get() != seq {
                    return glib::ControlFlow::Break;
                }
                match rx.try_recv() {
                    Ok(Some(thumb_path)) => {
                        if let Some(tex) = crate::thumbnails::load_texture_from_path(&thumb_path) {
                            pic.set_paintable(Some(&tex));
                        }
                        glib::ControlFlow::Break
                    }
                    Ok(None) | Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                        glib::ControlFlow::Break
                    }
                    Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                }
            });
        }
    }

    fn populate_properties(&self, entry: &FileEntry, props_opt: Option<&ItemProperties>, seq: u64) {
        self.populate_general(entry, props_opt, seq);
        self.populate_permissions(entry, props_opt);
        self.populate_checksums(entry, seq);
        self.populate_details(entry, props_opt);
    }

    fn populate_general(&self, entry: &FileEntry, props_opt: Option<&ItemProperties>, seq: u64) {
        clear_box(&self.general_box);

        let type_str = props_opt
            .map(|p| p.type_description.as_str())
            .unwrap_or(entry.kind_label());
        add_meta_row(&self.general_box, "Type", type_str);

        if let Some(p) = props_opt {
            add_meta_row(&self.general_box, "Content", &p.mime_type);

            if !p.is_dir && !p.is_broken_symlink {
                let open_row = gtk4::Box::new(gtk4::Orientation::Horizontal, 6);
                let app_lbl = make_value_label(
                    p.default_app_name.as_deref().unwrap_or("Not set"),
                );
                open_row.append(&app_lbl);

                if !p.available_apps.is_empty() {
                    let change_btn = gtk4::MenuButton::new();
                    let btn_lbl = gtk4::Label::new(Some("Change…"));
                    btn_lbl.set_width_chars(1);
                    btn_lbl.set_max_width_chars(1);
                    btn_lbl.set_ellipsize(gtk4::pango::EllipsizeMode::End);
                    change_btn.set_child(Some(&btn_lbl));
                    change_btn.add_css_class("alis-inspector-action-btn");
                    change_btn.set_tooltip_text(Some("Change default application"));

                    let pop = gtk4::Popover::new();
                    let pop_box = gtk4::Box::new(gtk4::Orientation::Vertical, 2);
                    for choice in &p.available_apps {
                        let item_btn = gtk4::Button::with_label(&choice.name);
                        item_btn.add_css_class("alis-flat-btn");
                        item_btn.set_halign(gtk4::Align::Fill);
                        let mime = p.mime_type.clone();
                        let aid = choice.id.clone();
                        let aname = choice.name.clone();
                        let albl = app_lbl.clone();
                        let pop_c = pop.clone();
                        let toast = self.on_toast.clone();
                        item_btn.connect_clicked(move |_| {
                            pop_c.popdown();
                            match properties::set_default_app(&mime, &aid) {
                                Ok(()) => {
                                    albl.set_text(&aname);
                                    toast(format!("Default app set to {aname}"));
                                }
                                Err(e) => toast(e),
                            }
                        });
                        pop_box.append(&item_btn);
                    }
                    pop.set_child(Some(&pop_box));
                    change_btn.set_popover(Some(&pop));
                    open_row.append(&change_btn);
                }
                add_meta_widget_row(&self.general_box, "Open with", &open_row);
            }
        }

        // Location + Copy button
        let loc_str = props_opt
            .map(|p| p.location.as_str())
            .unwrap_or_else(|| entry.path.parent().and_then(|p| p.to_str()).unwrap_or("/"));
        let loc_row = gtk4::Box::new(gtk4::Orientation::Horizontal, 4);
        let loc_lbl = make_value_label(loc_str);
        let copy_loc = make_copy_btn(&entry.path.to_string_lossy(), "Copy full path", self.on_toast.clone());
        loc_row.append(&loc_lbl);
        loc_row.append(&copy_loc);
        add_meta_widget_row(&self.general_box, "Location", &loc_row);

        // Size & Size on disk
        let size_lbl = make_value_label(&if entry.is_dir {
            "Calculating…".to_string()
        } else {
            format!("{} ({} B)", format_size(entry.size), entry.size)
        });
        let disk_lbl = make_value_label(&if entry.is_dir {
            "Calculating…".to_string()
        } else if let Some(p) = props_opt {
            format!("{} ({} B)", p.size_on_disk_label, p.size_on_disk)
        } else {
            "—".to_string()
        });
        add_meta_widget_row(&self.general_box, "Size", &size_lbl);
        add_meta_widget_row(&self.general_box, "On disk", &disk_lbl);

        if entry.is_dir {
            let p = entry.path.clone();
            let cancel = Arc::new(AtomicBool::new(false));
            *self.dir_size_cancel.borrow_mut() = Some(cancel.clone());
            let cancel_bg = cancel.clone();
            let (tx, rx) = std::sync::mpsc::channel();
            std::thread::spawn(move || {
                let res = crate::disk_usage::dir_size_and_disk_recursive(&p, &cancel_bg);
                let _ = tx.send(res);
            });
            let gen_cell = self.generation.clone();
            let sl = size_lbl.clone();
            let dl = disk_lbl.clone();
            glib::timeout_add_local(std::time::Duration::from_millis(50), move || {
                if gen_cell.get() != seq {
                    cancel.store(true, Ordering::Relaxed);
                    return glib::ControlFlow::Break;
                }
                match rx.try_recv() {
                    Ok((bytes, disk_bytes, count)) => {
                        if cancel.load(Ordering::Relaxed) {
                            return glib::ControlFlow::Break;
                        }
                        sl.set_text(&format!("{} ({count} items)", format_size(bytes)));
                        dl.set_text(&format!("{} ({disk_bytes} B)", format_size(disk_bytes)));
                        glib::ControlFlow::Break
                    }
                    Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
                    Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                }
            });
        }

        if let Some(p) = props_opt {
            add_section_header(&self.general_box, "Dates");
            add_meta_row(&self.general_box, "Created", &p.created_label);
            add_meta_row(&self.general_box, "Modified", &p.modified_label);
            add_meta_row(&self.general_box, "Accessed", &p.accessed_label);
        }
    }

    fn populate_permissions(&self, entry: &FileEntry, props_opt: Option<&ItemProperties>) {
        clear_box(&self.permissions_box);

        let mode_init = props_opt.map(|p| p.mode).unwrap_or(entry.mode) & 0o777;
        let can_chmod = props_opt.map(|p| p.can_chmod).unwrap_or(false);
        let owner_group = props_opt
            .map(|p| format!("{}:{}", p.owner, p.group))
            .unwrap_or_else(|| "—".into());
        let perm_summary = props_opt
            .map(|p| p.permissions_label.clone())
            .unwrap_or_else(|| crate::model::format_permissions(mode_init));

        let card = gtk4::Box::new(gtk4::Orientation::Vertical, 4);
        card.add_css_class("alis-props-card");
        add_meta_row(&card, "Owner", &owner_group);
        let mode_lbl = make_value_label(&perm_summary);
        add_meta_widget_row(&card, "Mode", &mode_lbl);
        self.permissions_box.append(&card);

        let cur_mode = Rc::new(Cell::new(mode_init));
        let suppress = Rc::new(Cell::new(false));
        let toggles: Rc<RefCell<Vec<(u32, gtk4::ToggleButton)>>> = Rc::new(RefCell::new(Vec::new()));

        let exec_toggle = gtk4::ToggleButton::new();
        exec_toggle.add_css_class("alis-perm-toggle");
        exec_toggle.add_css_class("alis-exec-toggle");
        exec_toggle.set_hexpand(true);
        exec_toggle.set_focus_on_click(false);
        exec_toggle.set_tooltip_text(Some("Allow executing file as program"));
        let exec_inner = gtk4::Box::new(gtk4::Orientation::Horizontal, 6);
        exec_inner.set_halign(gtk4::Align::Center);
        exec_inner.set_valign(gtk4::Align::Center);
        let exec_ico = gtk4::Image::from_icon_name("utilities-terminal-symbolic");
        exec_ico.set_pixel_size(14);
        let exec_lbl = gtk4::Label::new(Some("Executable"));
        exec_lbl.set_width_chars(1);
        exec_lbl.set_max_width_chars(1);
        exec_lbl.set_ellipsize(gtk4::pango::EllipsizeMode::End);
        exec_inner.append(&exec_ico);
        exec_inner.append(&exec_lbl);
        exec_toggle.set_child(Some(&exec_inner));
        exec_toggle.set_active(!entry.is_dir && (mode_init & 0o100) != 0);
        exec_toggle.set_visible(!entry.is_dir);
        exec_toggle.set_sensitive(can_chmod);

        let apply_new_mode: Rc<dyn Fn(u32)> = {
            let p = entry.path.clone();
            let cm = cur_mode.clone();
            let ml = mode_lbl.clone();
            let sup = suppress.clone();
            let tgs = toggles.clone();
            let ec = exec_toggle.clone();
            let on_perm = self.on_permissions_changed.clone();
            let on_toast = self.on_toast.clone();
            Rc::new(move |next_mode: u32| {
                let p_bg = p.clone();
                let p_ui = p.clone();
                let cm_ui = cm.clone();
                let ml_ui = ml.clone();
                let sup_ui = sup.clone();
                let tgs_ui = tgs.clone();
                let ec_ui = ec.clone();
                let on_perm_ui = on_perm.clone();
                let on_toast_ui = on_toast.clone();
                let (tx, rx) = std::sync::mpsc::channel();
                std::thread::spawn(move || {
                    let _ = tx.send(properties::set_mode(&p_bg, next_mode));
                });
                glib::timeout_add_local(std::time::Duration::from_millis(30), move || match rx
                    .try_recv()
                {
                    Ok(Ok(updated)) => {
                        let m = updated.mode & 0o777;
                        cm_ui.set(m);
                        ml_ui.set_text(&updated.permissions_label);
                        sup_ui.set(true);
                        for (bit, btn) in tgs_ui.borrow().iter() {
                            btn.set_active((m & bit) != 0);
                        }
                        ec_ui.set_active((m & 0o100) != 0);
                        sup_ui.set(false);
                        on_perm_ui(p_ui.clone());
                        glib::ControlFlow::Break
                    }
                    Ok(Err(err)) => {
                        sup_ui.set(true);
                        let m = cm_ui.get();
                        for (bit, btn) in tgs_ui.borrow().iter() {
                            btn.set_active((m & bit) != 0);
                        }
                        ec_ui.set_active((m & 0o100) != 0);
                        sup_ui.set(false);
                        on_toast_ui(err);
                        glib::ControlFlow::Break
                    }
                    Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
                    Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                });
            })
        };

        let roles = [
            ("Owner", 0o400u32, 0o200u32, 0o100u32),
            ("Group", 0o040u32, 0o020u32, 0o010u32),
            ("Others", 0o004u32, 0o002u32, 0o001u32),
        ];
        for (role_label, r_bit, w_bit, x_bit) in roles {
            let row = gtk4::Box::new(gtk4::Orientation::Horizontal, 4);
            let k = gtk4::Label::new(Some(role_label));
            k.add_css_class("alis-muted");
            k.set_width_request(46);
            k.set_xalign(0.0);
            k.set_ellipsize(gtk4::pango::EllipsizeMode::End);
            row.append(&k);

            let btn_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 3);
            btn_box.set_homogeneous(true);
            btn_box.set_hexpand(true);

            for (ch, bit, tip) in [("R", r_bit, "Read"), ("W", w_bit, "Write"), ("X", x_bit, "Execute")] {
                let tb = gtk4::ToggleButton::new();
                let tl = gtk4::Label::new(Some(ch));
                tl.set_width_chars(1);
                tl.set_max_width_chars(1);
                tb.set_child(Some(&tl));
                tb.add_css_class("alis-perm-toggle");
                tb.set_focus_on_click(false);
                tb.set_tooltip_text(Some(tip));
                tb.set_active((mode_init & bit) != 0);
                tb.set_sensitive(can_chmod);

                let sup = suppress.clone();
                let cm = cur_mode.clone();
                let apply = apply_new_mode.clone();
                tb.connect_toggled(move |b| {
                    if sup.get() {
                        return;
                    }
                    let next = if b.is_active() {
                        cm.get() | bit
                    } else {
                        cm.get() & !bit
                    };
                    apply(next);
                });
                toggles.borrow_mut().push((bit, tb.clone()));
                btn_box.append(&tb);
            }
            row.append(&btn_box);
            self.permissions_box.append(&row);
        }

        if !entry.is_dir {
            let sup = suppress.clone();
            let cm = cur_mode.clone();
            let apply = apply_new_mode;
            exec_toggle.connect_toggled(move |chk| {
                if sup.get() {
                    return;
                }
                let next = if chk.is_active() {
                    cm.get() | 0o111
                } else {
                    cm.get() & !0o111
                };
                apply(next);
            });
            self.permissions_box.append(&exec_toggle);
        }

        if !can_chmod {
            add_muted_note(
                &self.permissions_box,
                if entry.is_symlink {
                    "Permissions are managed on the link target."
                } else {
                    "Only the file owner can modify permissions."
                },
            );
        }
    }

    fn populate_checksums(&self, entry: &FileEntry, seq: u64) {
        clear_box(&self.checksums_box);
        if entry.is_dir || entry.is_broken_symlink {
            add_muted_note(&self.checksums_box, "Checksums are available for regular files.");
            return;
        }

        let digests: Rc<RefCell<HashMap<&'static str, String>>> = Rc::new(RefCell::new(HashMap::new()));
        let verify_entry = gtk4::Entry::new();
        verify_entry.set_placeholder_text(Some("Verify hash…"));
        verify_entry.set_width_chars(1);
        verify_entry.set_hexpand(true);
        verify_entry.add_css_class("alis-path-entry");

        let verify_status = gtk4::Label::new(Some(""));
        verify_status.set_xalign(0.0);
        verify_status.set_width_chars(1);
        verify_status.set_max_width_chars(1);
        verify_status.set_wrap(true);
        verify_status.set_wrap_mode(gtk4::pango::WrapMode::WordChar);
        verify_status.set_visible(false);

        let update_verify: Rc<dyn Fn()> = {
            let ve = verify_entry.clone();
            let vs = verify_status.clone();
            let dg = digests.clone();
            Rc::new(move || {
                let raw = ve.text().trim().to_ascii_lowercase();
                vs.remove_css_class("alis-props-match");
                vs.remove_css_class("alis-props-mismatch");
                if raw.is_empty() {
                    vs.set_visible(false);
                    return;
                }
                let map = dg.borrow();
                if map.is_empty() {
                    vs.set_text("Calculate a checksum first");
                    vs.set_visible(true);
                    return;
                }
                if let Some((algo, _)) = map.iter().find(|(_, v)| v.eq_ignore_ascii_case(&raw)) {
                    vs.set_text(&format!("Matches {algo}"));
                    vs.add_css_class("alis-props-match");
                } else {
                    vs.set_text("No computed hash matches");
                    vs.add_css_class("alis-props-mismatch");
                }
                vs.set_visible(true);
            })
        };

        for (label, algo) in [
            ("MD5", "md5"),
            ("SHA-1", "sha1"),
            ("SHA-256", "sha256"),
            ("SHA-512", "sha512"),
        ] {
            let block = gtk4::Box::new(gtk4::Orientation::Vertical, 4);
            block.add_css_class("alis-props-card");

            let top = gtk4::Box::new(gtk4::Orientation::Horizontal, 4);
            let name_lbl = gtk4::Label::new(Some(label));
            name_lbl.set_xalign(0.0);
            name_lbl.set_hexpand(true);
            name_lbl.set_width_chars(1);
            name_lbl.set_max_width_chars(1);
            name_lbl.set_ellipsize(gtk4::pango::EllipsizeMode::End);
            top.append(&name_lbl);

            let copy_btn = gtk4::Button::from_icon_name("edit-copy-symbolic");
            copy_btn.add_css_class("alis-act-btn");
            copy_btn.set_focus_on_click(false);
            copy_btn.set_tooltip_text(Some("Copy digest"));
            copy_btn.set_sensitive(false);

            let calc_btn = make_action_btn("Calculate", &format!("Compute {label}"));
            calc_btn.set_hexpand(false);
            top.append(&copy_btn);
            top.append(&calc_btn);
            block.append(&top);

            let val_lbl = gtk4::Label::new(Some("Not calculated"));
            val_lbl.set_xalign(0.0);
            val_lbl.set_selectable(true);
            val_lbl.set_wrap(true);
            val_lbl.set_wrap_mode(gtk4::pango::WrapMode::Char);
            val_lbl.set_width_chars(1);
            val_lbl.set_max_width_chars(1);
            val_lbl.add_css_class("alis-props-mono");
            block.append(&val_lbl);

            {
                let vl = val_lbl.clone();
                let toast = self.on_toast.clone();
                copy_btn.connect_clicked(move |b| {
                    let txt = vl.text().to_string();
                    if let Some(disp) = gtk4::gdk::Display::default() {
                        disp.clipboard().set_text(&txt);
                    } else {
                        let _ = b;
                    }
                    toast(format!("Copied {label} checksum"));
                });
            }

            {
                let p = entry.path.clone();
                let vl = val_lbl.clone();
                let cb = copy_btn.clone();
                let dg = digests.clone();
                let uv = update_verify.clone();
                let gen_cell = self.generation.clone();
                calc_btn.connect_clicked(move |btn| {
                    btn.set_sensitive(false);
                    vl.set_text("Calculating…");
                    let path_bg = p.clone();
                    let (tx, rx) = std::sync::mpsc::channel();
                    std::thread::spawn(move || {
                        let _ = tx.send(properties::compute_checksum(&path_bg, algo));
                    });
                    let vl_ui = vl.clone();
                    let cb_ui = cb.clone();
                    let btn_ui = btn.clone();
                    let dg_ui = dg.clone();
                    let uv_ui = uv.clone();
                    let gen_c = gen_cell.clone();
                    glib::timeout_add_local(std::time::Duration::from_millis(40), move || {
                        if gen_c.get() != seq {
                            return glib::ControlFlow::Break;
                        }
                        match rx.try_recv() {
                            Ok(Ok(digest)) => {
                                vl_ui.set_text(&digest);
                                cb_ui.set_sensitive(true);
                                btn_ui.set_sensitive(true);
                                dg_ui.borrow_mut().insert(label, digest);
                                uv_ui();
                                glib::ControlFlow::Break
                            }
                            Ok(Err(err)) => {
                                vl_ui.set_text(&err);
                                btn_ui.set_sensitive(true);
                                glib::ControlFlow::Break
                            }
                            Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                                btn_ui.set_sensitive(true);
                                glib::ControlFlow::Break
                            }
                            Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                        }
                    });
                });
            }

            self.checksums_box.append(&block);
        }

        let uv = update_verify;
        verify_entry.connect_changed(move |_| uv());
        self.checksums_box.append(&verify_entry);
        self.checksums_box.append(&verify_status);
    }

    fn populate_details(&self, entry: &FileEntry, props_opt: Option<&ItemProperties>) {
        clear_box(&self.details_box);

        if let Some(p) = props_opt {
            add_meta_row(&self.details_box, "MIME", &p.mime_type);
            if let Some(ref dims) = p.image_dimensions {
                add_meta_row(&self.details_box, "Dimensions", dims);
            }
            if let Some(ref orig) = p.trash_original_path {
                add_meta_row(&self.details_box, "From", orig);
            }
            if let Some(ref target) = p.symlink_target {
                add_meta_row(&self.details_box, "Target", target);
            }
            if let Some(ref gs) = p.git_status {
                add_meta_row(&self.details_box, "Git", gs);
            }
            if let Some(cnt) = p.direct_children {
                add_meta_row(&self.details_box, "Direct", &format!("{cnt} items"));
            }
            add_meta_row(
                &self.details_box,
                "Inode",
                &format!("{} ({} links)", p.inode, p.hard_links),
            );
            add_meta_row(&self.details_box, "Device", &p.device_id.to_string());
        } else {
            add_meta_row(&self.details_box, "Kind", entry.kind_label());
        }

        let path_row = gtk4::Box::new(gtk4::Orientation::Horizontal, 4);
        let path_lbl = make_value_label(&entry.path.to_string_lossy());
        let copy_btn = make_copy_btn(&entry.path.to_string_lossy(), "Copy full path", self.on_toast.clone());
        path_row.append(&path_lbl);
        path_row.append(&copy_btn);
        add_meta_widget_row(&self.details_box, "Path", &path_row);
    }
}

fn clear_box(b: &gtk4::Box) {
    while let Some(child) = b.first_child() {
        b.remove(&child);
    }
}

fn add_section_header(container: &gtk4::Box, title: &str) {
    let lbl = gtk4::Label::new(Some(title));
    lbl.add_css_class("alis-sidebar-section-title");
    lbl.set_xalign(0.0);
    lbl.set_width_chars(1);
    lbl.set_max_width_chars(1);
    lbl.set_ellipsize(gtk4::pango::EllipsizeMode::End);
    lbl.set_margin_top(4);
    container.append(&lbl);
}

fn add_muted_note(container: &gtk4::Box, text: &str) {
    let lbl = gtk4::Label::new(Some(text));
    lbl.add_css_class("alis-muted");
    lbl.set_xalign(0.0);
    lbl.set_wrap(true);
    lbl.set_wrap_mode(gtk4::pango::WrapMode::WordChar);
    lbl.set_width_chars(1);
    lbl.set_max_width_chars(1);
    container.append(&lbl);
}

fn make_tab_btn(label: &str, tooltip: &str, group: Option<&gtk4::ToggleButton>) -> gtk4::ToggleButton {
    let lbl = gtk4::Label::new(Some(label));
    lbl.set_xalign(0.5);
    lbl.set_width_chars(1);
    lbl.set_max_width_chars(1);
    lbl.set_ellipsize(gtk4::pango::EllipsizeMode::End);
    let btn = gtk4::ToggleButton::new();
    btn.set_child(Some(&lbl));
    btn.add_css_class("alis-props-tab-btn");
    btn.set_hexpand(true);
    btn.set_focus_on_click(false);
    btn.set_tooltip_text(Some(tooltip));
    if let Some(g) = group {
        btn.set_group(Some(g));
    }
    btn
}

fn make_action_btn(label: &str, tooltip: &str) -> gtk4::Button {
    let lbl = gtk4::Label::new(Some(label));
    lbl.set_xalign(0.5);
    lbl.set_width_chars(1);
    lbl.set_max_width_chars(1);
    lbl.set_ellipsize(gtk4::pango::EllipsizeMode::End);
    let btn = gtk4::Button::new();
    btn.set_child(Some(&lbl));
    btn.add_css_class("alis-inspector-action-btn");
    btn.set_hexpand(true);
    btn.set_focus_on_click(false);
    btn.set_tooltip_text(Some(tooltip));
    btn
}

fn make_copy_btn(text: &str, tooltip: &str, on_toast: Rc<dyn Fn(String)>) -> gtk4::Button {
    let btn = gtk4::Button::from_icon_name("edit-copy-symbolic");
    btn.add_css_class("alis-act-btn");
    btn.set_focus_on_click(false);
    btn.set_valign(gtk4::Align::Start);
    btn.set_tooltip_text(Some(tooltip));
    let txt = text.to_string();
    btn.connect_clicked(move |_| {
        if let Some(disp) = gtk4::gdk::Display::default() {
            disp.clipboard().set_text(&txt);
        }
        on_toast("Copied path to clipboard".into());
    });
    btn
}

fn make_value_label(value: &str) -> gtk4::Label {
    let v = gtk4::Label::new(Some(value));
    v.set_xalign(0.0);
    v.set_hexpand(true);
    v.set_wrap(true);
    v.set_wrap_mode(gtk4::pango::WrapMode::WordChar);
    v.set_width_chars(1);
    v.set_max_width_chars(1);
    v.set_selectable(true);
    v
}

fn add_meta_row(container: &gtk4::Box, label: &str, value: &str) {
    let v = make_value_label(value);
    add_meta_widget_row(container, label, &v);
}

fn add_meta_widget_row(container: &gtk4::Box, label: &str, widget: &impl IsA<gtk4::Widget>) {
    let row = gtk4::Box::new(gtk4::Orientation::Horizontal, 6);
    let k = gtk4::Label::new(Some(label));
    k.add_css_class("alis-muted");
    k.set_width_request(54);
    k.set_ellipsize(gtk4::pango::EllipsizeMode::End);
    k.set_xalign(0.0);
    k.set_valign(gtk4::Align::Start);
    row.append(&k);
    row.append(widget);
    container.append(&row);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::BookmarkEntry;
    use crate::ui::sidebar::SidebarPanel;
    use std::fs;

    #[test]
    #[ignore = "requires GTK4 display (run under GDK_BACKEND=broadway with --test-threads=1)"]
    fn gtk4_broadway_pane_minimum_width_fits_without_clipping() {
        gtk4::init().expect("gtk4::init under broadway");
        let palette = crate::theme::AlisPalette::default();
        let css = palette.to_css();
        let provider = gtk4::CssProvider::new();
        provider.load_from_string(&css);
        if let Some(display) = gtk4::gdk::Display::default() {
            gtk4::style_context_add_provider_for_display(
                &display,
                &provider,
                gtk4::STYLE_PROVIDER_PRIORITY_APPLICATION,
            );
        }

        let tmp = std::env::temp_dir().join(format!(
            "alis-files-boundary-test-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&tmp);
        let nested = tmp.join("DeepNestedWorkspaceFolderWithLongNameForTesting");
        fs::create_dir_all(&nested).unwrap();
        let long_file = nested.join("VeryLongFilenameForBoundaryTestingArchive_2026_11_25.tar.gz");
        fs::write(&long_file, b"hello boundary").unwrap();

        let inspector = InspectorPanel::new(
            Rc::new(|_| {}),
            Rc::new(|_| {}),
            Rc::new(|_| {}),
            Rc::new(|_| {}),
            Rc::new(|_| {}),
            380,
        );
        if let Ok(entry) = FileEntry::from_path(long_file) {
            inspector.inspect_entry(&entry, false);
        }

        let content = inspector.root.child().expect("inspector inner content");
        let (min_req, _) = content.preferred_size();
        assert!(
            min_req.width() <= 200,
            "Inspector inner content min width {}px exceeds 200px pane minimum",
            min_req.width()
        );
        let (actions_min, _) = inspector.actions_box.preferred_size();
        assert!(
            actions_min.width() <= 178,
            "Inspector actions row min width {}px exceeds 178px inner width at 200px pane",
            actions_min.width()
        );
        let (tabs_min, _) = inspector.props_tabs_row.preferred_size();
        assert!(
            tabs_min.width() <= 180,
            "Properties tab bar min width {}px exceeds 180px inner width at 200px pane",
            tabs_min.width()
        );

        let sidebar = SidebarPanel::new(
            Rc::new(|_| {}),
            Rc::new(|_| {}),
            Rc::new(|_| {}),
        );
        sidebar.rebuild_bookmarks(&[BookmarkEntry {
            name: "VeryLongBookmarkDirectoryNameExceedingRailWidth".into(),
            path: nested.to_string_lossy().to_string(),
        }]);
        let sb_child = sidebar.root.child().expect("sidebar inner content");
        let (sb_min, _) = sb_child.preferred_size();
        assert!(
            sb_min.width() <= 156,
            "Sidebar inner content min width {}px exceeds 156px rail minimum",
            sb_min.width()
        );

        let _ = fs::remove_dir_all(&tmp);
    }
}
