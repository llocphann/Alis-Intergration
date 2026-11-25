use crate::config::{BookmarkEntry, home_dir};
use crate::model::{format_size, is_trash_dir, trash_files_dir};
use crate::mounts::DriveItem;
use gtk4::gio;
use gtk4::glib;
use gtk4::prelude::*;
use std::cell::{Cell, RefCell};
use std::fs;
use std::path::{Path, PathBuf};
use std::rc::Rc;

#[derive(Clone)]
pub struct SidebarPanel {
    pub root: gtk4::ScrolledWindow,
    places_box: gtk4::Box,
    bookmarks_box: gtk4::Box,
    drives_box: gtk4::Box,
    places_rev: gtk4::Revealer,
    bookmarks_rev: gtk4::Revealer,
    drives_rev: gtk4::Revealer,
    place_buttons: Rc<RefCell<Vec<(PathBuf, gtk4::Button)>>>,
    bookmark_buttons: Rc<RefCell<Vec<(PathBuf, gtk4::Button)>>>,
    drive_buttons: Rc<RefCell<Vec<(PathBuf, gtk4::Button)>>>,
    active_path: Rc<RefCell<PathBuf>>,
    cached_bookmarks: Rc<RefCell<Vec<BookmarkEntry>>>,
    focused_row_idx: Rc<Cell<Option<usize>>>,
    pane_focused: Rc<Cell<bool>>,
    on_navigate: Rc<dyn Fn(PathBuf)>,
    on_remove_bookmark: Rc<dyn Fn(String)>,
    on_eject_result: Rc<dyn Fn(Result<String, String>)>,
    _volume_monitor: gio::VolumeMonitor,
}

impl SidebarPanel {
    pub fn new(
        on_navigate: Rc<dyn Fn(PathBuf)>,
        on_remove_bookmark: Rc<dyn Fn(String)>,
        on_eject_result: Rc<dyn Fn(Result<String, String>)>,
    ) -> Self {
        let root = gtk4::ScrolledWindow::new();
        root.set_width_request(228);
        root.set_hexpand(false);
        root.set_vexpand(true);
        root.set_hscrollbar_policy(gtk4::PolicyType::External);
        root.set_propagate_natural_width(false);
        root.add_css_class("alis-sidebar");

        let vbox = gtk4::Box::new(gtk4::Orientation::Vertical, 2);

        let places_box = gtk4::Box::new(gtk4::Orientation::Vertical, 1);
        let places_rev = gtk4::Revealer::new();
        places_rev.set_transition_type(gtk4::RevealerTransitionType::SlideDown);
        places_rev.set_reveal_child(true);
        places_rev.set_child(Some(&places_box));
        let places_hdr = collapsible_section("Places", &places_rev);

        let bookmarks_box = gtk4::Box::new(gtk4::Orientation::Vertical, 1);
        let bookmarks_rev = gtk4::Revealer::new();
        bookmarks_rev.set_transition_type(gtk4::RevealerTransitionType::SlideDown);
        bookmarks_rev.set_reveal_child(true);
        bookmarks_rev.set_child(Some(&bookmarks_box));
        let bookmarks_hdr = collapsible_section("Bookmarks", &bookmarks_rev);

        let drives_box = gtk4::Box::new(gtk4::Orientation::Vertical, 2);
        let drives_rev = gtk4::Revealer::new();
        drives_rev.set_transition_type(gtk4::RevealerTransitionType::SlideDown);
        drives_rev.set_reveal_child(true);
        drives_rev.set_child(Some(&drives_box));
        let drives_hdr = collapsible_section("Drives", &drives_rev);

        vbox.append(&places_hdr);
        vbox.append(&places_rev);
        vbox.append(&bookmarks_hdr);
        vbox.append(&bookmarks_rev);
        vbox.append(&drives_hdr);
        vbox.append(&drives_rev);

        root.set_child(Some(&vbox));

        let volume_monitor = gio::VolumeMonitor::get();

        let panel = Self {
            root,
            places_box,
            bookmarks_box,
            drives_box,
            places_rev,
            bookmarks_rev,
            drives_rev,
            place_buttons: Rc::new(RefCell::new(Vec::new())),
            bookmark_buttons: Rc::new(RefCell::new(Vec::new())),
            drive_buttons: Rc::new(RefCell::new(Vec::new())),
            active_path: Rc::new(RefCell::new(home_dir())),
            cached_bookmarks: Rc::new(RefCell::new(Vec::new())),
            focused_row_idx: Rc::new(Cell::new(None)),
            pane_focused: Rc::new(Cell::new(false)),
            on_navigate,
            on_remove_bookmark,
            on_eject_result,
            _volume_monitor: volume_monitor.clone(),
        };

        panel.rebuild_places();
        panel.rebuild_drives();

        {
            let p = panel.clone();
            volume_monitor.connect_mount_added(move |_, _| p.rebuild_drives());
        }
        {
            let p = panel.clone();
            volume_monitor.connect_mount_removed(move |_, _| p.rebuild_drives());
        }
        {
            let p = panel.clone();
            volume_monitor.connect_volume_added(move |_, _| p.rebuild_drives());
        }
        {
            let p = panel.clone();
            volume_monitor.connect_volume_removed(move |_, _| p.rebuild_drives());
        }

        panel
    }

    pub fn set_active_path(&self, path: &Path) {
        let changed = *self.active_path.borrow() != path;
        *self.active_path.borrow_mut() = path.to_path_buf();
        if changed {
            for list in [
                self.place_buttons.borrow(),
                self.bookmark_buttons.borrow(),
                self.drive_buttons.borrow(),
            ] {
                for (btn_path, btn) in list.iter() {
                    if btn_path == path {
                        btn.add_css_class("active-place");
                    } else {
                        btn.remove_css_class("active-place");
                    }
                }
            }
        }
    }

    pub fn rebuild_places(&self) {
        clear_box(&self.places_box);
        self.place_buttons.borrow_mut().clear();
        let active = self.active_path.borrow().clone();
        let home = home_dir();
        let trash_dir = trash_files_dir();
        let trash_count = fs::read_dir(&trash_dir)
            .map(|it| it.filter_map(Result::ok).count())
            .unwrap_or(0);

        let places: Vec<(&str, &str, PathBuf, Option<String>)> = vec![
            ("Home", "user-home-symbolic", home.clone(), None),
            ("Desktop", "user-desktop-symbolic", home.join("Desktop"), None),
            ("Documents", "folder-documents-symbolic", home.join("Documents"), None),
            ("Downloads", "folder-download-symbolic", home.join("Downloads"), None),
            ("Pictures", "folder-pictures-symbolic", home.join("Pictures"), None),
            ("Music", "folder-music-symbolic", home.join("Music"), None),
            ("Videos", "folder-videos-symbolic", home.join("Videos"), None),
            (
                "Trash",
                if trash_count > 0 {
                    "user-trash-full-symbolic"
                } else {
                    "user-trash-symbolic"
                },
                trash_dir.clone(),
                if trash_count > 0 {
                    Some(trash_count.to_string())
                } else {
                    None
                },
            ),
        ];

        for (label, icon, path, badge) in places {
            if !is_trash_dir(&path) && path != home && !path.is_dir() {
                continue;
            }
            let btn = make_place_button(
                label,
                icon,
                &path,
                active == path,
                badge.as_deref(),
                self.on_navigate.clone(),
            );
            self.place_buttons.borrow_mut().push((path, btn.clone()));
            self.places_box.append(&btn);
        }
    }

    pub fn rebuild_bookmarks(&self, bookmarks: &[BookmarkEntry]) {
        *self.cached_bookmarks.borrow_mut() = bookmarks.to_vec();
        clear_box(&self.bookmarks_box);
        self.bookmark_buttons.borrow_mut().clear();
        if bookmarks.is_empty() {
            let empty = gtk4::Label::new(Some("No bookmarks yet"));
            empty.add_css_class("alis-muted");
            empty.set_xalign(0.0);
            empty.set_width_chars(1);
            empty.set_ellipsize(gtk4::pango::EllipsizeMode::End);
            empty.set_margin_start(14);
            empty.set_margin_top(4);
            empty.set_margin_bottom(4);
            self.bookmarks_box.append(&empty);
            return;
        }
        let active = self.active_path.borrow().clone();
        for bm in bookmarks {
            let row = gtk4::Box::new(gtk4::Orientation::Horizontal, 2);
            let target = PathBuf::from(&bm.path);
            let btn = make_place_button(
                &bm.name,
                "user-bookmarks-symbolic",
                &target,
                active == target,
                None,
                self.on_navigate.clone(),
            );
            btn.set_hexpand(true);

            let del = gtk4::Button::from_icon_name("window-close-symbolic");
            del.add_css_class("alis-tab-close");
            del.set_focus_on_click(false);
            del.set_valign(gtk4::Align::Center);
            del.set_margin_end(6);
            del.set_tooltip_text(Some("Remove bookmark"));
            {
                let path_str = bm.path.clone();
                let cb = self.on_remove_bookmark.clone();
                del.connect_clicked(move |_| cb(path_str.clone()));
            }
            self.bookmark_buttons
                .borrow_mut()
                .push((target, btn.clone()));
            row.append(&btn);
            row.append(&del);
            self.bookmarks_box.append(&row);
        }
    }

    pub fn rebuild_drives(&self) {
        clear_box(&self.drives_box);
        self.drive_buttons.borrow_mut().clear();
        let active = self.active_path.borrow().clone();

        // Always include Computer (/) at top of Drives matching inir-files Rail.qml
        let (root_total, root_used) = crate::mounts::filesystem_space(Path::new("/"));
        let comp_card = gtk4::Box::new(gtk4::Orientation::Vertical, 2);
        let comp_btn = make_place_button(
            "Computer",
            "computer-symbolic",
            Path::new("/"),
            active == Path::new("/"),
            None,
            self.on_navigate.clone(),
        );
        self.drive_buttons
            .borrow_mut()
            .push((PathBuf::from("/"), comp_btn.clone()));
        comp_card.append(&comp_btn);
        if root_total > 0 {
            let bar = gtk4::ProgressBar::new();
            bar.add_css_class("alis-drive-bar");
            bar.set_fraction((root_used as f64 / root_total as f64).clamp(0.0, 1.0));
            bar.set_margin_start(14);
            bar.set_margin_end(14);
            let free = root_total.saturating_sub(root_used);
            bar.set_tooltip_text(Some(&format!(
                "{} free of {}",
                format_size(free),
                format_size(root_total)
            )));
            comp_card.append(&bar);
        }
        self.drives_box.append(&comp_card);

        let drives: Vec<DriveItem> = crate::mounts::list_drives();
        for drive in drives {
            if drive.mount_point.as_deref() == Some(Path::new("/")) {
                continue;
            }
            let card = gtk4::Box::new(gtk4::Orientation::Vertical, 2);

            let top = gtk4::Box::new(gtk4::Orientation::Horizontal, 2);
            if let Some(ref mp) = drive.mount_point {
                let btn = make_place_button(
                    &drive.name,
                    &drive.icon_name,
                    mp,
                    active == *mp,
                    None,
                    self.on_navigate.clone(),
                );
                btn.set_hexpand(true);
                self.drive_buttons
                    .borrow_mut()
                    .push((mp.clone(), btn.clone()));
                top.append(&btn);

                if drive.can_eject {
                    let eject_btn = gtk4::Button::from_icon_name("media-eject-symbolic");
                    eject_btn.add_css_class("alis-tab-close");
                    eject_btn.set_focus_on_click(false);
                    eject_btn.set_valign(gtk4::Align::Center);
                    eject_btn.set_margin_end(6);
                    eject_btn.set_tooltip_text(Some(if drive.is_removable {
                        "Safely eject"
                    } else {
                        "Unmount"
                    }));
                    let mp_c = mp.clone();
                    let dev = drive.block_device.clone();
                    let removable = drive.is_removable;
                    let cb = self.on_eject_result.clone();
                    let panel_clone = self.clone();
                    eject_btn.connect_clicked(move |_| {
                        let mp_bg = mp_c.clone();
                        let dev_bg = dev.clone();
                        let cb_ui = cb.clone();
                        let p_ui = panel_clone.clone();
                        let (tx, rx) = std::sync::mpsc::channel();
                        std::thread::spawn(move || {
                            let res =
                                crate::mounts::safe_unmount(&mp_bg, dev_bg.as_deref(), removable);
                            let _ = tx.send(res);
                        });
                        glib::timeout_add_local(std::time::Duration::from_millis(60), move || {
                            match rx.try_recv() {
                                Ok(res) => {
                                    cb_ui(res);
                                    p_ui.rebuild_drives();
                                    glib::ControlFlow::Break
                                }
                                Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                                    glib::ControlFlow::Break
                                }
                                Err(std::sync::mpsc::TryRecvError::Empty) => {
                                    glib::ControlFlow::Continue
                                }
                            }
                        });
                    });
                    top.append(&eject_btn);
                }
            } else if let Some(ref dev) = drive.block_device {
                let hbox = gtk4::Box::new(gtk4::Orientation::Horizontal, 10);
                let img = gtk4::Image::from_icon_name(&drive.icon_name);
                img.set_pixel_size(17);
                img.set_opacity(0.65);
                let lbl = gtk4::Label::new(Some(&drive.name));
                lbl.set_xalign(0.0);
                lbl.set_width_chars(1);
                lbl.set_ellipsize(gtk4::pango::EllipsizeMode::End);
                lbl.set_hexpand(true);
                let hint = gtk4::Label::new(Some("Mount"));
                hint.add_css_class("alis-muted");
                hbox.append(&img);
                hbox.append(&lbl);
                hbox.append(&hint);

                let btn = gtk4::Button::new();
                btn.set_child(Some(&hbox));
                btn.set_has_frame(false);
                btn.set_focus_on_click(false);
                btn.add_css_class("alis-sidebar-row");
                btn.set_hexpand(true);
                btn.set_tooltip_text(Some(&format!("Mount {dev}")));

                let dev_c = dev.clone();
                let nav_cb = self.on_navigate.clone();
                let res_cb = self.on_eject_result.clone();
                let panel_clone = self.clone();
                btn.connect_clicked(move |_| {
                    let dev_bg = dev_c.clone();
                    let nav_ui = nav_cb.clone();
                    let res_ui = res_cb.clone();
                    let p_ui = panel_clone.clone();
                    let (tx, rx) = std::sync::mpsc::channel();
                    std::thread::spawn(move || {
                        let res = crate::mounts::mount_volume(&dev_bg);
                        let _ = tx.send(res);
                    });
                    glib::timeout_add_local(std::time::Duration::from_millis(60), move || {
                        match rx.try_recv() {
                            Ok(Ok(mounted_path)) => {
                                p_ui.rebuild_drives();
                                nav_ui(mounted_path);
                                glib::ControlFlow::Break
                            }
                            Ok(Err(err)) => {
                                res_ui(Err(err));
                                glib::ControlFlow::Break
                            }
                            Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                                glib::ControlFlow::Break
                            }
                            Err(std::sync::mpsc::TryRecvError::Empty) => {
                                glib::ControlFlow::Continue
                            }
                        }
                    });
                });
                top.append(&btn);
            }
            card.append(&top);

            if drive.total_bytes > 0 {
                let bar = gtk4::ProgressBar::new();
                bar.add_css_class("alis-drive-bar");
                bar.set_fraction(drive.usage_fraction());
                bar.set_margin_start(14);
                bar.set_margin_end(14);
                let free = drive.total_bytes.saturating_sub(drive.used_bytes);
                bar.set_tooltip_text(Some(&format!(
                    "{} free of {}",
                    format_size(free),
                    format_size(drive.total_bytes)
                )));
                card.append(&bar);
            }
            self.drives_box.append(&card);
        }
        self.apply_kbd_focus_visual();
    }

    fn visible_row_buttons(&self) -> Vec<gtk4::Button> {
        let mut out = Vec::new();
        for (rev, bx) in [
            (&self.places_rev, &self.places_box),
            (&self.bookmarks_rev, &self.bookmarks_box),
            (&self.drives_rev, &self.drives_box),
        ] {
            if rev.reveals_child() {
                collect_sidebar_row_buttons(bx.upcast_ref(), &mut out);
            }
        }
        out
    }

    fn apply_kbd_focus_visual(&self) {
        let rows = self.visible_row_buttons();
        for b in &rows {
            b.remove_css_class("rail-kbd-focus");
        }
        if !self.pane_focused.get() || rows.is_empty() {
            return;
        }
        let active = self.active_path.borrow().clone();
        let idx = self.focused_row_idx.get().unwrap_or_else(|| {
            let active_idx = self
                .place_buttons
                .borrow()
                .iter()
                .position(|(p, _)| *p == active)
                .unwrap_or(0);
            active_idx.min(rows.len().saturating_sub(1))
        });
        let clamped = idx.min(rows.len() - 1);
        self.focused_row_idx.set(Some(clamped));
        rows[clamped].add_css_class("rail-kbd-focus");
    }

    pub fn set_pane_focused(&self, focused: bool) {
        self.pane_focused.set(focused);
        if focused {
            self.root.add_css_class("pane-focused");
        } else {
            self.root.remove_css_class("pane-focused");
        }
        self.apply_kbd_focus_visual();
    }

    pub fn move_keyboard_focus(&self, delta: i32) {
        let rows = self.visible_row_buttons();
        if rows.is_empty() {
            return;
        }
        let cur = self.focused_row_idx.get().unwrap_or(0) as isize;
        let next = (cur + delta as isize).clamp(0, rows.len() as isize - 1) as usize;
        self.focused_row_idx.set(Some(next));
        self.apply_kbd_focus_visual();
        rows[next].grab_focus();
    }

    pub fn activate_focused_row(&self) -> bool {
        let rows = self.visible_row_buttons();
        if rows.is_empty() {
            return false;
        }
        let idx = self.focused_row_idx.get().unwrap_or(0).min(rows.len() - 1);
        rows[idx].emit_clicked();
        true
    }
}

fn collect_sidebar_row_buttons(widget: &gtk4::Widget, out: &mut Vec<gtk4::Button>) {
    if !widget.is_visible() {
        return;
    }
    if let Ok(btn) = widget.clone().downcast::<gtk4::Button>()
        && btn.has_css_class("alis-sidebar-row")
    {
        out.push(btn);
        return;
    }
    let mut child = widget.first_child();
    while let Some(c) = child {
        collect_sidebar_row_buttons(&c, out);
        child = c.next_sibling();
    }
}

fn collapsible_section(text: &str, revealer: &gtk4::Revealer) -> gtk4::Button {
    let hbox = gtk4::Box::new(gtk4::Orientation::Horizontal, 4);
    let lbl = gtk4::Label::new(Some(text));
    lbl.set_xalign(0.0);
    lbl.set_width_chars(1);
    lbl.set_ellipsize(gtk4::pango::EllipsizeMode::End);
    lbl.set_hexpand(true);
    let chev = gtk4::Image::from_icon_name("pan-down-symbolic");
    chev.set_pixel_size(14);
    hbox.append(&lbl);
    hbox.append(&chev);

    let btn = gtk4::Button::new();
    btn.set_child(Some(&hbox));
    btn.set_has_frame(false);
    btn.set_can_focus(false);
    btn.set_focus_on_click(false);
    btn.add_css_class("alis-sidebar-section-btn");

    let expanded = Rc::new(Cell::new(true));
    let rev = revealer.clone();
    btn.connect_clicked(move |_| {
        let next = !expanded.get();
        expanded.set(next);
        rev.set_reveal_child(next);
        chev.set_icon_name(Some(if next {
            "pan-down-symbolic"
        } else {
            "pan-end-symbolic"
        }));
    });
    btn
}

fn make_place_button(
    label: &str,
    icon_name: &str,
    target: &Path,
    is_active: bool,
    badge: Option<&str>,
    on_navigate: Rc<dyn Fn(PathBuf)>,
) -> gtk4::Button {
    let hbox = gtk4::Box::new(gtk4::Orientation::Horizontal, 10);
    let img = gtk4::Image::from_icon_name(icon_name);
    img.set_pixel_size(17);
    let lbl = gtk4::Label::new(Some(label));
    lbl.set_xalign(0.0);
    lbl.set_width_chars(1);
    lbl.set_ellipsize(gtk4::pango::EllipsizeMode::End);
    lbl.set_hexpand(true);
    hbox.append(&img);
    hbox.append(&lbl);

    if let Some(b) = badge {
        let count_lbl = gtk4::Label::new(Some(b));
        count_lbl.add_css_class("alis-muted");
        hbox.append(&count_lbl);
    }

    let btn = gtk4::Button::new();
    btn.set_child(Some(&hbox));
    btn.set_has_frame(false);
    btn.set_focus_on_click(false);
    btn.add_css_class("alis-sidebar-row");
    if is_active {
        btn.add_css_class("active-place");
    }
    let path = target.to_path_buf();
    btn.connect_clicked(move |_| on_navigate(path.clone()));
    btn
}

fn clear_box(b: &gtk4::Box) {
    while let Some(child) = b.first_child() {
        b.remove(&child);
    }
}
