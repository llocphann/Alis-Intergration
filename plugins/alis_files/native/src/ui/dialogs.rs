use crate::archive::ArchiveFormat;
use crate::fs_ops::{
    BulkRenameRule, CaseTransform, execute_bulk_rename, preview_bulk_rename,
};
use crate::model::format_size;
use gtk4::gdk;
use gtk4::glib;
use gtk4::prelude::*;
use std::cell::RefCell;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

fn attach_escape_close(win: &gtk4::Window) {
    let key_ctrl = gtk4::EventControllerKey::new();
    key_ctrl.set_propagation_phase(gtk4::PropagationPhase::Capture);
    let w = win.clone();
    key_ctrl.connect_key_pressed(move |_, key, _, _| {
        if key == gdk::Key::Escape {
            w.close();
            glib::Propagation::Stop
        } else {
            glib::Propagation::Proceed
        }
    });
    win.add_controller(key_ctrl);
}

/// Simple single-line text input dialog (New Folder, New File, Rename).
pub fn open_name_prompt<F>(
    parent: &gtk4::ApplicationWindow,
    title: &str,
    label: &str,
    initial: &str,
    confirm_label: &str,
    on_submit: F,
) where
    F: FnOnce(String) + 'static,
{
    open_name_prompt_with_selection(parent, title, label, initial, confirm_label, true, on_submit);
}

pub fn open_name_prompt_with_selection<F>(
    parent: &gtk4::ApplicationWindow,
    title: &str,
    label: &str,
    initial: &str,
    confirm_label: &str,
    select_stem_only: bool,
    on_submit: F,
) where
    F: FnOnce(String) + 'static,
{
    let win = gtk4::Window::builder()
        .title(title)
        .transient_for(parent)
        .modal(true)
        .default_width(420)
        .resizable(false)
        .build();
    win.add_css_class("alis-files-window");
    win.add_css_class("alis-dialog-surface");

    let vbox = gtk4::Box::new(gtk4::Orientation::Vertical, 10);
    vbox.set_margin_top(16);
    vbox.set_margin_bottom(16);
    vbox.set_margin_start(16);
    vbox.set_margin_end(16);

    let lbl = gtk4::Label::new(Some(label));
    lbl.set_xalign(0.0);
    vbox.append(&lbl);

    let entry = gtk4::Entry::new();
    entry.set_text(initial);
    entry.add_css_class("alis-path-entry");
    vbox.append(&entry);

    let actions = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
    actions.set_halign(gtk4::Align::End);
    let cancel_btn = gtk4::Button::with_label("Cancel");
    cancel_btn.add_css_class("alis-flat-btn");
    let ok_btn = gtk4::Button::with_label(confirm_label);
    ok_btn.add_css_class("alis-accent-btn");
    actions.append(&cancel_btn);
    actions.append(&ok_btn);
    vbox.append(&actions);

    let cb_cell = Rc::new(RefCell::new(Some(on_submit)));
    let submit = {
        let cb = cb_cell.clone();
        let e = entry.clone();
        let w = win.clone();
        Rc::new(move || {
            let val = e.text().to_string();
            w.close();
            if let Some(f) = cb.borrow_mut().take() {
                f(val);
            }
        })
    };

    {
        let s = submit.clone();
        ok_btn.connect_clicked(move |_| s());
    }
    {
        let s = submit.clone();
        entry.connect_activate(move |_| s());
    }
    {
        let w = win.clone();
        cancel_btn.connect_clicked(move |_| w.close());
    }

    attach_escape_close(&win);

    win.set_child(Some(&vbox));
    win.present();
    entry.grab_focus();
    // Pre-select stem if renaming a regular file with an extension; folders/dotfiles select all.
    if !initial.is_empty() {
        if select_stem_only {
            let (stem, _) = crate::fs_ops::split_name_ext(initial);
            entry.select_region(0, stem.chars().count() as i32);
        } else {
            entry.select_region(0, -1);
        }
    }
}

/// Confirmation dialog for permanent delete or empty trash.
pub fn open_confirm_dialog<F>(
    parent: &gtk4::ApplicationWindow,
    title: &str,
    message: &str,
    confirm_label: &str,
    destructive: bool,
    on_confirm: F,
) where
    F: FnOnce() + 'static,
{
    let win = gtk4::Window::builder()
        .title(title)
        .transient_for(parent)
        .modal(true)
        .default_width(420)
        .resizable(false)
        .build();
    win.add_css_class("alis-files-window");
    win.add_css_class("alis-dialog-surface");

    let vbox = gtk4::Box::new(gtk4::Orientation::Vertical, 12);
    vbox.set_margin_top(16);
    vbox.set_margin_bottom(16);
    vbox.set_margin_start(16);
    vbox.set_margin_end(16);

    let msg = gtk4::Label::new(Some(message));
    msg.set_wrap(true);
    msg.set_xalign(0.0);
    vbox.append(&msg);

    let actions = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
    actions.set_halign(gtk4::Align::End);
    let cancel_btn = gtk4::Button::with_label("Cancel");
    cancel_btn.add_css_class("alis-flat-btn");
    let ok_btn = gtk4::Button::with_label(confirm_label);
    ok_btn.add_css_class(if destructive {
        "alis-danger-btn"
    } else {
        "alis-accent-btn"
    });
    actions.append(&cancel_btn);
    actions.append(&ok_btn);
    vbox.append(&actions);

    let cb_cell = Rc::new(RefCell::new(Some(on_confirm)));
    {
        let cb = cb_cell.clone();
        let w = win.clone();
        ok_btn.connect_clicked(move |_| {
            w.close();
            if let Some(f) = cb.borrow_mut().take() {
                f();
            }
        });
    }
    {
        let w = win.clone();
        cancel_btn.connect_clicked(move |_| w.close());
    }
    attach_escape_close(&win);
    win.set_child(Some(&vbox));
    win.present();
}

/// Bulk Rename dialog with live preview table, find/replace, regex, prefix/suffix, numbering, case transform.
pub fn open_bulk_rename_dialog<F>(
    parent: &gtk4::ApplicationWindow,
    sources: Vec<PathBuf>,
    on_done: F,
) where
    F: FnOnce(Vec<(PathBuf, PathBuf)>) + 'static,
{
    let win = gtk4::Window::builder()
        .title(format!("Bulk Rename ({} items)", sources.len()))
        .transient_for(parent)
        .modal(true)
        .default_width(740)
        .default_height(560)
        .build();
    win.add_css_class("alis-files-window");
    win.add_css_class("alis-dialog-surface");

    let root = gtk4::Box::new(gtk4::Orientation::Vertical, 10);
    root.set_margin_top(14);
    root.set_margin_bottom(14);
    root.set_margin_start(16);
    root.set_margin_end(16);

    let controls = gtk4::Grid::new();
    controls.set_row_spacing(8);
    controls.set_column_spacing(10);

    let find_entry = gtk4::Entry::builder().placeholder_text("Find text or regex…").hexpand(true).build();
    let replace_entry = gtk4::Entry::builder().placeholder_text("Replace with…").hexpand(true).build();
    let regex_chk = gtk4::CheckButton::with_label("Regex");

    let prefix_entry = gtk4::Entry::builder().placeholder_text("Prefix…").hexpand(true).build();
    let suffix_entry = gtk4::Entry::builder().placeholder_text("Suffix…").hexpand(true).build();

    let num_chk = gtk4::CheckButton::with_label("Add numbering");
    let start_spin = gtk4::SpinButton::with_range(0.0, 99999.0, 1.0);
    start_spin.set_value(1.0);
    let pad_spin = gtk4::SpinButton::with_range(1.0, 6.0, 1.0);
    pad_spin.set_value(2.0);
    let num_start_chk = gtk4::CheckButton::with_label("At start");

    let case_dd = gtk4::DropDown::from_strings(&["Keep Case", "lowercase", "UPPERCASE", "Title Case"]);
    let preserve_ext_chk = gtk4::CheckButton::with_label("Preserve extension");
    preserve_ext_chk.set_active(true);

    controls.attach(&gtk4::Label::new(Some("Find:")), 0, 0, 1, 1);
    controls.attach(&find_entry, 1, 0, 2, 1);
    controls.attach(&gtk4::Label::new(Some("Replace:")), 3, 0, 1, 1);
    controls.attach(&replace_entry, 4, 0, 2, 1);
    controls.attach(&regex_chk, 6, 0, 1, 1);

    controls.attach(&gtk4::Label::new(Some("Prefix:")), 0, 1, 1, 1);
    controls.attach(&prefix_entry, 1, 1, 2, 1);
    controls.attach(&gtk4::Label::new(Some("Suffix:")), 3, 1, 1, 1);
    controls.attach(&suffix_entry, 4, 1, 2, 1);
    controls.attach(&preserve_ext_chk, 6, 1, 1, 1);

    controls.attach(&num_chk, 0, 2, 2, 1);
    let num_opts = gtk4::Box::new(gtk4::Orientation::Horizontal, 6);
    num_opts.append(&gtk4::Label::new(Some("Start:")));
    num_opts.append(&start_spin);
    num_opts.append(&gtk4::Label::new(Some("Pad:")));
    num_opts.append(&pad_spin);
    num_opts.append(&num_start_chk);
    controls.attach(&num_opts, 2, 2, 3, 1);
    controls.attach(&case_dd, 5, 2, 2, 1);

    root.append(&controls);

    let status_lbl = gtk4::Label::new(Some("Preview"));
    status_lbl.set_xalign(0.0);
    status_lbl.add_css_class("alis-subtext");
    root.append(&status_lbl);

    let scroll = gtk4::ScrolledWindow::new();
    scroll.set_vexpand(true);
    let preview_list = gtk4::ListBox::new();
    preview_list.add_css_class("alis-file-list");
    preview_list.set_selection_mode(gtk4::SelectionMode::None);
    scroll.set_child(Some(&preview_list));
    root.append(&scroll);

    let actions = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
    actions.set_halign(gtk4::Align::End);
    let cancel_btn = gtk4::Button::with_label("Cancel");
    cancel_btn.add_css_class("alis-flat-btn");
    let apply_btn = gtk4::Button::with_label("Rename All");
    apply_btn.add_css_class("alis-accent-btn");
    actions.append(&cancel_btn);
    actions.append(&apply_btn);
    root.append(&actions);

    let current_preview = Rc::new(RefCell::new(Vec::new()));
    let sources_rc = Rc::new(sources);

    let refresh_preview = {
        let find_e = find_entry.clone();
        let rep_e = replace_entry.clone();
        let rx_c = regex_chk.clone();
        let pre_e = prefix_entry.clone();
        let suf_e = suffix_entry.clone();
        let num_c = num_chk.clone();
        let st_s = start_spin.clone();
        let pd_s = pad_spin.clone();
        let ns_c = num_start_chk.clone();
        let case_d = case_dd.clone();
        let ext_c = preserve_ext_chk.clone();
        let list = preview_list.clone();
        let st_lbl = status_lbl.clone();
        let app_b = apply_btn.clone();
        let srcs = sources_rc.clone();
        let cur_prev = current_preview.clone();
        Rc::new(move || {
            let rule = BulkRenameRule {
                find: find_e.text().to_string(),
                replace: rep_e.text().to_string(),
                use_regex: rx_c.is_active(),
                prefix: pre_e.text().to_string(),
                suffix: suf_e.text().to_string(),
                add_numbering: num_c.is_active(),
                number_start: st_s.value_as_int().max(0) as usize,
                number_step: 1,
                number_pad: pd_s.value_as_int().max(1) as usize,
                number_at_start: ns_c.is_active(),
                case_transform: match case_d.selected() {
                    1 => CaseTransform::Lowercase,
                    2 => CaseTransform::Uppercase,
                    3 => CaseTransform::TitleCase,
                    _ => CaseTransform::None,
                },
                preserve_extension: ext_c.is_active(),
            };
            while let Some(c) = list.first_child() {
                list.remove(&c);
            }
            match preview_bulk_rename(&srcs, &rule) {
                Err(err) => {
                    st_lbl.set_text(&format!("Error: {err}"));
                    app_b.set_sensitive(false);
                    cur_prev.borrow_mut().clear();
                }
                Ok(items) => {
                    let conflicts = items.iter().filter(|i| i.conflict.is_some()).count();
                    let changed = items.iter().filter(|i| i.old_name != i.new_name).count();
                    for item in &items {
                        let row = gtk4::Box::new(gtk4::Orientation::Horizontal, 10);
                        let old_l = gtk4::Label::new(Some(&item.old_name));
                        old_l.set_xalign(0.0);
                        old_l.set_hexpand(true);
                        old_l.set_ellipsize(gtk4::pango::EllipsizeMode::Middle);
                        let arrow = gtk4::Label::new(Some("→"));
                        arrow.add_css_class("alis-subtext");
                        let new_l = gtk4::Label::new(Some(&item.new_name));
                        new_l.set_xalign(0.0);
                        new_l.set_hexpand(true);
                        new_l.set_ellipsize(gtk4::pango::EllipsizeMode::Middle);
                        row.append(&old_l);
                        row.append(&arrow);
                        row.append(&new_l);
                        if let Some(ref c) = item.conflict {
                            let badge = gtk4::Label::new(Some(c));
                            badge.add_css_class("alis-git-badge");
                            badge.add_css_class("alis-git-conflict");
                            row.append(&badge);
                        }
                        list.append(&row);
                    }
                    st_lbl.set_text(&if conflicts > 0 {
                        format!("{changed} to rename — {conflicts} conflict(s) must be resolved")
                    } else {
                        format!("{changed} of {} item(s) will be renamed", items.len())
                    });
                    app_b.set_sensitive(conflicts == 0 && changed > 0);
                    *cur_prev.borrow_mut() = items;
                }
            }
        })
    };

    macro_rules! wire_entry {
        ($w:expr) => {{
            let r = refresh_preview.clone();
            $w.connect_changed(move |_| r());
        }};
    }
    wire_entry!(find_entry);
    wire_entry!(replace_entry);
    wire_entry!(prefix_entry);
    wire_entry!(suffix_entry);

    macro_rules! wire_chk {
        ($w:expr) => {{
            let r = refresh_preview.clone();
            $w.connect_toggled(move |_| r());
        }};
    }
    wire_chk!(regex_chk);
    wire_chk!(num_chk);
    wire_chk!(num_start_chk);
    wire_chk!(preserve_ext_chk);
    {
        let r = refresh_preview.clone();
        start_spin.connect_value_changed(move |_| r());
    }
    {
        let r = refresh_preview.clone();
        pad_spin.connect_value_changed(move |_| r());
    }
    {
        let r = refresh_preview.clone();
        case_dd.connect_selected_notify(move |_| r());
    }

    refresh_preview();

    let cb_cell = Rc::new(RefCell::new(Some(on_done)));
    {
        let cur_prev = current_preview.clone();
        let cb = cb_cell.clone();
        let st_lbl = status_lbl.clone();
        let w = win.clone();
        apply_btn.connect_clicked(move |_| {
            let items = cur_prev.borrow().clone();
            match execute_bulk_rename(&items) {
                Ok(pairs) => {
                    w.close();
                    if let Some(f) = cb.borrow_mut().take() {
                        f(pairs);
                    }
                }
                Err(e) => st_lbl.set_text(&format!("Rename failed: {e}")),
            }
        });
    }
    {
        let w = win.clone();
        cancel_btn.connect_clicked(move |_| w.close());
    }

    attach_escape_close(&win);
    win.set_child(Some(&root));
    win.present();
}

/// Compress selected items dialog.
pub fn open_compress_dialog<F>(
    parent: &gtk4::ApplicationWindow,
    default_name: &str,
    on_compress: F,
) where
    F: FnOnce(String, ArchiveFormat) + 'static,
{
    let win = gtk4::Window::builder()
        .title("Compress Items")
        .transient_for(parent)
        .modal(true)
        .default_width(440)
        .resizable(false)
        .build();
    win.add_css_class("alis-files-window");
    win.add_css_class("alis-dialog-surface");

    let vbox = gtk4::Box::new(gtk4::Orientation::Vertical, 10);
    vbox.set_margin_top(16);
    vbox.set_margin_bottom(16);
    vbox.set_margin_start(16);
    vbox.set_margin_end(16);

    let name_entry = gtk4::Entry::new();
    name_entry.set_text(default_name);
    name_entry.add_css_class("alis-path-entry");

    let labels: Vec<&str> = ArchiveFormat::ALL.iter().map(|f| f.label()).collect();
    let format_dd = gtk4::DropDown::from_strings(&labels);
    format_dd.set_selected(0);

    vbox.append(&gtk4::Label::builder().label("Archive name:").xalign(0.0).build());
    vbox.append(&name_entry);
    vbox.append(&gtk4::Label::builder().label("Format:").xalign(0.0).build());
    vbox.append(&format_dd);

    let actions = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
    actions.set_halign(gtk4::Align::End);
    let cancel_btn = gtk4::Button::with_label("Cancel");
    cancel_btn.add_css_class("alis-flat-btn");
    let ok_btn = gtk4::Button::with_label("Create Archive");
    ok_btn.add_css_class("alis-accent-btn");
    actions.append(&cancel_btn);
    actions.append(&ok_btn);
    vbox.append(&actions);

    let cb_cell = Rc::new(RefCell::new(Some(on_compress)));
    let submit = {
        let cb = cb_cell.clone();
        let ne = name_entry.clone();
        let dd = format_dd.clone();
        let w = win.clone();
        Rc::new(move || {
            let name = ne.text().to_string();
            let idx = (dd.selected() as usize).min(ArchiveFormat::ALL.len() - 1);
            let fmt = ArchiveFormat::ALL[idx];
            w.close();
            if let Some(f) = cb.borrow_mut().take() {
                f(name, fmt);
            }
        })
    };
    {
        let s = submit.clone();
        ok_btn.connect_clicked(move |_| s());
    }
    {
        let s = submit.clone();
        name_entry.connect_activate(move |_| s());
    }
    {
        let w = win.clone();
        cancel_btn.connect_clicked(move |_| w.close());
    }

    attach_escape_close(&win);
    win.set_child(Some(&vbox));
    win.present();
    name_entry.grab_focus();
}

/// Multithreaded Disk Space Analyzer dialog with drill-down navigation and proportional bars.
pub fn open_disk_analyzer_dialog(
    parent: &gtk4::ApplicationWindow,
    start_dir: PathBuf,
    on_open_in_files: Rc<dyn Fn(PathBuf)>,
) {
    let win = gtk4::Window::builder()
        .title("Disk Space Analyzer")
        .transient_for(parent)
        .modal(false)
        .default_width(760)
        .default_height(560)
        .build();
    win.add_css_class("alis-files-window");
    win.add_css_class("alis-dialog-surface");

    let root = gtk4::Box::new(gtk4::Orientation::Vertical, 10);
    root.set_margin_top(14);
    root.set_margin_bottom(14);
    root.set_margin_start(16);
    root.set_margin_end(16);

    let top = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
    let up_btn = gtk4::Button::from_icon_name("go-up-symbolic");
    up_btn.add_css_class("alis-flat-btn");
    up_btn.set_tooltip_text(Some("Parent folder"));

    let path_lbl = gtk4::Label::new(Some(&start_dir.to_string_lossy()));
    path_lbl.set_hexpand(true);
    path_lbl.set_xalign(0.0);
    path_lbl.set_ellipsize(gtk4::pango::EllipsizeMode::Start);
    path_lbl.add_css_class("title-4");

    let summary_lbl = gtk4::Label::new(Some("Scanning…"));
    summary_lbl.add_css_class("alis-subtext");

    let open_here_btn = gtk4::Button::with_label("Open Folder");
    open_here_btn.add_css_class("alis-flat-btn");

    top.append(&up_btn);
    top.append(&path_lbl);
    top.append(&summary_lbl);
    top.append(&open_here_btn);
    root.append(&top);

    let scroll = gtk4::ScrolledWindow::new();
    scroll.set_vexpand(true);
    let list = gtk4::ListBox::new();
    list.add_css_class("alis-file-list");
    list.set_selection_mode(gtk4::SelectionMode::None);
    scroll.set_child(Some(&list));
    root.append(&scroll);

    let current_dir = Rc::new(RefCell::new(start_dir.clone()));
    let active_cancel: Rc<RefCell<Arc<AtomicBool>>> =
        Rc::new(RefCell::new(Arc::new(AtomicBool::new(false))));

    type ScanDirFn = Rc<dyn Fn(PathBuf)>;
    let scan_fn: Rc<RefCell<Option<ScanDirFn>>> = Rc::new(RefCell::new(None));
    let scan_impl = {
        let cur_dir = current_dir.clone();
        let active_c = active_cancel.clone();
        let p_lbl = path_lbl.clone();
        let s_lbl = summary_lbl.clone();
        let lb = list.clone();
        let scan_ref = scan_fn.clone();
        let open_cb = on_open_in_files.clone();
        Rc::new(move |dir: PathBuf| {
            active_c.borrow().store(true, Ordering::Relaxed);
            let cancel = Arc::new(AtomicBool::new(false));
            *active_c.borrow_mut() = cancel.clone();
            *cur_dir.borrow_mut() = dir.clone();
            p_lbl.set_text(&dir.to_string_lossy());
            s_lbl.set_text("Scanning…");
            while let Some(c) = lb.first_child() {
                lb.remove(&c);
            }

            let dir_bg = dir.clone();
            let cancel_bg = cancel.clone();
            let (tx, rx) = std::sync::mpsc::channel();
            std::thread::spawn(move || {
                let report = crate::disk_usage::analyze_directory(&dir_bg, &cancel_bg);
                let _ = tx.send(report);
            });

            let lb_ui = lb.clone();
            let s_ui = s_lbl.clone();
            let scan_ref_ui = scan_ref.clone();
            let open_cb_ui = open_cb.clone();
            let cancel_check = cancel.clone();
            glib::timeout_add_local(std::time::Duration::from_millis(50), move || {
                if cancel_check.load(Ordering::Relaxed) {
                    return glib::ControlFlow::Break;
                }
                match rx.try_recv() {
                    Ok(report) => {
                        s_ui.set_text(&format!(
                            "{}  •  {} items",
                            format_size(report.total_bytes),
                            report.total_items
                        ));
                        let total = report.total_bytes.max(1) as f64;
                        for item in report.children.into_iter().take(200) {
                            let frac = (item.bytes as f64 / total).clamp(0.0, 1.0);
                            let pct = frac * 100.0;
                            let row = gtk4::Box::new(gtk4::Orientation::Vertical, 4);
                            row.set_margin_top(4);
                            row.set_margin_bottom(4);

                            let top_row = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
                            let icon = gtk4::Image::from_icon_name(if item.is_dir {
                                "folder"
                            } else {
                                "text-x-generic"
                            });
                            icon.set_pixel_size(18);
                            let name_btn = gtk4::Button::with_label(&item.name);
                            name_btn.set_has_frame(false);
                            name_btn.set_hexpand(true);
                            name_btn.set_halign(gtk4::Align::Start);
                            let item_path = item.path.clone();
                            let is_dir = item.is_dir;
                            let scan_r = scan_ref_ui.clone();
                            let open_r = open_cb_ui.clone();
                            name_btn.connect_clicked(move |_| {
                                if is_dir {
                                    if let Some(ref f) = *scan_r.borrow() {
                                        f(item_path.clone());
                                    }
                                } else if let Some(parent) = item_path.parent() {
                                    open_r(parent.to_path_buf());
                                }
                            });

                            let size_l = gtk4::Label::new(Some(&format!(
                                "{} ({:.1}%)",
                                format_size(item.bytes),
                                pct
                            )));
                            size_l.add_css_class("alis-subtext");

                            top_row.append(&icon);
                            top_row.append(&name_btn);
                            top_row.append(&size_l);

                            let bar = gtk4::ProgressBar::new();
                            bar.add_css_class("alis-disk-bar");
                            bar.set_fraction(frac);

                            row.append(&top_row);
                            row.append(&bar);
                            lb_ui.append(&row);
                        }
                        glib::ControlFlow::Break
                    }
                    Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
                    Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                }
            });
        })
    };
    *scan_fn.borrow_mut() = Some(scan_impl.clone());

    {
        let cur = current_dir.clone();
        let sc = scan_impl.clone();
        up_btn.connect_clicked(move |_| {
            let parent = cur.borrow().parent().map(Path::to_path_buf);
            if let Some(p) = parent {
                sc(p);
            }
        });
    }
    {
        let cur = current_dir.clone();
        let open_cb = on_open_in_files.clone();
        let w = win.clone();
        open_here_btn.connect_clicked(move |_| {
            open_cb(cur.borrow().clone());
            w.close();
        });
    }
    {
        let active_c = active_cancel.clone();
        win.connect_close_request(move |_| {
            active_c.borrow().store(true, Ordering::Relaxed);
            glib::Propagation::Proceed
        });
    }

    attach_escape_close(&win);
    scan_impl(start_dir);
    win.set_child(Some(&root));
    win.present();
}

#[derive(Clone)]
pub struct PaletteEntry {
    pub title: String,
    pub subtitle: String,
    pub icon: String,
    pub action: Rc<dyn Fn()>,
}

/// Command & Jump Palette (`Ctrl+K`) with fuzzy instant filtering over commands, bookmarks, and recent folders.
pub fn open_command_palette(parent: &gtk4::ApplicationWindow, entries: Vec<PaletteEntry>) {
    let win = gtk4::Window::builder()
        .title("Command Palette")
        .transient_for(parent)
        .modal(true)
        .default_width(540)
        .default_height(420)
        .build();
    win.add_css_class("alis-files-window");
    win.add_css_class("alis-dialog-surface");

    let vbox = gtk4::Box::new(gtk4::Orientation::Vertical, 8);
    vbox.set_margin_top(12);
    vbox.set_margin_bottom(12);
    vbox.set_margin_start(14);
    vbox.set_margin_end(14);

    let search = gtk4::SearchEntry::new();
    search.set_placeholder_text(Some("Jump to folder or run command…"));
    search.add_css_class("alis-path-entry");
    vbox.append(&search);

    let scroll = gtk4::ScrolledWindow::new();
    scroll.set_vexpand(true);
    let list = gtk4::ListBox::new();
    list.add_css_class("alis-file-list");
    list.set_selection_mode(gtk4::SelectionMode::Single);
    scroll.set_child(Some(&list));
    vbox.append(&scroll);

    let all_entries = Rc::new(entries);
    let filtered = Rc::new(RefCell::new(Vec::<PaletteEntry>::new()));

    let repopulate = {
        let all = all_entries.clone();
        let filt = filtered.clone();
        let lb = list.clone();
        Rc::new(move |query: &str| {
            let q = query.trim().to_lowercase();
            while let Some(c) = lb.first_child() {
                lb.remove(&c);
            }
            let mut next = Vec::new();
            for e in all.iter() {
                if q.is_empty()
                    || e.title.to_lowercase().contains(&q)
                    || e.subtitle.to_lowercase().contains(&q)
                {
                    let hbox = gtk4::Box::new(gtk4::Orientation::Horizontal, 10);
                    let img = gtk4::Image::from_icon_name(&e.icon);
                    img.set_pixel_size(18);
                    let col = gtk4::Box::new(gtk4::Orientation::Vertical, 1);
                    col.set_hexpand(true);
                    let t = gtk4::Label::new(Some(&e.title));
                    t.set_xalign(0.0);
                    let s = gtk4::Label::new(Some(&e.subtitle));
                    s.set_xalign(0.0);
                    s.add_css_class("alis-subtext");
                    s.set_ellipsize(gtk4::pango::EllipsizeMode::Middle);
                    col.append(&t);
                    col.append(&s);
                    hbox.append(&img);
                    hbox.append(&col);
                    lb.append(&hbox);
                    next.push(e.clone());
                }
            }
            if let Some(first) = lb.row_at_index(0) {
                lb.select_row(Some(&first));
            }
            *filt.borrow_mut() = next;
        })
    };

    repopulate("");

    {
        let rp = repopulate.clone();
        search.connect_search_changed(move |se| rp(&se.text()));
    }

    let activate_selected = {
        let lb = list.clone();
        let filt = filtered.clone();
        let w = win.clone();
        Rc::new(move || {
            let idx = lb
                .selected_row()
                .map(|r| r.index() as usize)
                .unwrap_or(0);
            let maybe_action = filt.borrow().get(idx).map(|e| e.action.clone());
            w.close();
            if let Some(act) = maybe_action {
                act();
            }
        })
    };

    {
        let act = activate_selected.clone();
        search.connect_activate(move |_| act());
    }
    {
        let filt = filtered.clone();
        let w = win.clone();
        list.connect_row_activated(move |_, row| {
            let idx = row.index() as usize;
            let maybe_action = filt.borrow().get(idx).map(|e| e.action.clone());
            w.close();
            if let Some(act) = maybe_action {
                act();
            }
        });
    }

    let key_ctrl = gtk4::EventControllerKey::new();
    key_ctrl.set_propagation_phase(gtk4::PropagationPhase::Capture);
    {
        let w = win.clone();
        let lb = list.clone();
        let act = activate_selected.clone();
        key_ctrl.connect_key_pressed(move |_, key, _, _| match key {
            gdk::Key::Escape => {
                w.close();
                glib::Propagation::Stop
            }
            gdk::Key::Down => {
                let next = lb.selected_row().map(|r| r.index() + 1).unwrap_or(0);
                if let Some(row) = lb.row_at_index(next) {
                    lb.select_row(Some(&row));
                }
                glib::Propagation::Stop
            }
            gdk::Key::Up => {
                let prev = lb.selected_row().map(|r| (r.index() - 1).max(0)).unwrap_or(0);
                if let Some(row) = lb.row_at_index(prev) {
                    lb.select_row(Some(&row));
                }
                glib::Propagation::Stop
            }
            gdk::Key::Return | gdk::Key::KP_Enter => {
                act();
                glib::Propagation::Stop
            }
            _ => glib::Propagation::Proceed,
        });
    }
    win.add_controller(key_ctrl);

    win.set_child(Some(&vbox));
    win.present();
    search.grab_focus();
}
