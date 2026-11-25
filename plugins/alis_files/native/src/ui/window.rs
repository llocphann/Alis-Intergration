use crate::archive::ArchiveFormat;
use crate::config::{
    AppConfig, SessionState, SessionTab, SortField, SortOrder, ViewMode, config_path, home_dir,
    xdg_config_home,
};
use crate::fs_ops::{
    UndoAction, create_entry_yazi, create_file, create_folder, empty_trash,
    remove_permanent_batch, rename_single, restore_from_trash, transfer_batch, trash_batch,
    unique_destination,
};
use crate::model::{FileEntry, format_size, is_trash_dir, trash_files_dir};
use crate::ui::dialogs::{
    PaletteEntry, open_bulk_rename_dialog, open_command_palette, open_compress_dialog,
    open_confirm_dialog, open_disk_analyzer_dialog, open_name_prompt,
    open_name_prompt_with_selection,
};
use crate::ui::inspector::InspectorPanel;
use crate::ui::keys::{GotoTarget, KeyCommand, attach_window_keys};
use crate::ui::pane::{BrowserPane, PaneCallbacks, TabState};
use crate::ui::quicklook::open_quicklook_items;
use crate::ui::sidebar::SidebarPanel;
use crate::ui::{
    ClipboardOp, SharedStateRc, read_clipboard_files, set_system_clipboard_files,
    set_system_clipboard_text,
};
use gtk4::gdk;
use gtk4::gio;
use gtk4::glib;
use gtk4::prelude::*;
use std::cell::{Cell, RefCell};
use std::path::{Path, PathBuf};
use std::rc::Rc;

const GRID_ZOOM_SIZES: [i32; 7] = [40, 56, 72, 96, 128, 176, 240];

#[derive(Debug, Clone)]
struct WindowTab {
    left: TabState,
    right: Option<TabState>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum FocusRegion {
    Rail,
    Primary,
    Secondary,
    Preview,
    Properties,
}

fn validate_session_dir(raw: &str) -> PathBuf {
    let p = PathBuf::from(raw);
    if is_trash_dir(&p) || p.is_dir() {
        p
    } else {
        p.ancestors()
            .find(|a| a.is_dir())
            .map(Path::to_path_buf)
            .unwrap_or_else(home_dir)
    }
}

fn closest_grid_zoom_step(px: i32) -> f64 {
    GRID_ZOOM_SIZES
        .iter()
        .enumerate()
        .min_by_key(|(_, s)| (**s - px).abs())
        .map(|(i, _)| i as f64)
        .unwrap_or(2.0)
}

#[derive(Clone)]
pub struct AlisFilesWindow {
    pub window: gtk4::ApplicationWindow,
    state: SharedStateRc,
    sidebar: SidebarPanel,
    rail_handle: gtk4::Box,
    rail_open: Rc<Cell<bool>>,
    rail_toggle_btn: gtk4::Button,
    canvas_card: gtk4::Box,
    tab_strip: gtk4::Box,
    window_tabs: Rc<RefCell<Vec<WindowTab>>>,
    active_tab_idx: Rc<Cell<usize>>,
    primary_pane: BrowserPane,
    secondary_pane: BrowserPane,
    split_paned: gtk4::Paned,
    split_active: Rc<Cell<bool>>,
    split_btn_syncing: Rc<Cell<bool>>,
    active_is_secondary: Rc<Cell<bool>>,
    focused_region: Rc<Cell<FocusRegion>>,
    last_inspector_region: Rc<Cell<FocusRegion>>,
    inspector: InspectorPanel,
    inspector_handle: gtk4::Box,
    inspector_open: Rc<Cell<bool>>,
    back_btn: gtk4::Button,
    fwd_btn: gtk4::Button,
    up_btn: gtk4::Button,
    path_inset: gtk4::Box,
    path_stack: gtk4::Stack,
    breadcrumb_box: gtk4::Box,
    path_entry: gtk4::Entry,
    seg_grid_btn: gtk4::Button,
    seg_list_btn: gtk4::Button,
    seg_gallery_btn: gtk4::Button,
    sort_btn: gtk4::Button,
    split_btn: gtk4::ToggleButton,
    more_btn: gtk4::Button,
    inspector_btn: gtk4::ToggleButton,
    status_left: gtk4::Label,
    status_branch: gtk4::Label,
    status_vim: gtk4::Label,
    disk_meter: gtk4::ProgressBar,
    status_right: gtk4::Label,
    zoom_scale: gtk4::Scale,
    zoom_updating: Rc<Cell<bool>>,
    toast_box: gtk4::Box,
    toast_label: gtk4::Label,
    toast_undo_btn: gtk4::Button,
    toast_gen: Rc<Cell<u64>>,
    session_save_scheduled: Rc<Cell<bool>>,
    _cfg_monitor: Rc<RefCell<Option<gio::FileMonitor>>>,
}

impl AlisFilesWindow {
    pub fn new(
        app: &gtk4::Application,
        start_dir: PathBuf,
        state: SharedStateRc,
        restore_session: bool,
    ) -> Self {
        let (init_w, init_h, init_split, init_insp, init_rail, init_view, init_rail_w, init_insp_w, init_insp_ratio) = {
            let st = state.borrow();
            (
                st.config.window_width,
                st.config.window_height,
                st.config.split_view_default,
                st.config.inspector_open_default,
                st.config.rail_open,
                st.config.view_mode,
                st.config.rail_width.clamp(156, 460),
                st.config.inspector_width.clamp(200, 560),
                st.config.inspector_preview_ratio_milli.clamp(220, 720),
            )
        };

        let window = gtk4::ApplicationWindow::builder()
            .application(app)
            .title("Files")
            .default_width(init_w.clamp(680, 2400))
            .default_height(init_h.clamp(440, 1600))
            .build();
        // Frameless 3-column layout matching inir-files Browser.qml (empty Head space moves window)
        window.set_decorated(false);
        window.add_css_class("alis-files-window");

        // Outer 3-column container on Rail backdrop: [Left Rail | Rounded Canvas Card | Right Aside]
        let outer = gtk4::Box::new(gtk4::Orientation::Horizontal, 0);
        outer.set_hexpand(true);
        outer.set_vexpand(true);

        let win_cell: Rc<RefCell<Option<AlisFilesWindow>>> = Rc::new(RefCell::new(None));

        // ── 1. Left Rail ─────────────────────────────────────────────────
        let sidebar = {
            let wc1 = win_cell.clone();
            let wc2 = win_cell.clone();
            let wc3 = win_cell.clone();
            SidebarPanel::new(
                Rc::new(move |p| {
                    if let Some(ref w) = *wc1.borrow() {
                        w.active_pane().navigate_to(p);
                    }
                }),
                Rc::new(move |path_str| {
                    if let Some(ref w) = *wc2.borrow() {
                        w.remove_bookmark(&path_str);
                    }
                }),
                Rc::new(move |res| {
                    if let Some(ref w) = *wc3.borrow() {
                        match res {
                            Ok(msg) => w.show_toast(&msg, false),
                            Err(err) => w.show_toast(&err, false),
                        }
                    }
                }),
            )
        };
        sidebar.root.set_width_request(init_rail_w);
        sidebar.root.set_visible(init_rail);

        // ── 2. Center Rounded Canvas Card ────────────────────────────────
        let canvas_card = gtk4::Box::new(gtk4::Orientation::Vertical, 0);
        canvas_card.add_css_class("alis-canvas-card");
        canvas_card.set_overflow(gtk4::Overflow::Hidden);
        canvas_card.set_hexpand(true);
        canvas_card.set_vexpand(true);
        canvas_card.set_margin_top(8);
        canvas_card.set_margin_bottom(8);
        canvas_card.set_margin_start(if init_rail { 0 } else { 8 });
        canvas_card.set_margin_end(if init_insp { 0 } else { 8 });

        // Unified TabStrip at top of Canvas (auto-hidden when <= 1 tab)
        let tab_strip = gtk4::Box::new(gtk4::Orientation::Horizontal, 4);
        tab_strip.add_css_class("alis-tabstrip");
        tab_strip.set_visible(false);
        canvas_card.append(&tab_strip);

        // Head bar inside WindowHandle (empty space drags window, double-click toggles maximize)
        let win_handle = gtk4::WindowHandle::new();
        let head = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
        head.add_css_class("alis-head");

        let nav_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 2);
        let rail_toggle_btn = act_icon_btn("sidebar-show-symbolic", "Show Places (F9)");
        rail_toggle_btn.set_visible(!init_rail);
        let back_btn = act_icon_btn("go-previous-symbolic", "Back (Alt+Left)");
        let fwd_btn = act_icon_btn("go-next-symbolic", "Forward (Alt+Right)");
        let up_btn = act_icon_btn("go-up-symbolic", "Enclosing folder (Alt+Up)");
        nav_box.append(&rail_toggle_btn);
        nav_box.append(&back_btn);
        nav_box.append(&fwd_btn);
        nav_box.append(&up_btn);
        head.append(&nav_box);

        // Inset Breadcrumb / Editable PathBar
        let path_inset = gtk4::Box::new(gtk4::Orientation::Horizontal, 2);
        path_inset.add_css_class("alis-inset");
        path_inset.set_hexpand(true);
        path_inset.set_valign(gtk4::Align::Center);

        let path_stack = gtk4::Stack::new();
        path_stack.set_hexpand(true);

        let crumb_row = gtk4::Box::new(gtk4::Orientation::Horizontal, 2);
        let breadcrumb_scroll = gtk4::ScrolledWindow::new();
        breadcrumb_scroll.set_hexpand(true);
        breadcrumb_scroll.set_vscrollbar_policy(gtk4::PolicyType::Never);
        breadcrumb_scroll.set_hscrollbar_policy(gtk4::PolicyType::Automatic);
        let crumb_inner = gtk4::Box::new(gtk4::Orientation::Horizontal, 2);
        let breadcrumb_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 2);
        let crumb_spacer = gtk4::Box::new(gtk4::Orientation::Horizontal, 0);
        crumb_spacer.set_hexpand(true);
        crumb_spacer.set_size_request(28, -1);
        crumb_inner.append(&breadcrumb_box);
        crumb_inner.append(&crumb_spacer);
        breadcrumb_scroll.set_child(Some(&crumb_inner));

        let edit_path_btn = act_icon_btn("document-edit-symbolic", "Edit location (Ctrl+L)");
        crumb_row.append(&breadcrumb_scroll);
        crumb_row.append(&edit_path_btn);

        let path_entry = gtk4::Entry::new();
        path_entry.add_css_class("alis-path-entry");
        path_entry.set_hexpand(true);

        path_stack.add_named(&crumb_row, Some("crumbs"));
        path_stack.add_named(&path_entry, Some("entry"));
        path_stack.set_visible_child_name("crumbs");
        path_inset.append(&path_stack);
        head.append(&path_inset);

        // Right tool controls matching Head.qml: Search | Segments(Grid/List/Gallery) | Sort | Split | More | Preview | Close
        let tools_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 4);
        tools_box.set_valign(gtk4::Align::Center);

        let search_btn = act_icon_btn("system-search-symbolic", "Search / Filter (Ctrl+F or /)");

        let seg_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 2);
        seg_box.add_css_class("alis-segments");
        seg_box.set_valign(gtk4::Align::Center);
        let seg_grid_btn = seg_icon_btn("view-grid-symbolic", "Grid (Ctrl+1)");
        let seg_list_btn = seg_icon_btn("view-list-symbolic", "List (Ctrl+2)");
        let seg_gallery_btn = seg_icon_btn("folder-pictures-symbolic", "Gallery (Ctrl+3)");
        seg_box.append(&seg_grid_btn);
        seg_box.append(&seg_list_btn);
        seg_box.append(&seg_gallery_btn);

        let sort_btn = act_icon_btn("view-sort-ascending-symbolic", "Sort");

        let split_btn = gtk4::ToggleButton::new();
        split_btn.set_icon_name("view-dual-symbolic");
        split_btn.add_css_class("alis-act-btn");
        split_btn.set_focus_on_click(false);
        split_btn.set_tooltip_text(Some("Split View (F3)"));
        split_btn.set_active(init_split);
        if init_split {
            split_btn.add_css_class("toggled");
        }

        let more_btn = act_icon_btn("view-more-symbolic", "More actions");

        let inspector_btn = gtk4::ToggleButton::new();
        inspector_btn.set_icon_name("sidebar-show-right-symbolic");
        inspector_btn.add_css_class("alis-act-btn");
        inspector_btn.set_focus_on_click(false);
        inspector_btn.set_tooltip_text(Some("Preview (Ctrl+I / Alt+I)"));
        inspector_btn.set_active(init_insp);
        if init_insp {
            inspector_btn.add_css_class("toggled");
        }

        tools_box.append(&search_btn);
        tools_box.append(&seg_box);
        tools_box.append(&sort_btn);
        tools_box.append(&split_btn);
        tools_box.append(&more_btn);
        tools_box.append(&inspector_btn);
        head.append(&tools_box);

        win_handle.set_child(Some(&head));
        canvas_card.append(&win_handle);

        // Panes + Toast overlay
        let make_pane_callbacks = |is_secondary: bool| -> PaneCallbacks {
            let wc_f = win_cell.clone();
            let wc_s = win_cell.clone();
            let wc_sel = win_cell.clone();
            let wc_ctx = win_cell.clone();
            let wc_drop = win_cell.clone();
            let wc_open = win_cell.clone();
            PaneCallbacks {
                on_focus: Rc::new(move || {
                    if let Some(ref w) = *wc_f.borrow() {
                        let region = if is_secondary && w.split_active.get() {
                            FocusRegion::Secondary
                        } else {
                            FocusRegion::Primary
                        };
                        w.set_focused_region(region, false);
                    }
                }),
                on_state_changed: Rc::new(move || {
                    if let Some(ref w) = *wc_s.borrow() {
                        w.sync_chrome();
                    }
                }),
                on_selection_changed: Rc::new(move |entries| {
                    if let Some(ref w) = *wc_sel.borrow() {
                        w.on_selection_changed(entries);
                    }
                }),
                on_context_menu: Rc::new(move |anchor, x, y, entries, cur_dir| {
                    if let Some(ref w) = *wc_ctx.borrow() {
                        w.show_context_menu(&anchor, x, y, entries, cur_dir);
                    }
                }),
                on_drop_files: Rc::new(move |paths, dest, action| {
                    if let Some(ref w) = *wc_drop.borrow() {
                        w.handle_drop(paths, dest, action);
                    }
                }),
                on_open_file: Rc::new(move |entry| {
                    if let Some(ref w) = *wc_open.borrow() {
                        w.open_file_entry(&entry);
                    }
                }),
            }
        };

        let primary_pane = BrowserPane::new(
            start_dir.clone(),
            state.clone(),
            make_pane_callbacks(false),
        );
        let secondary_pane = BrowserPane::new(
            start_dir.clone(),
            state.clone(),
            make_pane_callbacks(true),
        );
        primary_pane.set_active(true);

        let split_paned = gtk4::Paned::new(gtk4::Orientation::Horizontal);
        split_paned.set_hexpand(true);
        split_paned.set_vexpand(true);
        split_paned.set_wide_handle(true);
        split_paned.set_start_child(Some(&primary_pane.root));
        split_paned.set_end_child(Some(&secondary_pane.root));
        secondary_pane.root.set_visible(init_split);
        canvas_card.append(&split_paned);

        // Status bar inside Canvas bottom (`Status.qml`, 36px height; transient status inline in status_left slot)
        let statusbar = gtk4::Box::new(gtk4::Orientation::Horizontal, 10);
        statusbar.add_css_class("alis-statusbar");
        let status_left = gtk4::Label::new(Some("0 items"));
        status_left.set_xalign(0.0);
        status_left.set_hexpand(true);
        status_left.set_ellipsize(gtk4::pango::EllipsizeMode::Middle);

        let toast_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
        toast_box.set_hexpand(true);
        toast_box.set_visible(false);
        let toast_label = gtk4::Label::new(Some(""));
        toast_label.set_xalign(0.0);
        toast_label.set_hexpand(true);
        toast_label.set_width_chars(1);
        toast_label.set_ellipsize(gtk4::pango::EllipsizeMode::End);
        toast_label.add_css_class("alis-status-toast-label");
        let toast_undo_btn = gtk4::Button::with_label("Undo");
        toast_undo_btn.add_css_class("alis-status-undo-btn");
        toast_undo_btn.set_focus_on_click(false);
        toast_undo_btn.set_visible(false);
        toast_box.append(&toast_label);
        toast_box.append(&toast_undo_btn);

        let status_branch = gtk4::Label::new(Some(""));
        status_branch.add_css_class("alis-muted");
        status_branch.set_visible(false);

        let status_vim = gtk4::Label::new(Some("VIM"));
        status_vim.add_css_class("alis-vim-pill");
        status_vim.set_visible(state.borrow().config.vim_keybindings);

        let disk_meter = gtk4::ProgressBar::new();
        disk_meter.add_css_class("alis-drive-bar");
        disk_meter.set_width_request(44);
        disk_meter.set_valign(gtk4::Align::Center);

        let status_right = gtk4::Label::new(Some(""));
        status_right.set_xalign(1.0);

        let zoom_scale = gtk4::Scale::with_range(gtk4::Orientation::Horizontal, 0.0, 6.0, 1.0);
        zoom_scale.add_css_class("alis-zoom-scale");
        zoom_scale.set_width_request(96);
        zoom_scale.set_draw_value(false);
        zoom_scale.set_focusable(false);
        zoom_scale.set_tooltip_text(Some("Zoom size"));

        statusbar.append(&status_left);
        statusbar.append(&toast_box);
        statusbar.append(&status_branch);
        statusbar.append(&status_vim);
        statusbar.append(&disk_meter);
        statusbar.append(&status_right);
        statusbar.append(&zoom_scale);
        canvas_card.append(&statusbar);

        // ── 3. Right Preview & Live Properties Aside ─────────────────────
        let inspector = {
            let wc_o = win_cell.clone();
            let wc_q = win_cell.clone();
            let wc_perm = win_cell.clone();
            let wc_t = win_cell.clone();
            let st_ratio = state.clone();
            InspectorPanel::new(
                Rc::new(move |p| {
                    if let Some(ref w) = *wc_o.borrow()
                        && let Ok(fe) = FileEntry::from_path(p)
                    {
                        if fe.is_dir {
                            w.active_pane().navigate_to(fe.path);
                        } else {
                            w.open_file_entry(&fe);
                        }
                    }
                }),
                Rc::new(move |p| {
                    if let Some(ref w) = *wc_q.borrow() {
                        w.open_quicklook_for(&p);
                    }
                }),
                Rc::new(move |_| {
                    if let Some(ref w) = *wc_perm.borrow() {
                        w.reload_all_panes();
                    }
                }),
                Rc::new(move |msg| {
                    if let Some(ref w) = *wc_t.borrow() {
                        w.show_toast(&msg, false);
                    }
                }),
                Rc::new(move |ratio| {
                    let mut st = st_ratio.borrow_mut();
                    let clamped = ratio.clamp(220, 720);
                    if st.config.inspector_preview_ratio_milli != clamped {
                        st.config.inspector_preview_ratio_milli = clamped;
                        let _ = st.config.save();
                    }
                }),
                init_insp_ratio,
            )
        };
        inspector.root.set_width_request(init_insp_w);
        inspector.root.set_visible(init_insp);

        let rail_handle = make_resize_handle("Drag to resize sidebar (double-click to reset)");
        rail_handle.set_visible(init_rail);
        let inspector_handle = make_resize_handle("Drag to resize preview inspector (double-click to reset)");
        inspector_handle.set_visible(init_insp);

        outer.append(&sidebar.root);
        outer.append(&rail_handle);
        outer.append(&canvas_card);
        outer.append(&inspector_handle);
        outer.append(&inspector.root);
        window.set_child(Some(&outer));

        // Attach zero-jitter drag & double-click reset gestures on Rail and Inspector edges
        attach_pane_resize(
            &rail_handle,
            &outer,
            &sidebar.root,
            &inspector.root,
            156,
            460,
            228,
            true,
            state.clone(),
        );
        attach_pane_resize(
            &inspector_handle,
            &outer,
            &inspector.root,
            &sidebar.root,
            200,
            560,
            296,
            false,
            state.clone(),
        );

        let this = Self {
            window: window.clone(),
            state: state.clone(),
            sidebar,
            rail_handle,
            rail_open: Rc::new(Cell::new(init_rail)),
            rail_toggle_btn,
            canvas_card,
            tab_strip,
            window_tabs: Rc::new(RefCell::new(vec![WindowTab {
                left: TabState::new(start_dir),
                right: None,
            }])),
            active_tab_idx: Rc::new(Cell::new(0)),
            primary_pane,
            secondary_pane,
            split_paned,
            split_active: Rc::new(Cell::new(init_split)),
            split_btn_syncing: Rc::new(Cell::new(false)),
            active_is_secondary: Rc::new(Cell::new(false)),
            focused_region: Rc::new(Cell::new(FocusRegion::Primary)),
            last_inspector_region: Rc::new(Cell::new(FocusRegion::Preview)),
            inspector,
            inspector_handle,
            inspector_open: Rc::new(Cell::new(init_insp)),
            back_btn,
            fwd_btn,
            up_btn,
            path_inset,
            path_stack,
            breadcrumb_box,
            path_entry,
            seg_grid_btn,
            seg_list_btn,
            seg_gallery_btn,
            sort_btn,
            split_btn,
            more_btn,
            inspector_btn,
            status_left,
            status_branch,
            status_vim,
            disk_meter,
            status_right,
            zoom_scale,
            zoom_updating: Rc::new(Cell::new(false)),
            toast_box,
            toast_label,
            toast_undo_btn,
            toast_gen: Rc::new(Cell::new(0)),
            session_save_scheduled: Rc::new(Cell::new(false)),
            _cfg_monitor: Rc::new(RefCell::new(None)),
        };

        *win_cell.borrow_mut() = Some(this.clone());
        this.apply_segment_highlight(init_view);
        this.sync_zoom_slider();

        // Click on empty area at right of breadcrumb enters inline edit mode (`PathBar.qml`)
        {
            let w = this.clone();
            let click_spacer = gtk4::GestureClick::new();
            click_spacer.set_button(gdk::BUTTON_PRIMARY);
            click_spacer.connect_pressed(move |_, _, _, _| {
                w.enter_path_edit();
            });
            crumb_spacer.add_controller(click_spacer);
        }

        // Wire Head controls
        {
            let w = this.clone();
            this.rail_toggle_btn.connect_clicked(move |_| w.toggle_rail());
        }
        {
            let w = this.clone();
            this.back_btn.connect_clicked(move |_| w.active_pane().go_back());
        }
        {
            let w = this.clone();
            this.fwd_btn.connect_clicked(move |_| w.active_pane().go_forward());
        }
        {
            let w = this.clone();
            this.up_btn.connect_clicked(move |_| w.active_pane().go_parent());
        }
        {
            let w = this.clone();
            edit_path_btn.connect_clicked(move |_| w.enter_path_edit());
        }
        {
            let w = this.clone();
            this.path_entry.connect_activate(move |e| {
                let raw = e.text().to_string();
                let trimmed = raw.trim();
                let expanded = if let Some(rest) = trimmed.strip_prefix("~/") {
                    home_dir().join(rest)
                } else if trimmed == "~" {
                    home_dir()
                } else {
                    PathBuf::from(trimmed)
                };
                w.exit_path_edit();
                if expanded.is_dir() {
                    w.active_pane().navigate_to(expanded);
                    w.active_pane().focus_view();
                } else if expanded.is_file() {
                    if let Some(parent) = expanded.parent() {
                        w.active_pane().navigate_to(parent.to_path_buf());
                        w.active_pane().select_path(&expanded);
                    }
                } else {
                    w.show_toast("Path does not exist", false);
                }
            });
        }
        {
            let w = this.clone();
            search_btn.connect_clicked(move |_| w.active_pane().show_filter());
        }
        {
            let w = this.clone();
            this.seg_grid_btn.connect_clicked(move |_| w.set_view_mode(ViewMode::Grid));
        }
        {
            let w = this.clone();
            this.seg_list_btn.connect_clicked(move |_| w.set_view_mode(ViewMode::List));
        }
        {
            let w = this.clone();
            this.seg_gallery_btn.connect_clicked(move |_| w.set_view_mode(ViewMode::Gallery));
        }
        {
            let w = this.clone();
            this.sort_btn.connect_clicked(move |_| w.open_sort_popover());
        }
        {
            let w = this.clone();
            this.split_btn.connect_toggled(move |tb| {
                if !w.split_btn_syncing.get() {
                    w.set_split_view(tb.is_active());
                }
            });
        }
        {
            let w = this.clone();
            this.more_btn.connect_clicked(move |_| w.open_more_popover());
        }
        {
            let w = this.clone();
            this.inspector_btn
                .connect_toggled(move |tb| w.set_inspector_open(tb.is_active()));
        }
        {
            let w = this.clone();
            this.toast_undo_btn.connect_clicked(move |_| w.perform_undo());
        }
        {
            let w = this.clone();
            this.zoom_scale.connect_value_changed(move |sc| {
                if w.zoom_updating.get() {
                    return;
                }
                let val = sc.value().round() as usize;
                let mode = w.state.borrow().config.view_mode;
                w.save_config_patch(|cfg| match mode {
                    ViewMode::List => {
                        cfg.list_zoom = val.min(2) as u8;
                    }
                    ViewMode::Grid | ViewMode::Gallery => {
                        cfg.grid_icon_size = GRID_ZOOM_SIZES[val.min(GRID_ZOOM_SIZES.len() - 1)];
                    }
                });
                w.primary_pane.render_entries();
                if w.split_active.get() {
                    w.secondary_pane.render_entries();
                }
            });
        }

        // Persist actual window dimensions and open tabs/session on close
        {
            let st = state.clone();
            let win = window.clone();
            let p_pane = this.primary_pane.clone();
            let s_pane = this.secondary_pane.clone();
            let w_tabs = this.window_tabs.clone();
            let act_idx = this.active_tab_idx.clone();
            let sp_active = this.split_active.clone();
            let sec_active = this.active_is_secondary.clone();
            let paned = this.split_paned.clone();
            window.connect_close_request(move |_| {
                let (w, h) = (win.width(), win.height());
                let sess = collect_window_session(
                    &p_pane,
                    &s_pane,
                    &w_tabs,
                    act_idx.get(),
                    sp_active.get(),
                    sec_active.get(),
                    &paned,
                );
                save_disk_config_patch(&st, |cfg| {
                    if w > 400 && h > 300 {
                        cfg.window_width = w;
                        cfg.window_height = h;
                    }
                    cfg.session = sess;
                });
                glib::Propagation::Proceed
            });
        }

        // Attach click focus tracking for Rail & Inspector cards
        {
            let w = this.clone();
            let rail_click = gtk4::GestureClick::new();
            rail_click.set_button(0);
            rail_click.set_propagation_phase(gtk4::PropagationPhase::Capture);
            rail_click.connect_pressed(move |_, _, _, _| {
                w.set_focused_region(FocusRegion::Rail, false);
            });
            this.sidebar.root.add_controller(rail_click);
        }
        {
            let w1 = this.clone();
            let w2 = this.clone();
            this.inspector.attach_focus_clicks(
                Rc::new(move || w1.set_focused_region(FocusRegion::Preview, false)),
                Rc::new(move || w2.set_focused_region(FocusRegion::Properties, false)),
            );
        }

        // Keyboard controller (Vim + standard desktop shortcuts)
        {
            let st_vim = state.clone();
            let st_grid = state.clone();
            let w = this.clone();
            let vim_lbl = this.status_vim.clone();
            attach_window_keys(
                &window,
                Rc::new(move || st_vim.borrow().config.vim_keybindings),
                Rc::new(move || {
                    matches!(
                        st_grid.borrow().config.view_mode,
                        ViewMode::Grid | ViewMode::Gallery
                    )
                }),
                move |cmd| w.handle_key_command(cmd),
                move |chord| {
                    if let Some(ch) = chord {
                        vim_lbl.set_text(&format!("{ch}…"));
                    } else {
                        vim_lbl.set_text("VIM");
                    }
                },
            );
        }

        this.watch_config_file();
        this.sidebar
            .rebuild_bookmarks(&this.state.borrow().config.bookmarks);

        if restore_session {
            let saved_sess = state.borrow().config.session.clone();
            if !saved_sess.tab_entries.is_empty() {
                let restored: Vec<WindowTab> = saved_sess
                    .tab_entries
                    .iter()
                    .take(32)
                    .map(|entry| WindowTab {
                        left: TabState::new(validate_session_dir(&entry.path)),
                        right: entry
                            .split_path
                            .as_deref()
                            .map(validate_session_dir)
                            .map(TabState::new),
                    })
                    .collect();
                if !restored.is_empty() {
                    let act = saved_sess.active_tab.min(restored.len() - 1);
                    *this.window_tabs.borrow_mut() = restored;
                    this.active_tab_idx.set(act);
                    this.apply_active_window_tab(saved_sess.active_is_secondary);
                    if this.split_active.get() {
                        let ratio = saved_sess.split_ratio_milli.clamp(200, 800);
                        let paned_ref = this.split_paned.clone();
                        glib::idle_add_local_once(move || {
                            let total_w = paned_ref.width();
                            if total_w > 300 {
                                paned_ref.set_position((total_w * i32::from(ratio)) / 1000);
                            }
                        });
                    }
                }
            } else if !saved_sess.tabs.is_empty() {
                let mut restored: Vec<WindowTab> = saved_sess
                    .tabs
                    .iter()
                    .take(32)
                    .map(|p| WindowTab {
                        left: TabState::new(validate_session_dir(p)),
                        right: None,
                    })
                    .collect();
                let act = saved_sess.active_tab.min(restored.len().saturating_sub(1));
                if saved_sess.split_open && !restored.is_empty() {
                    let sec_raw = saved_sess
                        .secondary_tabs
                        .get(saved_sess.secondary_active_tab)
                        .or_else(|| saved_sess.secondary_tabs.first())
                        .cloned()
                        .unwrap_or_else(|| restored[act].left.path.to_string_lossy().to_string());
                    restored[act].right = Some(TabState::new(validate_session_dir(&sec_raw)));
                }
                if !restored.is_empty() {
                    *this.window_tabs.borrow_mut() = restored;
                    this.active_tab_idx.set(act);
                    this.apply_active_window_tab(saved_sess.active_is_secondary);
                    if this.split_active.get() {
                        let ratio = saved_sess.split_ratio_milli.clamp(200, 800);
                        let paned_ref = this.split_paned.clone();
                        glib::idle_add_local_once(move || {
                            let total_w = paned_ref.width();
                            if total_w > 300 {
                                paned_ref.set_position((total_w * i32::from(ratio)) / 1000);
                            }
                        });
                    }
                }
            } else if init_split {
                this.toggle_split_view_for_active_tab(true);
            }
        } else if init_split {
            this.toggle_split_view_for_active_tab(true);
        }

        this.set_focused_region(
            if this.split_active.get() && this.active_is_secondary.get() {
                FocusRegion::Secondary
            } else {
                FocusRegion::Primary
            },
            false,
        );
        this.sync_chrome();
        this
    }

    pub fn active_pane(&self) -> BrowserPane {
        if self.split_active.get() && self.active_is_secondary.get() {
            self.secondary_pane.clone()
        } else {
            self.primary_pane.clone()
        }
    }

    fn set_active_pane(&self, secondary: bool) {
        let target_sec = secondary && self.split_active.get();
        self.active_is_secondary.set(target_sec);
        self.primary_pane.set_active(!target_sec);
        self.secondary_pane.set_active(target_sec);
        self.apply_focus_visuals();
        self.sync_chrome();
    }

    fn apply_focus_visuals(&self) {
        let reg = self.focused_region.get();
        self.sidebar.set_pane_focused(reg == FocusRegion::Rail);
        match reg {
            FocusRegion::Preview => self.inspector.set_focused_card(Some("preview")),
            FocusRegion::Properties => self.inspector.set_focused_card(Some("properties")),
            _ => self.inspector.set_focused_card(None),
        }
        if reg == FocusRegion::Primary || reg == FocusRegion::Secondary {
            self.canvas_card.add_css_class("pane-focused");
        } else {
            self.canvas_card.remove_css_class("pane-focused");
        }
        if reg == FocusRegion::Primary && self.split_active.get() {
            self.primary_pane.root.add_css_class("pane-split-focused");
        } else {
            self.primary_pane.root.remove_css_class("pane-split-focused");
        }
        if reg == FocusRegion::Secondary && self.split_active.get() {
            self.secondary_pane.root.add_css_class("pane-split-focused");
        } else {
            self.secondary_pane.root.remove_css_class("pane-split-focused");
        }
    }

    fn set_focused_region(&self, mut region: FocusRegion, grab_kbd_focus: bool) {
        if region == FocusRegion::Rail && !self.rail_open.get() {
            region = FocusRegion::Primary;
        }
        if region == FocusRegion::Secondary && !self.split_active.get() {
            region = FocusRegion::Primary;
        }
        if matches!(region, FocusRegion::Preview | FocusRegion::Properties)
            && !self.inspector_open.get()
        {
            region = if self.split_active.get() && self.active_is_secondary.get() {
                FocusRegion::Secondary
            } else {
                FocusRegion::Primary
            };
        }
        self.focused_region.set(region);
        if matches!(region, FocusRegion::Preview | FocusRegion::Properties) {
            self.last_inspector_region.set(region);
        }
        if region == FocusRegion::Primary {
            self.set_active_pane(false);
            if grab_kbd_focus {
                self.primary_pane.focus_view();
            }
            return;
        }
        if region == FocusRegion::Secondary {
            self.set_active_pane(true);
            if grab_kbd_focus {
                self.secondary_pane.focus_view();
            }
            return;
        }
        self.apply_focus_visuals();
    }

    fn move_pane_focus(&self, dir: KeyCommand) {
        let cur = self.focused_region.get();
        let next = match dir {
            KeyCommand::FocusPaneLeft => match cur {
                FocusRegion::Preview | FocusRegion::Properties => {
                    if self.split_active.get() {
                        FocusRegion::Secondary
                    } else {
                        FocusRegion::Primary
                    }
                }
                FocusRegion::Secondary => FocusRegion::Primary,
                FocusRegion::Primary if self.rail_open.get() => FocusRegion::Rail,
                other => other,
            },
            KeyCommand::FocusPaneRight => match cur {
                FocusRegion::Rail => FocusRegion::Primary,
                FocusRegion::Primary if self.split_active.get() => FocusRegion::Secondary,
                FocusRegion::Primary | FocusRegion::Secondary if self.inspector_open.get() => {
                    self.last_inspector_region.get()
                }
                other => other,
            },
            KeyCommand::FocusPaneDown => match cur {
                FocusRegion::Preview if self.inspector_open.get() => FocusRegion::Properties,
                other => other,
            },
            KeyCommand::FocusPaneUp => match cur {
                FocusRegion::Properties if self.inspector_open.get() => FocusRegion::Preview,
                other => other,
            },
            _ => cur,
        };
        if next != cur {
            self.set_focused_region(next, true);
        }
    }

    fn sync_active_window_tab_from_panes(&self) {
        let mut tabs = self.window_tabs.borrow_mut();
        if tabs.is_empty() {
            tabs.push(WindowTab {
                left: self.primary_pane.current_tab_state(),
                right: None,
            });
            self.active_tab_idx.set(0);
            return;
        }
        let idx = self.active_tab_idx.get().min(tabs.len() - 1);
        self.active_tab_idx.set(idx);
        tabs[idx].left = self.primary_pane.current_tab_state();
        if self.split_active.get() && tabs[idx].right.is_some() {
            tabs[idx].right = Some(self.secondary_pane.current_tab_state());
        }
    }

    fn apply_active_window_tab(&self, focus_secondary: bool) {
        let (left, right) = {
            let mut tabs = self.window_tabs.borrow_mut();
            if tabs.is_empty() {
                tabs.push(WindowTab {
                    left: TabState::new(home_dir()),
                    right: None,
                });
            }
            let idx = self.active_tab_idx.get().min(tabs.len() - 1);
            self.active_tab_idx.set(idx);
            (tabs[idx].left.clone(), tabs[idx].right.clone())
        };

        let is_split = right.is_some();
        let was_split = self.split_active.get();
        self.primary_pane.apply_tab_state(left, true);
        self.split_active.set(is_split);
        self.secondary_pane.root.set_visible(is_split);

        self.split_btn_syncing.set(true);
        self.split_btn.set_active(is_split);
        if is_split {
            self.split_btn.add_css_class("toggled");
        } else {
            self.split_btn.remove_css_class("toggled");
        }
        self.split_btn_syncing.set(false);

        if let Some(sec_tab) = right {
            self.secondary_pane.apply_tab_state(sec_tab, true);
            if !was_split {
                let w = self.window.width();
                if w > 400 {
                    self.split_paned.set_position((w - 240) / 2);
                }
            }
        }

        let target_sec = is_split && focus_secondary;
        self.set_focused_region(
            if target_sec {
                FocusRegion::Secondary
            } else {
                FocusRegion::Primary
            },
            false,
        );
        self.sync_chrome();
    }

    fn open_new_tab(&self, path: PathBuf) {
        self.sync_active_window_tab_from_panes();
        let next_idx = {
            let mut tabs = self.window_tabs.borrow_mut();
            tabs.push(WindowTab {
                left: TabState::new(path),
                right: None,
            });
            tabs.len() - 1
        };
        self.active_tab_idx.set(next_idx);
        self.apply_active_window_tab(false);
    }

    fn switch_to_window_tab(&self, idx: usize, focus_secondary: bool) {
        self.sync_active_window_tab_from_panes();
        let len = self.window_tabs.borrow().len();
        if idx >= len {
            return;
        }
        self.active_tab_idx.set(idx);
        self.apply_active_window_tab(focus_secondary);
    }

    fn next_window_tab(&self) {
        self.sync_active_window_tab_from_panes();
        let len = self.window_tabs.borrow().len();
        if len > 1 {
            let next = (self.active_tab_idx.get() + 1) % len;
            self.switch_to_window_tab(next, false);
        }
    }

    fn prev_window_tab(&self) {
        self.sync_active_window_tab_from_panes();
        let len = self.window_tabs.borrow().len();
        if len > 1 {
            let cur = self.active_tab_idx.get();
            let prev = if cur == 0 { len - 1 } else { cur - 1 };
            self.switch_to_window_tab(prev, false);
        }
    }

    fn close_window_tab_side(&self, idx: usize, close_right: Option<bool>) {
        self.sync_active_window_tab_from_panes();
        let mut focus_sec = false;
        let changed = {
            let mut tabs = self.window_tabs.borrow_mut();
            if idx >= tabs.len() {
                false
            } else if let Some(right_side) = close_right {
                if tabs[idx].right.is_none() {
                    false
                } else {
                    let right = tabs[idx].right.take().unwrap();
                    if !right_side {
                        tabs[idx].left = right;
                    }
                    true
                }
            } else if tabs.len() > 1 {
                tabs.remove(idx);
                let cur = self.active_tab_idx.get();
                let next = if idx < cur {
                    cur - 1
                } else {
                    cur.min(tabs.len() - 1)
                };
                self.active_tab_idx.set(next);
                focus_sec = false;
                true
            } else {
                false
            }
        };
        if changed {
            self.apply_active_window_tab(focus_sec);
        }
    }

    fn close_active_tab_or_half(&self) {
        self.sync_active_window_tab_from_panes();
        let idx = self.active_tab_idx.get();
        let is_split = self
            .window_tabs
            .borrow()
            .get(idx)
            .is_some_and(|t| t.right.is_some());
        if is_split {
            self.close_window_tab_side(idx, Some(self.active_is_secondary.get()));
        } else {
            self.close_window_tab_side(idx, None);
        }
    }

    fn toggle_split_view_for_active_tab(&self, enable: bool) {
        self.sync_active_window_tab_from_panes();
        let mut focus_sec = self.active_is_secondary.get();
        let changed = {
            let mut tabs = self.window_tabs.borrow_mut();
            if tabs.is_empty() {
                false
            } else {
                let idx = self.active_tab_idx.get().min(tabs.len() - 1);
                if enable {
                    if tabs[idx].right.is_some() {
                        false
                    } else if idx + 1 < tabs.len() && tabs[idx + 1].right.is_none() {
                        let neighbor = tabs.remove(idx + 1);
                        tabs[idx].right = Some(neighbor.left);
                        focus_sec = false;
                        true
                    } else if idx > 0 && tabs[idx - 1].right.is_none() {
                        let cur = tabs.remove(idx);
                        tabs[idx - 1].right = Some(cur.left);
                        self.active_tab_idx.set(idx - 1);
                        focus_sec = true;
                        true
                    } else {
                        let dup = TabState::new(tabs[idx].left.path.clone());
                        tabs[idx].right = Some(dup);
                        focus_sec = false;
                        true
                    }
                } else if let Some(right_tab) = tabs[idx].right.take() {
                    tabs.insert(
                        idx + 1,
                        WindowTab {
                            left: right_tab,
                            right: None,
                        },
                    );
                    if self.active_is_secondary.get() {
                        self.active_tab_idx.set(idx + 1);
                    }
                    focus_sec = false;
                    true
                } else {
                    false
                }
            }
        };
        if changed {
            self.apply_active_window_tab(focus_sec);
        }
    }

    pub fn open_folder(&self, dir: PathBuf) {
        self.active_pane().navigate_to(dir);
        self.window.present();
    }

    pub fn show_item(&self, item: PathBuf) {
        if let Some(parent) = item.parent().filter(|p| !p.as_os_str().is_empty()) {
            self.active_pane().navigate_to(parent.to_path_buf());
            self.active_pane().select_path(&item);
        } else if item.is_dir() {
            self.active_pane().navigate_to(item);
        }
        self.window.present();
    }

    pub fn show_item_properties(&self, item: PathBuf) {
        self.show_item(item);
        if !self.inspector_open.get() {
            self.set_inspector_open(true);
        }
        self.inspector.focus_properties_tab("general");
    }

    fn sync_chrome(&self) {
        self.sync_active_window_tab_from_panes();
        let pane = self.active_pane();
        let cur = pane.current_dir();
        self.back_btn.set_sensitive(pane.can_go_back());
        self.fwd_btn.set_sensitive(pane.can_go_forward());
        self.up_btn.set_sensitive(cur.parent().is_some());
        self.sidebar.set_active_path(&cur);
        self.rebuild_breadcrumbs(&cur);
        self.rebuild_tab_strip();

        let total = pane.visible_count();
        let sel = pane.selected_entries();
        if sel.is_empty() {
            self.status_left.set_text(&format!(
                "{total} {}",
                if total == 1 { "item" } else { "items" }
            ));
        } else if sel.len() == 1 {
            let e = &sel[0];
            let detail = if e.is_dir {
                "Folder".to_string()
            } else {
                format_size(e.size)
            };
            self.status_left.set_text(&format!("{} · {detail}", e.name));
        } else {
            let file_bytes: u64 = sel.iter().filter(|e| !e.is_dir).map(|e| e.size).sum();
            self.status_left.set_text(&format!(
                "{} of {} chosen · {}",
                sel.len(),
                total,
                format_size(file_bytes)
            ));
        }

        if let Some(branch) = pane.git_branch() {
            self.status_branch.set_text(&format!("git:{branch}"));
            self.status_branch.set_visible(true);
        } else {
            self.status_branch.set_visible(false);
        }

        self.status_vim
            .set_visible(self.state.borrow().config.vim_keybindings);

        let (fs_total, fs_used) = crate::mounts::filesystem_space(&cur);
        if fs_total > 0 {
            let free = fs_total.saturating_sub(fs_used);
            self.disk_meter
                .set_fraction((fs_used as f64 / fs_total as f64).clamp(0.0, 1.0));
            self.disk_meter.set_visible(true);
            self.status_right.set_text(&format!("{} free", format_size(free)));
        } else {
            self.disk_meter.set_visible(false);
            self.status_right.set_text("");
        }

        if self.inspector_open.get() && sel.is_empty() {
            self.inspector.inspect_folder(&cur, total);
        }
        self.schedule_session_save();
    }

    fn rebuild_tab_strip(&self) {
        while let Some(c) = self.tab_strip.first_child() {
            self.tab_strip.remove(&c);
        }
        let tabs = self.window_tabs.borrow().clone();
        let active_idx = self.active_tab_idx.get().min(tabs.len().saturating_sub(1));
        let active_split = tabs.get(active_idx).is_some_and(|t| t.right.is_some());
        if tabs.len() <= 1 && !active_split {
            self.tab_strip.set_visible(false);
            return;
        }
        self.tab_strip.set_visible(true);
        let active_sec = self.active_is_secondary.get();

        let scroll = gtk4::ScrolledWindow::new();
        scroll.set_hexpand(true);
        scroll.set_vscrollbar_policy(gtk4::PolicyType::Never);
        scroll.set_hscrollbar_policy(gtk4::PolicyType::Automatic);

        let strip_row = gtk4::Box::new(gtk4::Orientation::Horizontal, 6);
        for (i, tab) in tabs.iter().enumerate() {
            let is_cur = i == active_idx;
            if let Some(ref right_tab) = tab.right {
                // Grouped Split Tab Pill: [ Left Half ✕ | Right Half ✕ ]
                let group = gtk4::Box::new(gtk4::Orientation::Horizontal, 2);
                group.add_css_class("alis-split-tab-group");
                if is_cur {
                    group.add_css_class("tab-active");
                }

                let make_half = |t: &TabState, half_active: bool, close_right: bool| {
                    let holder = gtk4::Box::new(gtk4::Orientation::Horizontal, 2);
                    let btn = gtk4::Button::new();
                    btn.add_css_class("alis-split-tab-half");
                    btn.set_focus_on_click(false);
                    if half_active {
                        btn.add_css_class("half-active");
                    }
                    let tip = t.path.to_string_lossy().to_string();
                    btn.set_tooltip_text(Some(&tip));

                    let inner = gtk4::Box::new(gtk4::Orientation::Horizontal, 5);
                    let icon = gtk4::Image::from_icon_name("folder-symbolic");
                    icon.set_pixel_size(13);
                    let lbl = gtk4::Label::new(Some(&t.title()));
                    lbl.set_ellipsize(gtk4::pango::EllipsizeMode::End);
                    lbl.set_max_width_chars(16);
                    lbl.set_xalign(0.0);
                    inner.append(&icon);
                    inner.append(&lbl);
                    btn.set_child(Some(&inner));
                    {
                        let w = self.clone();
                        btn.connect_clicked(move |_| w.switch_to_window_tab(i, close_right));
                    }

                    let close = gtk4::Button::from_icon_name("window-close-symbolic");
                    close.add_css_class("alis-tab-close");
                    close.set_focus_on_click(false);
                    close.set_tooltip_text(Some("Close split side"));
                    {
                        let w = self.clone();
                        close.connect_clicked(move |_| w.close_window_tab_side(i, Some(close_right)));
                    }

                    holder.append(&btn);
                    holder.append(&close);
                    holder
                };

                let left_holder = make_half(&tab.left, is_cur && !active_sec, false);
                let sep = gtk4::Box::new(gtk4::Orientation::Vertical, 0);
                sep.add_css_class("alis-split-tab-sep");
                let right_holder = make_half(right_tab, is_cur && active_sec, true);

                group.append(&left_holder);
                group.append(&sep);
                group.append(&right_holder);
                strip_row.append(&group);
            } else {
                let holder = gtk4::Box::new(gtk4::Orientation::Horizontal, 2);
                let tab_btn = gtk4::Button::new();
                tab_btn.add_css_class("alis-tab-btn");
                tab_btn.set_focus_on_click(false);
                if is_cur {
                    tab_btn.add_css_class("tab-active");
                }
                let tip = tab.left.path.to_string_lossy().to_string();
                tab_btn.set_tooltip_text(Some(&tip));

                let inner = gtk4::Box::new(gtk4::Orientation::Horizontal, 6);
                let icon = gtk4::Image::from_icon_name("folder-symbolic");
                icon.set_pixel_size(14);
                let lbl = gtk4::Label::new(Some(&tab.left.title()));
                lbl.set_ellipsize(gtk4::pango::EllipsizeMode::End);
                lbl.set_max_width_chars(22);
                lbl.set_hexpand(true);
                lbl.set_xalign(0.0);
                inner.append(&icon);
                inner.append(&lbl);

                let close = gtk4::Button::from_icon_name("window-close-symbolic");
                close.add_css_class("alis-tab-close");
                close.set_focus_on_click(false);
                close.set_tooltip_text(Some("Close tab (Alt+W)"));
                {
                    let w = self.clone();
                    close.connect_clicked(move |_| w.close_window_tab_side(i, None));
                }

                tab_btn.set_child(Some(&inner));
                tab_btn.set_hexpand(true);
                {
                    let w = self.clone();
                    tab_btn.connect_clicked(move |_| w.switch_to_window_tab(i, false));
                }
                holder.append(&tab_btn);
                holder.append(&close);
                strip_row.append(&holder);
            }
        }
        scroll.set_child(Some(&strip_row));
        self.tab_strip.append(&scroll);

        let add_btn = act_icon_btn("list-add-symbolic", "New tab (Alt+T)");
        add_btn.add_css_class("round");
        {
            let w = self.clone();
            add_btn.connect_clicked(move |_| w.open_new_tab(w.active_pane().current_dir()));
        }
        self.tab_strip.append(&add_btn);
    }

    fn rebuild_breadcrumbs(&self, path: &Path) {
        while let Some(c) = self.breadcrumb_box.first_child() {
            self.breadcrumb_box.remove(&c);
        }
        let home = home_dir();
        let mut segments: Vec<(String, PathBuf)> = Vec::new();
        if is_trash_dir(path) {
            segments.push(("Trash".into(), path.to_path_buf()));
        } else if path == home || path.starts_with(&home) {
            segments.push(("Home".into(), home.clone()));
            let rel = path.strip_prefix(&home).unwrap_or(Path::new(""));
            let mut acc = home.clone();
            for comp in rel.components() {
                acc.push(comp);
                segments.push((comp.as_os_str().to_string_lossy().to_string(), acc.clone()));
            }
        } else {
            let mut acc = PathBuf::new();
            for comp in path.components() {
                acc.push(comp);
                let label = match comp {
                    std::path::Component::RootDir => "Computer".into(),
                    _ => comp.as_os_str().to_string_lossy().to_string(),
                };
                segments.push((label, acc.clone()));
            }
        }
        let last_idx = segments.len().saturating_sub(1);
        for (i, (label, target)) in segments.into_iter().enumerate() {
            if i > 0 {
                let sep = gtk4::Label::new(Some("›"));
                sep.add_css_class("alis-crumb-sep");
                self.breadcrumb_box.append(&sep);
            }
            let btn = gtk4::Button::with_label(&label);
            btn.add_css_class("alis-crumb-btn");
            btn.set_focus_on_click(false);
            if i == last_idx {
                btn.add_css_class("crumb-current");
            }
            let w = self.clone();
            btn.connect_clicked(move |_| w.active_pane().navigate_to(target.clone()));
            self.breadcrumb_box.append(&btn);
        }
    }

    fn enter_path_edit(&self) {
        let cur = self.active_pane().current_dir();
        self.path_entry.set_text(&cur.to_string_lossy());
        self.path_inset.add_css_class("focused");
        self.path_stack.set_visible_child_name("entry");
        self.path_entry.grab_focus();
        self.path_entry.select_region(0, -1);
    }

    fn exit_path_edit(&self) {
        self.path_inset.remove_css_class("focused");
        self.path_stack.set_visible_child_name("crumbs");
    }

    fn apply_segment_highlight(&self, mode: ViewMode) {
        for btn in [&self.seg_grid_btn, &self.seg_list_btn, &self.seg_gallery_btn] {
            btn.remove_css_class("active");
        }
        match mode {
            ViewMode::Grid => self.seg_grid_btn.add_css_class("active"),
            ViewMode::List => self.seg_list_btn.add_css_class("active"),
            ViewMode::Gallery => self.seg_gallery_btn.add_css_class("active"),
        }
    }

    fn sync_zoom_slider(&self) {
        self.zoom_updating.set(true);
        let (mode, icon_size, list_zoom) = {
            let st = self.state.borrow();
            (
                st.config.view_mode,
                st.config.grid_icon_size,
                st.config.list_zoom,
            )
        };
        match mode {
            ViewMode::List => {
                self.zoom_scale.set_range(0.0, 2.0);
                self.zoom_scale.set_value(f64::from(list_zoom.min(2)));
            }
            ViewMode::Grid | ViewMode::Gallery => {
                self.zoom_scale.set_range(0.0, (GRID_ZOOM_SIZES.len() - 1) as f64);
                self.zoom_scale.set_value(closest_grid_zoom_step(icon_size));
            }
        }
        self.zoom_updating.set(false);
    }

    fn set_view_mode(&self, mode: ViewMode) {
        if self.state.borrow().config.view_mode == mode {
            return;
        }
        self.save_config_patch(|cfg| {
            cfg.view_mode = mode;
        });
        self.apply_segment_highlight(mode);
        self.sync_zoom_slider();
        self.primary_pane.render_entries();
        if self.split_active.get() {
            self.secondary_pane.render_entries();
        }
    }

    fn toggle_rail(&self) {
        let next = !self.rail_open.get();
        self.rail_open.set(next);
        self.sidebar.root.set_visible(next);
        self.rail_handle.set_visible(next);
        self.rail_toggle_btn.set_visible(!next);
        self.canvas_card.set_margin_start(if next { 0 } else { 8 });
        if !next && self.focused_region.get() == FocusRegion::Rail {
            self.set_focused_region(FocusRegion::Primary, true);
        }
        self.save_config_patch(|cfg| {
            cfg.rail_open = next;
        });
    }

    fn set_split_view(&self, enabled: bool) {
        self.toggle_split_view_for_active_tab(enabled);
    }

    fn set_inspector_open(&self, open: bool) {
        self.inspector_open.set(open);
        self.inspector.root.set_visible(open);
        self.inspector_handle.set_visible(open);
        self.canvas_card.set_margin_end(if open { 0 } else { 8 });
        if open {
            self.inspector_btn.add_css_class("toggled");
            self.on_selection_changed(self.active_pane().selected_entries());
        } else {
            self.inspector_btn.remove_css_class("toggled");
            if matches!(
                self.focused_region.get(),
                FocusRegion::Preview | FocusRegion::Properties
            ) {
                let fallback = if self.split_active.get() && self.active_is_secondary.get() {
                    FocusRegion::Secondary
                } else {
                    FocusRegion::Primary
                };
                self.set_focused_region(fallback, true);
            }
        }
        if self.state.borrow().config.inspector_open_default != open {
            self.save_config_patch(|cfg| {
                cfg.inspector_open_default = open;
            });
        }
    }

    fn set_show_hidden(&self, show: bool) {
        if self.state.borrow().config.show_hidden != show {
            self.save_config_patch(|cfg| {
                cfg.show_hidden = show;
            });
        }
        self.reload_all_panes();
    }

    fn open_sort_popover(&self) {
        let popover = gtk4::Popover::new();
        popover.set_parent(&self.sort_btn);
        popover.set_has_arrow(false);

        let menu = gtk4::Box::new(gtk4::Orientation::Vertical, 2);
        menu.set_width_request(196);
        let (cur_field, cur_order, cur_dirs_first) = {
            let st = self.state.borrow();
            (
                st.config.sort_field,
                st.config.sort_order,
                st.config.directories_first,
            )
        };

        for (label, field) in [
            ("Name", SortField::Name),
            ("Modified", SortField::Modified),
            ("Size", SortField::Size),
            ("Kind", SortField::Kind),
        ] {
            let prefix = if cur_field == field { "✓  " } else { "    " };
            let btn = popover_btn(&format!("{prefix}{label}"));
            let w = self.clone();
            let pop = popover.clone();
            btn.connect_clicked(move |_| {
                pop.popdown();
                w.active_pane().toggle_sort(field);
            });
            menu.append(&btn);
        }
        menu.append(&gtk4::Separator::new(gtk4::Orientation::Horizontal));

        let rev_label = if cur_order == SortOrder::Desc {
            "✓  Reversed"
        } else {
            "    Reversed"
        };
        let rev_btn = popover_btn(rev_label);
        {
            let w = self.clone();
            let pop = popover.clone();
            rev_btn.connect_clicked(move |_| {
                pop.popdown();
                {
                    let mut st = w.state.borrow_mut();
                    st.config.sort_order = match st.config.sort_order {
                        SortOrder::Asc => SortOrder::Desc,
                        SortOrder::Desc => SortOrder::Asc,
                    };
                    let _ = st.config.save();
                }
                w.primary_pane.render_entries();
                if w.split_active.get() {
                    w.secondary_pane.render_entries();
                }
            });
        }
        menu.append(&rev_btn);

        let df_label = if cur_dirs_first {
            "✓  Folders first"
        } else {
            "    Folders first"
        };
        let df_btn = popover_btn(df_label);
        {
            let w = self.clone();
            let pop = popover.clone();
            df_btn.connect_clicked(move |_| {
                pop.popdown();
                {
                    let mut st = w.state.borrow_mut();
                    st.config.directories_first = !st.config.directories_first;
                    let _ = st.config.save();
                }
                w.primary_pane.render_entries();
                if w.split_active.get() {
                    w.secondary_pane.render_entries();
                }
            });
        }
        menu.append(&df_btn);

        popover.set_child(Some(&menu));
        popover.connect_closed(|p| p.unparent());
        popover.popup();
    }

    fn open_more_popover(&self) {
        let popover = gtk4::Popover::new();
        popover.set_parent(&self.more_btn);
        popover.set_has_arrow(false);

        let menu = gtk4::Box::new(gtk4::Orientation::Vertical, 2);
        menu.set_width_request(236);
        let add = |label: &str, icon: &str, cb: Box<dyn Fn()>| {
            let hbox = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
            let img = gtk4::Image::from_icon_name(icon);
            img.set_pixel_size(15);
            let lbl = gtk4::Label::new(Some(label));
            lbl.set_xalign(0.0);
            hbox.append(&img);
            hbox.append(&lbl);
            let btn = gtk4::Button::new();
            btn.set_child(Some(&hbox));
            btn.set_has_frame(false);
            btn.set_focus_on_click(false);
            btn.add_css_class("alis-sidebar-row");
            let pop = popover.clone();
            btn.connect_clicked(move |_| {
                pop.popdown();
                cb();
            });
            menu.append(&btn);
        };

        let show_hidden = self.state.borrow().config.show_hidden;
        {
            let w = self.clone();
            add(
                if show_hidden {
                    "✓ Show Hidden Files (Ctrl+H)"
                } else {
                    "Show Hidden Files (Ctrl+H)"
                },
                "view-reveal-symbolic",
                Box::new(move || w.set_show_hidden(!show_hidden)),
            );
        }
        {
            let w = self.clone();
            add(
                "Command & Jump Palette (Ctrl+K)",
                "preferences-desktop-keyboard-shortcuts-symbolic",
                Box::new(move || w.open_palette()),
            );
        }
        {
            let w = self.clone();
            add(
                "Toggle Places Rail (F9)",
                "sidebar-show-symbolic",
                Box::new(move || w.toggle_rail()),
            );
        }
        menu.append(&gtk4::Separator::new(gtk4::Orientation::Horizontal));
        {
            let w = self.clone();
            add(
                "New Tab (Alt+T)",
                "tab-new-symbolic",
                Box::new(move || {
                    let cur = w.active_pane().current_dir();
                    w.open_new_tab(cur);
                }),
            );
        }
        {
            let w = self.clone();
            add(
                "New Folder (Ctrl+Shift+N)",
                "folder-new-symbolic",
                Box::new(move || w.prompt_new_folder()),
            );
        }
        {
            let w = self.clone();
            add(
                "New File",
                "document-new-symbolic",
                Box::new(move || w.prompt_new_file()),
            );
        }
        {
            let w = self.clone();
            add(
                "Bulk Rename Selected…",
                "document-edit-symbolic",
                Box::new(move || {
                    let ps = w.active_pane().selected_paths();
                    w.open_bulk_rename(ps);
                }),
            );
        }
        {
            let w = self.clone();
            add(
                "Disk Space Analyzer",
                "drive-harddisk-symbolic",
                Box::new(move || w.open_disk_analyzer()),
            );
        }
        {
            let w = self.clone();
            add(
                "Open Terminal Here",
                "utilities-terminal-symbolic",
                Box::new(move || {
                    let cur = w.active_pane().current_dir();
                    match crate::alis_actions::open_terminal_here(&cur) {
                        Ok(m) => w.show_toast(&m, false),
                        Err(e) => w.show_toast(&e, false),
                    }
                }),
            );
        }

        popover.set_child(Some(&menu));
        popover.connect_closed(|p| p.unparent());
        popover.popup();
    }

    fn open_quicklook_for(&self, target_path: &Path) {
        let pane = self.active_pane();
        let all = pane.visible_entries_snapshot();
        if let Some(pos) = all.iter().position(|e| e.path == target_path) {
            let p = pane.clone();
            open_quicklook_items(
                &self.window,
                all,
                pos,
                Some(Rc::new(move |e: &FileEntry| {
                    p.select_path(&e.path);
                })),
            );
        } else if let Ok(fe) = FileEntry::from_path(target_path.to_path_buf()) {
            open_quicklook_items(&self.window, vec![fe], 0, None);
        }
    }

    fn reload_all_panes(&self) {
        self.primary_pane.reload();
        if self.split_active.get() {
            self.secondary_pane.reload();
        }
        self.sync_chrome();
    }

    fn on_selection_changed(&self, entries: Vec<FileEntry>) {
        self.sync_chrome();
        if !self.inspector_open.get() {
            return;
        }
        let thumbs = self.state.borrow().config.thumbnails_enabled;
        match entries.len() {
            0 => {
                let pane = self.active_pane();
                self.inspector
                    .inspect_folder(&pane.current_dir(), pane.visible_count());
            }
            1 => self.inspector.inspect_entry(&entries[0], thumbs),
            _ => self.inspector.show_multi_entries(&entries),
        }
    }

    fn open_file_entry(&self, entry: &FileEntry) {
        if entry.is_broken_symlink {
            self.show_toast(&format!("Broken symbolic link: {}", entry.name), false);
            return;
        }
        if let Err(e) = crate::alis_actions::open_with_default_app(&entry.path) {
            self.show_toast(&e, false);
        }
    }

    fn show_toast(&self, msg: &str, with_undo: bool) {
        let seq = self.toast_gen.get().wrapping_add(1);
        self.toast_gen.set(seq);
        self.toast_label.set_text(msg);
        self.toast_label.set_tooltip_text(Some(msg));
        let lower = msg.to_ascii_lowercase();
        let is_err = lower.contains("error")
            || lower.contains("failed")
            || lower.contains("cannot")
            || lower.contains("could not")
            || lower.contains("does not exist");
        if is_err {
            self.toast_label.add_css_class("alis-status-toast-error");
        } else {
            self.toast_label.remove_css_class("alis-status-toast-error");
        }
        self.toast_undo_btn
            .set_visible(with_undo && self.state.borrow().undo.can_undo());
        self.status_left.set_visible(false);
        self.toast_box.set_visible(true);
        let tbox = self.toast_box.clone();
        let sleft = self.status_left.clone();
        let gen_cell = self.toast_gen.clone();
        let delay_ms = if is_err { 5500 } else { 4200 };
        glib::timeout_add_local_once(std::time::Duration::from_millis(delay_ms), move || {
            if gen_cell.get() == seq {
                tbox.set_visible(false);
                sleft.set_visible(true);
            }
        });
    }

    // ── File Operations ──────────────────────────────────────────────────

    fn copy_selected(&self) {
        let paths = self.active_pane().action_paths();
        if paths.is_empty() {
            return;
        }
        let n = paths.len();
        let was_cut = self.state.borrow().clipboard.op == Some(ClipboardOp::Cut);
        set_system_clipboard_files(&self.state, paths, ClipboardOp::Copy);
        if was_cut {
            self.primary_pane.render_entries();
            if self.split_active.get() {
                self.secondary_pane.render_entries();
            }
        }
        self.show_toast(&format!("Copied {n} item(s)"), false);
    }

    fn cut_selected(&self) {
        let paths = self.active_pane().action_paths();
        if paths.is_empty() {
            return;
        }
        let n = paths.len();
        set_system_clipboard_files(&self.state, paths, ClipboardOp::Cut);
        self.primary_pane.render_entries();
        if self.split_active.get() {
            self.secondary_pane.render_entries();
        }
        self.show_toast(&format!("Cut {n} item(s)"), false);
    }

    fn paste_into_active(&self) {
        let dest_dir = self.active_pane().current_dir();
        let w = self.clone();
        read_clipboard_files(&self.state, move |paths, op| {
            if paths.is_empty() {
                w.show_toast("Clipboard has no files to paste", false);
                return;
            }
            w.execute_transfer(paths, dest_dir, op);
        });
    }

    fn handle_drop(&self, paths: Vec<PathBuf>, dest_dir: PathBuf, action: gdk::DragAction) {
        let op = if action == gdk::DragAction::MOVE {
            ClipboardOp::Cut
        } else {
            ClipboardOp::Copy
        };
        self.execute_transfer(paths, dest_dir, op);
    }

    fn execute_transfer(&self, paths: Vec<PathBuf>, dest_dir: PathBuf, op: ClipboardOp) {
        let is_move = op == ClipboardOp::Cut;
        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            let mut pairs = Vec::with_capacity(paths.len());
            for src in paths {
                let Some(name) = src.file_name() else {
                    continue;
                };
                let desired = dest_dir.join(name);
                if is_move && desired == src {
                    continue;
                }
                if src.is_dir() && crate::fs_ops::is_same_or_descendant(&src, &dest_dir) {
                    let _ = tx.send(Err("Cannot move or copy a folder inside itself".into()));
                    return;
                }
                let target = unique_destination(&desired);
                pairs.push((src, target));
            }
            let _ = tx.send(transfer_batch(is_move, &pairs));
        });

        let w = self.clone();
        glib::timeout_add_local(std::time::Duration::from_millis(40), move || {
            match rx.try_recv() {
                Ok(Ok((created, moved))) => {
                    if !created.is_empty() {
                        let n = created.len();
                        w.state.borrow_mut().undo.push(UndoAction::Created {
                            label: format!("Copy {n} item(s)"),
                            paths: created,
                        });
                        w.show_toast(&format!("Copied {n} item(s)"), true);
                    } else if !moved.is_empty() {
                        let n = moved.len();
                        {
                            let mut st = w.state.borrow_mut();
                            st.clipboard.paths.clear();
                            st.clipboard.op = None;
                            st.undo.push(UndoAction::Moved {
                                label: format!("Move {n} item(s)"),
                                pairs: moved,
                            });
                        }
                        w.show_toast(&format!("Moved {n} item(s)"), true);
                    }
                    w.reload_all_panes();
                    glib::ControlFlow::Break
                }
                Ok(Err(err)) => {
                    w.show_toast(&err, false);
                    w.reload_all_panes();
                    glib::ControlFlow::Break
                }
                Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
                Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
            }
        });
    }

    fn trash_selected(&self) {
        let cur = self.active_pane().current_dir();
        if is_trash_dir(&cur) {
            self.permanent_delete_selected();
            return;
        }
        let paths = self.active_pane().action_paths();
        if paths.is_empty() {
            return;
        }
        let w = self.clone();
        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            let _ = tx.send(trash_batch(&paths));
        });
        glib::timeout_add_local(std::time::Duration::from_millis(30), move || match rx.try_recv() {
            Ok(Ok(records)) => {
                if !records.is_empty() {
                    let n = records.len();
                    w.state.borrow_mut().undo.push(UndoAction::Trashed {
                        label: format!("Trash {n} item(s)"),
                        items: records,
                    });
                    w.sidebar.rebuild_places();
                    w.reload_all_panes();
                    w.show_toast(&format!("Moved {n} item(s) to Trash"), true);
                }
                glib::ControlFlow::Break
            }
            Ok(Err(err)) => {
                w.reload_all_panes();
                w.show_toast(&err, false);
                glib::ControlFlow::Break
            }
            Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
            Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
        });
    }

    fn permanent_delete_selected(&self) {
        let paths = self.active_pane().action_paths();
        if paths.is_empty() {
            return;
        }
        let n = paths.len();
        let cur = self.active_pane().current_dir();
        let in_trash = is_trash_dir(&cur);
        let confirm = self.state.borrow().config.confirm_permanent_delete;
        let do_delete = {
            let w = self.clone();
            let ps = paths.clone();
            move || {
                let w_ui = w.clone();
                let (tx, rx) = std::sync::mpsc::channel();
                std::thread::spawn(move || {
                    if let Err(err) = remove_permanent_batch(&ps) {
                        let _ = tx.send(Err(err));
                        return;
                    }
                    if in_trash {
                        for p in &ps {
                            if let Some(name) =
                                p.file_name().map(|n| n.to_string_lossy().to_string())
                            {
                                let _ = std::fs::remove_file(
                                    crate::model::trash_info_dir()
                                        .join(format!("{name}.trashinfo")),
                                );
                            }
                        }
                    }
                    let _ = tx.send(Ok(()));
                });
                glib::timeout_add_local(std::time::Duration::from_millis(30), move || {
                    match rx.try_recv() {
                        Ok(Ok(())) => {
                            if in_trash {
                                w_ui.sidebar.rebuild_places();
                            }
                            w_ui.reload_all_panes();
                            w_ui.show_toast(&format!("Permanently deleted {n} item(s)"), false);
                            glib::ControlFlow::Break
                        }
                        Ok(Err(err)) => {
                            if in_trash {
                                w_ui.sidebar.rebuild_places();
                            }
                            w_ui.reload_all_panes();
                            w_ui.show_toast(&err, false);
                            glib::ControlFlow::Break
                        }
                        Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                            glib::ControlFlow::Break
                        }
                        Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                    }
                });
            }
        };
        if confirm {
            open_confirm_dialog(
                &self.window,
                "Delete Permanently",
                &format!("Permanently delete {n} item(s)? This cannot be undone."),
                "Delete Permanently",
                true,
                do_delete,
            );
        } else {
            do_delete();
        }
    }

    fn perform_undo(&self) {
        let mut mgr = std::mem::take(&mut self.state.borrow_mut().undo);
        let w = self.clone();
        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            let res = mgr.undo();
            let _ = tx.send((mgr, res));
        });
        glib::timeout_add_local(std::time::Duration::from_millis(25), move || match rx.try_recv() {
            Ok((mgr, res)) => {
                w.state.borrow_mut().undo = mgr;
                match res {
                    Ok(Some(msg)) => {
                        w.sidebar.rebuild_places();
                        w.reload_all_panes();
                        w.show_toast(&msg, false);
                    }
                    Ok(None) => w.show_toast("Nothing to undo", false),
                    Err(e) => {
                        w.reload_all_panes();
                        w.show_toast(&e, false);
                    }
                }
                glib::ControlFlow::Break
            }
            Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
            Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
        });
    }

    fn perform_redo(&self) {
        let mut mgr = std::mem::take(&mut self.state.borrow_mut().undo);
        let w = self.clone();
        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            let res = mgr.redo();
            let _ = tx.send((mgr, res));
        });
        glib::timeout_add_local(std::time::Duration::from_millis(25), move || match rx.try_recv() {
            Ok((mgr, res)) => {
                w.state.borrow_mut().undo = mgr;
                match res {
                    Ok(Some(msg)) => {
                        w.sidebar.rebuild_places();
                        w.reload_all_panes();
                        w.show_toast(&msg, true);
                    }
                    Ok(None) => w.show_toast("Nothing to redo", false),
                    Err(e) => {
                        w.reload_all_panes();
                        w.show_toast(&e, false);
                    }
                }
                glib::ControlFlow::Break
            }
            Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
            Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
        });
    }

    fn prompt_new_folder(&self) {
        let dir = self.active_pane().current_dir();
        let w = self.clone();
        open_name_prompt(
            &self.window,
            "New Folder",
            "Folder name:",
            "New Folder",
            "Create",
            move |name| {
                let d = dir.clone();
                let nm = name.clone();
                let (tx, rx) = std::sync::mpsc::channel();
                std::thread::spawn(move || {
                    let _ = tx.send(create_folder(&d, &nm));
                });
                let w_ui = w.clone();
                glib::timeout_add_local(std::time::Duration::from_millis(30), move || match rx
                    .try_recv()
                {
                    Ok(Ok(created)) => {
                        w_ui.state.borrow_mut().undo.push(UndoAction::Created {
                            label: format!("Create folder '{name}'"),
                            paths: vec![created.clone()],
                        });
                        w_ui.active_pane().reload_and_select(Some(created));
                        w_ui.show_toast(&format!("Created folder '{name}'"), true);
                        glib::ControlFlow::Break
                    }
                    Ok(Err(e)) => {
                        w_ui.show_toast(&e, false);
                        glib::ControlFlow::Break
                    }
                    Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
                    Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                });
            },
        );
    }

    fn prompt_new_file(&self) {
        let dir = self.active_pane().current_dir();
        let w = self.clone();
        open_name_prompt(
            &self.window,
            "New File",
            "File name:",
            "untitled.txt",
            "Create",
            move |name| {
                let d = dir.clone();
                let nm = name.clone();
                let (tx, rx) = std::sync::mpsc::channel();
                std::thread::spawn(move || {
                    let _ = tx.send(create_file(&d, &nm));
                });
                let w_ui = w.clone();
                glib::timeout_add_local(std::time::Duration::from_millis(30), move || match rx
                    .try_recv()
                {
                    Ok(Ok(created)) => {
                        w_ui.state.borrow_mut().undo.push(UndoAction::Created {
                            label: format!("Create file '{name}'"),
                            paths: vec![created.clone()],
                        });
                        w_ui.active_pane().reload_and_select(Some(created));
                        w_ui.show_toast(&format!("Created '{name}'"), true);
                        glib::ControlFlow::Break
                    }
                    Ok(Err(e)) => {
                        w_ui.show_toast(&e, false);
                        glib::ControlFlow::Break
                    }
                    Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
                    Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                });
            },
        );
    }

    fn prompt_create_entry(&self) {
        let dir = self.active_pane().current_dir();
        let w = self.clone();
        open_name_prompt(
            &self.window,
            "Create (end with / for folder)",
            "Name (e.g. notes.txt or docs/):",
            "",
            "Create",
            move |name| {
                let d = dir.clone();
                let nm = name.clone();
                let (tx, rx) = std::sync::mpsc::channel();
                std::thread::spawn(move || {
                    let _ = tx.send(create_entry_yazi(&d, &nm));
                });
                let d_ui = dir.clone();
                let w_ui = w.clone();
                glib::timeout_add_local(std::time::Duration::from_millis(30), move || match rx
                    .try_recv()
                {
                    Ok(Ok((created, is_dir))) => {
                        let clean = name.trim().trim_end_matches('/');
                        let msg = if is_dir {
                            format!("Created folder '{clean}'")
                        } else {
                            format!("Created '{clean}'")
                        };
                        w_ui.state.borrow_mut().undo.push(UndoAction::Created {
                            label: msg.clone(),
                            paths: vec![created.clone()],
                        });
                        let select_target = created
                            .strip_prefix(&d_ui)
                            .ok()
                            .and_then(|rel| rel.components().next())
                            .map(|comp| d_ui.join(comp.as_os_str()))
                            .unwrap_or(created);
                        w_ui.active_pane().reload_and_select(Some(select_target));
                        w_ui.show_toast(&msg, true);
                        glib::ControlFlow::Break
                    }
                    Ok(Err(e)) => {
                        w_ui.show_toast(&e, false);
                        glib::ControlFlow::Break
                    }
                    Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
                    Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                });
            },
        );
    }

    fn prompt_rename_selected(&self) {
        let sel = self.active_pane().action_entries();
        if sel.is_empty() {
            return;
        }
        if sel.len() > 1 {
            let paths: Vec<PathBuf> = sel.into_iter().map(|e| e.path).collect();
            self.open_bulk_rename(paths);
            return;
        }
        let target = sel[0].clone();
        let orig_name = target.name.clone();
        let select_stem_only = !target.is_dir && !target.name.starts_with('.');
        let w = self.clone();
        open_name_prompt_with_selection(
            &self.window,
            "Rename",
            "New name:",
            &orig_name,
            "Rename",
            select_stem_only,
            move |new_name| {
                let tpath = target.path.clone();
                let tname = target.name.clone();
                let nn = new_name.clone();
                let (tx, rx) = std::sync::mpsc::channel();
                std::thread::spawn(move || {
                    let _ = tx.send(rename_single(&tpath, &nn));
                });
                let w_ui = w.clone();
                let orig_path = target.path.clone();
                glib::timeout_add_local(std::time::Duration::from_millis(30), move || match rx
                    .try_recv()
                {
                    Ok(Ok(dest)) => {
                        if dest != orig_path {
                            w_ui.state.borrow_mut().undo.push(UndoAction::Moved {
                                label: format!("Rename '{tname}'"),
                                pairs: vec![(orig_path.clone(), dest.clone())],
                            });
                            w_ui.active_pane().reload_and_select(Some(dest));
                            w_ui.show_toast(&format!("Renamed to '{new_name}'"), true);
                        }
                        glib::ControlFlow::Break
                    }
                    Ok(Err(e)) => {
                        w_ui.show_toast(&e, false);
                        glib::ControlFlow::Break
                    }
                    Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
                    Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                });
            },
        );
    }

    fn open_bulk_rename(&self, paths: Vec<PathBuf>) {
        if paths.is_empty() {
            return;
        }
        let w = self.clone();
        open_bulk_rename_dialog(&self.window, paths, move |pairs| {
            let n = pairs.len();
            if n > 0 {
                w.state.borrow_mut().undo.push(UndoAction::Moved {
                    label: format!("Bulk rename {n} item(s)"),
                    pairs,
                });
                w.reload_all_panes();
                w.show_toast(&format!("Renamed {n} item(s)"), true);
            }
        });
    }

    fn open_compress(&self, sources: Vec<PathBuf>, dest_dir: PathBuf) {
        if sources.is_empty() {
            return;
        }
        let default_name = if sources.len() == 1 {
            sources[0]
                .file_stem()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or_else(|| "archive".into())
        } else {
            dest_dir
                .file_name()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or_else(|| "archive".into())
        };
        let w = self.clone();
        open_compress_dialog(&self.window, &default_name, move |name, fmt: ArchiveFormat| {
            w.show_toast(&format!("Compressing '{name}.{}'…", fmt.extension()), false);
            let w_ui = w.clone();
            let (tx, rx) = std::sync::mpsc::channel();
            std::thread::spawn(move || {
                let res = crate::archive::compress(&sources, &dest_dir, &name, fmt);
                let _ = tx.send(res);
            });
            glib::timeout_add_local(std::time::Duration::from_millis(60), move || {
                match rx.try_recv() {
                    Ok(Ok(archive_path)) => {
                        w_ui.state.borrow_mut().undo.push(UndoAction::Created {
                            label: "Create archive".into(),
                            paths: vec![archive_path.clone()],
                        });
                        w_ui.active_pane().reload_and_select(Some(archive_path));
                        w_ui.show_toast("Archive created", true);
                        glib::ControlFlow::Break
                    }
                    Ok(Err(err)) => {
                        w_ui.show_toast(&err, false);
                        glib::ControlFlow::Break
                    }
                    Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
                    Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                }
            });
        });
    }

    fn extract_archive(&self, archive_path: PathBuf, into_subfolder: bool) {
        self.show_toast("Extracting archive…", false);
        let w = self.clone();
        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            let res = crate::archive::extract(&archive_path, into_subfolder);
            let _ = tx.send(res);
        });
        glib::timeout_add_local(std::time::Duration::from_millis(60), move || {
            match rx.try_recv() {
                Ok(Ok(out_dir)) => {
                    if into_subfolder {
                        w.state.borrow_mut().undo.push(UndoAction::Created {
                            label: "Extract archive".into(),
                            paths: vec![out_dir.clone()],
                        });
                    }
                    w.reload_all_panes();
                    if into_subfolder {
                        w.active_pane().select_path(&out_dir);
                    }
                    w.show_toast(&format!("Extracted to {}", out_dir.display()), into_subfolder);
                    glib::ControlFlow::Break
                }
                Ok(Err(err)) => {
                    w.show_toast(&err, false);
                    glib::ControlFlow::Break
                }
                Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
                Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
            }
        });
    }

    fn open_disk_analyzer(&self) {
        let dir = self.active_pane().current_dir();
        let w = self.clone();
        open_disk_analyzer_dialog(
            &self.window,
            dir,
            Rc::new(move |target| w.active_pane().navigate_to(target)),
        );
    }

    fn save_config_patch(&self, patch: impl FnOnce(&mut AppConfig)) {
        save_disk_config_patch(&self.state, patch);
    }

    fn add_bookmark(&self, path: &Path) {
        let mut added = false;
        self.save_config_patch(|cfg| {
            added = cfg.add_bookmark(path);
        });
        if added {
            self.sidebar
                .rebuild_bookmarks(&self.state.borrow().config.bookmarks);
            self.show_toast("Added bookmark", false);
        }
    }

    fn remove_bookmark(&self, path_str: &str) {
        let mut removed = false;
        self.save_config_patch(|cfg| {
            removed = cfg.remove_bookmark(path_str);
        });
        self.sidebar
            .rebuild_bookmarks(&self.state.borrow().config.bookmarks);
        if removed {
            self.show_toast("Removed bookmark", false);
        }
    }

    // ── Context Menu (Standard + Archive + Bulk Rename + 4 Alis Actions) ─

    fn show_context_menu(
        &self,
        anchor: &gtk4::Widget,
        x: f64,
        y: f64,
        selected: Vec<FileEntry>,
        current_dir: PathBuf,
    ) {
        let popover = gtk4::Popover::new();
        popover.set_parent(anchor);
        popover.set_has_arrow(false);
        popover.set_pointing_to(Some(&gdk::Rectangle::new(x as i32, y as i32, 1, 1)));

        let menu_box = gtk4::Box::new(gtk4::Orientation::Vertical, 2);
        menu_box.set_width_request(234);

        let add_item = |label: &str, icon: &str, action: Box<dyn Fn()>| {
            let hbox = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
            let img = gtk4::Image::from_icon_name(icon);
            img.set_pixel_size(15);
            let lbl = gtk4::Label::new(Some(label));
            lbl.set_xalign(0.0);
            hbox.append(&img);
            hbox.append(&lbl);
            let btn = gtk4::Button::new();
            btn.set_child(Some(&hbox));
            btn.set_has_frame(false);
            btn.set_focus_on_click(false);
            btn.add_css_class("alis-sidebar-row");
            let pop = popover.clone();
            btn.connect_clicked(move |_| {
                pop.popdown();
                action();
            });
            menu_box.append(&btn);
        };
        let add_sep = || {
            let sep = gtk4::Separator::new(gtk4::Orientation::Horizontal);
            sep.set_margin_top(3);
            sep.set_margin_bottom(3);
            menu_box.append(&sep);
        };

        let in_trash = is_trash_dir(&current_dir);

        if selected.is_empty() {
            if !in_trash {
                {
                    let w = self.clone();
                    add_item("New Folder", "folder-new-symbolic", Box::new(move || w.prompt_new_folder()));
                }
                {
                    let w = self.clone();
                    add_item("New File", "document-new-symbolic", Box::new(move || w.prompt_new_file()));
                }
                {
                    let w = self.clone();
                    add_item("Paste", "edit-paste-symbolic", Box::new(move || w.paste_into_active()));
                }
                add_sep();
                {
                    let dir = current_dir.clone();
                    let w = self.clone();
                    add_item(
                        "Open Terminal Here",
                        "utilities-terminal-symbolic",
                        Box::new(move || match crate::alis_actions::open_terminal_here(&dir) {
                            Ok(m) => w.show_toast(&m, false),
                            Err(e) => w.show_toast(&e, false),
                        }),
                    );
                }
                {
                    let dir = current_dir.clone();
                    let w = self.clone();
                    add_item(
                        "Analyze Disk Space",
                        "drive-harddisk-symbolic",
                        Box::new(move || {
                            let w2 = w.clone();
                            open_disk_analyzer_dialog(
                                &w.window,
                                dir.clone(),
                                Rc::new(move |t| w2.active_pane().navigate_to(t)),
                            );
                        }),
                    );
                }
                {
                    let dir = current_dir.clone();
                    let w = self.clone();
                    add_item(
                        "Add Folder to Bookmarks",
                        "bookmark-new-symbolic",
                        Box::new(move || w.add_bookmark(&dir)),
                    );
                }
                add_sep();
                {
                    let w = self.clone();
                    add_item(
                        "Properties (Alt+Enter)",
                        "dialog-information-symbolic",
                        Box::new(move || {
                            if !w.inspector_open.get() {
                                w.set_inspector_open(true);
                            }
                            w.inspector.focus_properties_tab("general");
                        }),
                    );
                }
            } else {
                let w = self.clone();
                add_item(
                    "Empty Trash",
                    "user-trash-full-symbolic",
                    Box::new(move || {
                        let w2 = w.clone();
                        open_confirm_dialog(
                            &w.window,
                            "Empty Trash",
                            "Permanently delete every item in the Trash?",
                            "Empty Trash",
                            true,
                            move || {
                                let w3 = w2.clone();
                                let (tx, rx) = std::sync::mpsc::channel();
                                std::thread::spawn(move || {
                                    let _ = tx.send(empty_trash());
                                });
                                glib::timeout_add_local(
                                    std::time::Duration::from_millis(30),
                                    move || match rx.try_recv() {
                                        Ok(Ok(n)) => {
                                            w3.sidebar.rebuild_places();
                                            w3.reload_all_panes();
                                            w3.show_toast(
                                                &format!("Emptied {n} item(s) from Trash"),
                                                false,
                                            );
                                            glib::ControlFlow::Break
                                        }
                                        Ok(Err(e)) => {
                                            w3.show_toast(&e, false);
                                            glib::ControlFlow::Break
                                        }
                                        Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                                            glib::ControlFlow::Break
                                        }
                                        Err(std::sync::mpsc::TryRecvError::Empty) => {
                                            glib::ControlFlow::Continue
                                        }
                                    },
                                );
                            },
                        );
                    }),
                );
            }
        } else {
            let first = selected[0].clone();
            let all_paths: Vec<PathBuf> = selected.iter().map(|e| e.path.clone()).collect();

            if selected.len() == 1 {
                {
                    let e = first.clone();
                    let w = self.clone();
                    add_item(
                        if e.is_dir { "Open" } else { "Open with Default App" },
                        "document-open-symbolic",
                        Box::new(move || {
                            if e.is_dir {
                                w.active_pane().navigate_to(e.path.clone());
                            } else {
                                w.open_file_entry(&e);
                            }
                        }),
                    );
                }
                if first.is_dir {
                    let p = first.path.clone();
                    let w = self.clone();
                    add_item(
                        "Open in New Tab",
                        "tab-new-symbolic",
                        Box::new(move || w.active_pane().open_new_tab(p.clone())),
                    );
                } else {
                    let p = first.path.clone();
                    let w = self.clone();
                    add_item(
                        "Quick Look (Alt+Space)",
                        "view-reveal-symbolic",
                        Box::new(move || w.open_quicklook_for(&p)),
                    );
                }
            }

            // Exclusive Alis Actions (A4)
            let mut has_alis_action = false;
            if selected.len() == 1 && first.supports_wallpaper() {
                add_sep();
                has_alis_action = true;
                let p = first.path.clone();
                let w = self.clone();
                add_item(
                    "Set as Alis Wallpaper",
                    "preferences-desktop-wallpaper-symbolic",
                    Box::new(move || {
                        let p2 = p.clone();
                        w.run_bg_action(move || crate::alis_actions::set_as_alis_wallpaper(&p2));
                    }),
                );
            }
            let audio_paths: Vec<PathBuf> = selected
                .iter()
                .filter(|e| e.supports_local_music())
                .map(|e| e.path.clone())
                .collect();
            if !audio_paths.is_empty() {
                if !has_alis_action {
                    add_sep();
                    has_alis_action = true;
                }
                let w = self.clone();
                add_item(
                    "Play in Alis Local Music",
                    "audio-x-generic-symbolic",
                    Box::new(move || {
                        let ps = audio_paths.clone();
                        w.run_bg_action(move || crate::alis_actions::play_in_alis_local_music(&ps));
                    }),
                );
            }
            if selected.len() == 1 && first.is_dir {
                if !has_alis_action {
                    add_sep();
                    has_alis_action = true;
                }
                let p = first.path.clone();
                let w = self.clone();
                add_item(
                    "Open Terminal Here",
                    "utilities-terminal-symbolic",
                    Box::new(move || match crate::alis_actions::open_terminal_here(&p) {
                        Ok(m) => w.show_toast(&m, false),
                        Err(e) => w.show_toast(&e, false),
                    }),
                );
            }
            if selected.len() == 1 && first.supports_nexus() {
                if !has_alis_action {
                    add_sep();
                    has_alis_action = true;
                }
                let p = first.path.clone();
                let w = self.clone();
                add_item(
                    "Open / Send to Nexus",
                    "accessories-text-editor-symbolic",
                    Box::new(move || {
                        let p2 = p.clone();
                        w.run_bg_action(move || crate::alis_actions::send_to_nexus(&p2));
                    }),
                );
            }
            let file_paths: Vec<PathBuf> = selected
                .iter()
                .filter(|e| !e.is_dir)
                .map(|e| e.path.clone())
                .collect();
            if !file_paths.is_empty() {
                if !has_alis_action {
                    add_sep();
                }
                let w = self.clone();
                add_item(
                    "Send to Alis Companion",
                    "mail-send-symbolic",
                    Box::new(move || {
                        let ps = file_paths.clone();
                        w.run_bg_action(move || crate::alis_actions::send_to_alis_companion(&ps));
                    }),
                );
            }

            add_sep();

            if in_trash {
                let ps = all_paths.clone();
                let w = self.clone();
                add_item(
                    "Restore from Trash",
                    "edit-undo-symbolic",
                    Box::new(move || {
                        let w2 = w.clone();
                        let ps2 = ps.clone();
                        let (tx, rx) = std::sync::mpsc::channel();
                        std::thread::spawn(move || {
                            let mut ok_count = 0usize;
                            for p in &ps2 {
                                if restore_from_trash(p).is_ok() {
                                    ok_count += 1;
                                }
                            }
                            let _ = tx.send(ok_count);
                        });
                        glib::timeout_add_local(
                            std::time::Duration::from_millis(30),
                            move || match rx.try_recv() {
                                Ok(ok_count) => {
                                    w2.sidebar.rebuild_places();
                                    w2.reload_all_panes();
                                    w2.show_toast(&format!("Restored {ok_count} item(s)"), false);
                                    glib::ControlFlow::Break
                                }
                                Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                                    glib::ControlFlow::Break
                                }
                                Err(std::sync::mpsc::TryRecvError::Empty) => {
                                    glib::ControlFlow::Continue
                                }
                            },
                        );
                    }),
                );
                let w = self.clone();
                add_item(
                    "Delete Permanently",
                    "edit-delete-symbolic",
                    Box::new(move || w.permanent_delete_selected()),
                );
            } else {
                {
                    let w = self.clone();
                    add_item("Cut", "edit-cut-symbolic", Box::new(move || w.cut_selected()));
                }
                {
                    let w = self.clone();
                    add_item("Copy", "edit-copy-symbolic", Box::new(move || w.copy_selected()));
                }
                {
                    let w = self.clone();
                    add_item(
                        if selected.len() > 1 {
                            "Bulk Rename…"
                        } else {
                            "Rename (F2)"
                        },
                        "document-edit-symbolic",
                        Box::new(move || w.prompt_rename_selected()),
                    );
                }
                if selected.len() == 1 {
                    let ps = all_paths.clone();
                    let w = self.clone();
                    add_item(
                        "Bulk Rename…",
                        "edit-find-replace-symbolic",
                        Box::new(move || w.open_bulk_rename(ps.clone())),
                    );
                }

                add_sep();
                {
                    let ps = all_paths.clone();
                    let dir = current_dir.clone();
                    let w = self.clone();
                    add_item(
                        "Compress…",
                        "package-x-generic-symbolic",
                        Box::new(move || w.open_compress(ps.clone(), dir.clone())),
                    );
                }
                if selected.len() == 1 && first.is_extractable_archive() {
                    let p1 = first.path.clone();
                    let w1 = self.clone();
                    add_item(
                        "Extract to Subfolder",
                        "extract-archive-symbolic",
                        Box::new(move || w1.extract_archive(p1.clone(), true)),
                    );
                    let p2 = first.path.clone();
                    let w2 = self.clone();
                    add_item(
                        "Extract Here",
                        "extract-archive-symbolic",
                        Box::new(move || w2.extract_archive(p2.clone(), false)),
                    );
                }

                add_sep();
                {
                    let w = self.clone();
                    add_item("Move to Trash", "user-trash-symbolic", Box::new(move || w.trash_selected()));
                }
                {
                    let w = self.clone();
                    add_item(
                        "Delete Permanently",
                        "edit-delete-symbolic",
                        Box::new(move || w.permanent_delete_selected()),
                    );
                }
            }

            add_sep();
            if selected.len() == 1 && first.is_dir {
                let p = first.path.clone();
                let w = self.clone();
                add_item(
                    "Add to Bookmarks",
                    "bookmark-new-symbolic",
                    Box::new(move || w.add_bookmark(&p)),
                );
            }
            {
                let text = all_paths
                    .iter()
                    .map(|p| p.to_string_lossy().to_string())
                    .collect::<Vec<_>>()
                    .join("\n");
                let w = self.clone();
                add_item(
                    "Copy Path",
                    "edit-copy-symbolic",
                    Box::new(move || {
                        set_system_clipboard_text(&text);
                        w.show_toast("Copied path to clipboard", false);
                    }),
                );
            }
            if selected.len() == 1 {
                let w = self.clone();
                add_item(
                    "Properties (Alt+Enter)",
                    "dialog-information-symbolic",
                    Box::new(move || {
                        if !w.inspector_open.get() {
                            w.set_inspector_open(true);
                        }
                        w.inspector.focus_properties_tab("general");
                    }),
                );
            }
        }

        popover.set_child(Some(&menu_box));
        popover.connect_closed(|p| p.unparent());
        popover.popup();
    }

    fn run_bg_action<F>(&self, work: F)
    where
        F: FnOnce() -> Result<String, String> + Send + 'static,
    {
        let w = self.clone();
        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            let _ = tx.send(work());
        });
        glib::timeout_add_local(std::time::Duration::from_millis(50), move || {
            match rx.try_recv() {
                Ok(Ok(msg)) => {
                    w.show_toast(&msg, false);
                    glib::ControlFlow::Break
                }
                Ok(Err(err)) => {
                    w.show_toast(&err, false);
                    glib::ControlFlow::Break
                }
                Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
                Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
            }
        });
    }

    // ── Command / Jump Palette (Ctrl+K) ──────────────────────────────────

    fn open_palette(&self) {
        let mut items: Vec<PaletteEntry> = Vec::new();
        let w = self.clone();

        let mut add_cmd = |title: &str, subtitle: &str, icon: &str, f: Rc<dyn Fn()>| {
            items.push(PaletteEntry {
                title: title.into(),
                subtitle: subtitle.into(),
                icon: icon.into(),
                action: f,
            });
        };

        {
            let w = w.clone();
            add_cmd("Toggle Places Rail", "Show or hide left sidebar (F9)", "sidebar-show-symbolic", Rc::new(move || w.toggle_rail()));
        }
        {
            let w = w.clone();
            add_cmd("Toggle Split View", "Show two folders side-by-side (F3)", "view-dual-symbolic", Rc::new(move || {
                let next = !w.split_active.get();
                w.split_btn.set_active(next);
            }));
        }
        {
            let w = w.clone();
            add_cmd("Toggle Preview Aside", "Show right preview & details sidebar (Ctrl+I)", "sidebar-show-right-symbolic", Rc::new(move || {
                let next = !w.inspector_open.get();
                w.inspector_btn.set_active(next);
            }));
        }
        {
            let w = w.clone();
            add_cmd("Grid View", "Switch to icon & thumbnail grid (Ctrl+1)", "view-grid-symbolic", Rc::new(move || w.set_view_mode(ViewMode::Grid)));
        }
        {
            let w = w.clone();
            add_cmd("List View", "Switch to sortable column list (Ctrl+2)", "view-list-symbolic", Rc::new(move || w.set_view_mode(ViewMode::List)));
        }
        {
            let w = w.clone();
            add_cmd("Gallery View", "Switch to full-bleed media gallery (Ctrl+3)", "folder-pictures-symbolic", Rc::new(move || w.set_view_mode(ViewMode::Gallery)));
        }
        {
            let w = w.clone();
            add_cmd("Toggle Hidden Files", "Show or hide dotfiles (Ctrl+H)", "view-reveal-symbolic", Rc::new(move || {
                let cur = w.state.borrow().config.show_hidden;
                w.set_show_hidden(!cur);
            }));
        }
        {
            let w = w.clone();
            add_cmd("Disk Space Analyzer", "Inspect folder sizes in current directory", "drive-harddisk-symbolic", Rc::new(move || w.open_disk_analyzer()));
        }
        {
            let w = w.clone();
            add_cmd("Bulk Rename Selected", "Batch rename with find/replace & numbering", "document-edit-symbolic", Rc::new(move || {
                let ps = w.active_pane().selected_paths();
                w.open_bulk_rename(ps);
            }));
        }
        {
            let w = w.clone();
            add_cmd("Open Terminal Here", "Launch Alis terminal in current folder", "utilities-terminal-symbolic", Rc::new(move || {
                let cur = w.active_pane().current_dir();
                match crate::alis_actions::open_terminal_here(&cur) {
                    Ok(m) => w.show_toast(&m, false),
                    Err(e) => w.show_toast(&e, false),
                }
            }));
        }
        {
            let w = w.clone();
            add_cmd("New Folder", "Create folder in current directory (Ctrl+Shift+N)", "folder-new-symbolic", Rc::new(move || w.prompt_new_folder()));
        }
        {
            let w = w.clone();
            add_cmd("New File", "Create empty file in current directory", "document-new-symbolic", Rc::new(move || w.prompt_new_file()));
        }
        {
            let w = w.clone();
            add_cmd("Undo Last File Operation", "Revert move, rename, copy, or trash (Ctrl+Z)", "edit-undo-symbolic", Rc::new(move || w.perform_undo()));
        }

        let (bookmarks, recents) = {
            let st = self.state.borrow();
            (st.config.bookmarks.clone(), st.config.recent_folders.clone())
        };
        for bm in bookmarks {
            let p = PathBuf::from(&bm.path);
            let w = self.clone();
            items.push(PaletteEntry {
                title: format!("Bookmark: {}", bm.name),
                subtitle: bm.path,
                icon: "user-bookmarks-symbolic".into(),
                action: Rc::new(move || w.active_pane().navigate_to(p.clone())),
            });
        }
        for recent in recents {
            let p = PathBuf::from(&recent);
            let name = p
                .file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_else(|| recent.clone());
            let w = self.clone();
            items.push(PaletteEntry {
                title: format!("Jump: {name}"),
                subtitle: recent,
                icon: "folder-recent-symbolic".into(),
                action: Rc::new(move || w.active_pane().navigate_to(p.clone())),
            });
        }
        let home = home_dir();
        for (name, p) in [
            ("Home", home.clone()),
            ("Downloads", home.join("Downloads")),
            ("Documents", home.join("Documents")),
            ("Pictures", home.join("Pictures")),
            ("Music", home.join("Music")),
            ("Trash", trash_files_dir()),
        ] {
            let w = self.clone();
            items.push(PaletteEntry {
                title: format!("Place: {name}"),
                subtitle: p.to_string_lossy().to_string(),
                icon: "folder-symbolic".into(),
                action: Rc::new(move || w.active_pane().navigate_to(p.clone())),
            });
        }

        open_command_palette(&self.window, items);
    }

    // ── Keyboard Dispatch (Vim + Desktop Shortcuts) ──────────────────────

    fn goto_target(&self, target: GotoTarget) {
        let dest = match target {
            GotoTarget::Home => home_dir(),
            GotoTarget::Config => xdg_config_home(),
            GotoTarget::Downloads => home_dir().join("Downloads"),
            GotoTarget::Documents => home_dir().join("Documents"),
            GotoTarget::Desktop => home_dir().join("Desktop"),
            GotoTarget::Pictures => home_dir().join("Pictures"),
            GotoTarget::Videos => home_dir().join("Videos"),
            GotoTarget::Music => home_dir().join("Music"),
            GotoTarget::Trash => trash_files_dir(),
            GotoTarget::Root => PathBuf::from("/"),
        };
        if target != GotoTarget::Trash && !dest.is_dir() {
            self.show_toast(&format!("Folder not found: {}", dest.display()), false);
            return;
        }
        if matches!(
            self.focused_region.get(),
            FocusRegion::Rail | FocusRegion::Preview | FocusRegion::Properties
        ) {
            let target_region = if self.active_is_secondary.get() {
                FocusRegion::Secondary
            } else {
                FocusRegion::Primary
            };
            self.set_focused_region(target_region, false);
        }
        self.active_pane().navigate_to(dest);
    }

    fn handle_key_command(&self, cmd: KeyCommand) {
        let pane = self.active_pane();
        let region = self.focused_region.get();
        match cmd {
            KeyCommand::FocusPaneLeft
            | KeyCommand::FocusPaneRight
            | KeyCommand::FocusPaneUp
            | KeyCommand::FocusPaneDown => {
                self.move_pane_focus(cmd);
            }
            KeyCommand::MoveDown => match region {
                FocusRegion::Rail => self.sidebar.move_keyboard_focus(1),
                FocusRegion::Preview => self.inspector.scroll_card("preview", 48.0),
                FocusRegion::Properties => self.inspector.scroll_card("properties", 48.0),
                _ => pane.move_selection(1),
            },
            KeyCommand::MoveUp => match region {
                FocusRegion::Rail => self.sidebar.move_keyboard_focus(-1),
                FocusRegion::Preview => self.inspector.scroll_card("preview", -48.0),
                FocusRegion::Properties => self.inspector.scroll_card("properties", -48.0),
                _ => pane.move_selection(-1),
            },
            KeyCommand::MoveDownFast => match region {
                FocusRegion::Rail => self.sidebar.move_keyboard_focus(5),
                FocusRegion::Preview => self.inspector.scroll_card("preview", 180.0),
                FocusRegion::Properties => self.inspector.scroll_card("properties", 180.0),
                _ => pane.move_selection(5),
            },
            KeyCommand::MoveUpFast => match region {
                FocusRegion::Rail => self.sidebar.move_keyboard_focus(-5),
                FocusRegion::Preview => self.inspector.scroll_card("preview", -180.0),
                FocusRegion::Properties => self.inspector.scroll_card("properties", -180.0),
                _ => pane.move_selection(-5),
            },
            KeyCommand::MoveHalfPageDown => match region {
                FocusRegion::Rail => self.sidebar.move_keyboard_focus(10),
                FocusRegion::Preview => self.inspector.scroll_card("preview", 320.0),
                FocusRegion::Properties => self.inspector.scroll_card("properties", 320.0),
                _ => pane.move_selection(10),
            },
            KeyCommand::MoveHalfPageUp => match region {
                FocusRegion::Rail => self.sidebar.move_keyboard_focus(-10),
                FocusRegion::Preview => self.inspector.scroll_card("preview", -320.0),
                FocusRegion::Properties => self.inspector.scroll_card("properties", -320.0),
                _ => pane.move_selection(-10),
            },
            KeyCommand::GoParent => match region {
                FocusRegion::Properties => self.inspector.cycle_props_tab(-1),
                FocusRegion::Rail | FocusRegion::Preview => {}
                _ => pane.go_parent(),
            },
            KeyCommand::OpenSelected => match region {
                FocusRegion::Rail => {
                    if self.sidebar.activate_focused_row() {
                        self.set_focused_region(FocusRegion::Primary, true);
                    }
                }
                FocusRegion::Preview => self.inspector.trigger_open(),
                FocusRegion::Properties => self.inspector.cycle_props_tab(1),
                _ => pane.activate_selected(),
            },
            KeyCommand::GoFirst => pane.select_first(),
            KeyCommand::GoLast => pane.select_last(),
            KeyCommand::GoBack => pane.go_back(),
            KeyCommand::GoForward => pane.go_forward(),
            KeyCommand::Goto(target) => self.goto_target(target),
            KeyCommand::Copy => self.copy_selected(),
            KeyCommand::Cut => self.cut_selected(),
            KeyCommand::Paste => self.paste_into_active(),
            KeyCommand::Undo => self.perform_undo(),
            KeyCommand::Redo => self.perform_redo(),
            KeyCommand::Trash => self.trash_selected(),
            KeyCommand::PermanentDelete => self.permanent_delete_selected(),
            KeyCommand::Rename => self.prompt_rename_selected(),
            KeyCommand::NewFolder => self.prompt_new_folder(),
            KeyCommand::CreatePrompt => self.prompt_create_entry(),
            KeyCommand::ToggleHidden => {
                let next = !self.state.borrow().config.show_hidden;
                self.set_show_hidden(next);
            }
            KeyCommand::FocusFilter => pane.show_filter(),
            KeyCommand::FocusPathBar => self.enter_path_edit(),
            KeyCommand::OpenCommandPalette => self.open_palette(),
            KeyCommand::NewTab => {
                let cur = pane.current_dir();
                self.open_new_tab(cur);
            }
            KeyCommand::CloseTab => self.close_active_tab_or_half(),
            KeyCommand::PrevTab => self.prev_window_tab(),
            KeyCommand::NextTab => self.next_window_tab(),
            KeyCommand::SwitchTab(idx) => self.switch_to_window_tab(idx, false),
            KeyCommand::ToggleSplitView => {
                let next = !self.split_active.get();
                self.set_split_view(next);
            }
            KeyCommand::ToggleInspector => {
                let next = !self.inspector_open.get();
                self.inspector_btn.set_active(next);
            }
            KeyCommand::ToggleRail => self.toggle_rail(),
            KeyCommand::SetViewGrid => self.set_view_mode(ViewMode::Grid),
            KeyCommand::SetViewList => self.set_view_mode(ViewMode::List),
            KeyCommand::SetViewGallery => self.set_view_mode(ViewMode::Gallery),
            KeyCommand::QuickLook => {
                if region == FocusRegion::Preview {
                    self.inspector.trigger_quicklook();
                } else if let Some(first) = pane.focused_entry() {
                    self.open_quicklook_for(&first.path);
                }
            }
            KeyCommand::ToggleSelectAndAdvance => {
                if matches!(region, FocusRegion::Primary | FocusRegion::Secondary) {
                    pane.toggle_select_and_advance();
                }
            }
            KeyCommand::Properties => {
                if !self.inspector_open.get() {
                    self.set_inspector_open(true);
                } else {
                    self.on_selection_changed(pane.selected_entries());
                }
                self.inspector.focus_properties_tab("general");
            }
            KeyCommand::SelectAll => pane.select_all(),
            KeyCommand::Refresh => self.reload_all_panes(),
            KeyCommand::SwitchSplitPane => {
                if self.split_active.get() {
                    let target = if self.active_is_secondary.get() {
                        FocusRegion::Primary
                    } else {
                        FocusRegion::Secondary
                    };
                    self.set_focused_region(target, true);
                }
            }
            KeyCommand::Escape => {
                if self.path_stack.visible_child_name().as_deref() == Some("entry") {
                    self.exit_path_edit();
                    pane.focus_view();
                } else if pane.filter_revealer.reveals_child() {
                    pane.hide_filter();
                    pane.focus_view();
                } else {
                    pane.clear_selection();
                    let cleared_cut = {
                        let mut st = self.state.borrow_mut();
                        if st.clipboard.op == Some(ClipboardOp::Cut) {
                            st.clipboard = Default::default();
                            true
                        } else {
                            false
                        }
                    };
                    if cleared_cut {
                        self.primary_pane.render_entries();
                        if self.split_active.get() {
                            self.secondary_pane.render_entries();
                        }
                    }
                }
            }
        }
    }

    fn watch_config_file(&self) {
        let cfg_dir = crate::config::config_dir();
        let _ = std::fs::create_dir_all(&cfg_dir);
        let gdir = gio::File::for_path(&cfg_dir);
        if let Ok(mon) = gdir.monitor_directory(gio::FileMonitorFlags::NONE, gio::Cancellable::NONE)
        {
            let w = self.clone();
            let pending = Rc::new(Cell::new(false));
            mon.connect_changed(move |_, file, other, _| {
                let is_cfg = |f: &gio::File| {
                    f.basename()
                        .and_then(|n| n.into_os_string().into_string().ok())
                        .map(|n| n == "alis-files.json")
                        .unwrap_or(false)
                };
                if !(is_cfg(file) || other.map(is_cfg).unwrap_or(false)) || pending.get() {
                    return;
                }
                pending.set(true);
                let w_ui = w.clone();
                let p = pending.clone();
                glib::timeout_add_local_once(std::time::Duration::from_millis(120), move || {
                    p.set(false);
                    let fresh = AppConfig::load_from(&config_path());
                    let (
                        prev_view,
                        prev_hidden,
                        prev_git,
                        prev_thumbs,
                        prev_dirs_first,
                        prev_icon_size,
                        prev_list_zoom,
                        prev_rail_width,
                        prev_inspector_width,
                        prev_insp_ratio,
                    ) = {
                        let st = w_ui.state.borrow();
                        (
                            st.config.view_mode,
                            st.config.show_hidden,
                            st.config.git_badges,
                            st.config.thumbnails_enabled,
                            st.config.directories_first,
                            st.config.grid_icon_size,
                            st.config.list_zoom,
                            st.config.rail_width,
                            st.config.inspector_width,
                            st.config.inspector_preview_ratio_milli,
                        )
                    };
                    w_ui.state.borrow_mut().config = fresh.clone();
                    w_ui.status_vim.set_visible(fresh.vim_keybindings);
                    if fresh.rail_width != prev_rail_width {
                        w_ui.sidebar.root.set_width_request(fresh.rail_width);
                    }
                    if fresh.inspector_width != prev_inspector_width {
                        w_ui.inspector.root.set_width_request(fresh.inspector_width);
                    }
                    if fresh.inspector_preview_ratio_milli != prev_insp_ratio {
                        w_ui.inspector.set_preview_ratio_milli(fresh.inspector_preview_ratio_milli);
                    }
                    if fresh.view_mode != prev_view {
                        w_ui.apply_segment_highlight(fresh.view_mode);
                        w_ui.sync_zoom_slider();
                    }
                    if fresh.show_hidden != prev_hidden
                        || fresh.view_mode != prev_view
                        || fresh.git_badges != prev_git
                        || fresh.thumbnails_enabled != prev_thumbs
                        || fresh.directories_first != prev_dirs_first
                        || fresh.grid_icon_size != prev_icon_size
                        || fresh.list_zoom != prev_list_zoom
                    {
                        w_ui.reload_all_panes();
                    }
                    w_ui.sidebar.rebuild_bookmarks(&fresh.bookmarks);
                });
            });
            *self._cfg_monitor.borrow_mut() = Some(mon);
        }
    }
}

fn act_icon_btn(icon: &str, tooltip: &str) -> gtk4::Button {
    let btn = gtk4::Button::from_icon_name(icon);
    btn.add_css_class("alis-act-btn");
    btn.set_focus_on_click(false);
    btn.set_tooltip_text(Some(tooltip));
    btn
}

fn seg_icon_btn(icon: &str, tooltip: &str) -> gtk4::Button {
    let btn = gtk4::Button::from_icon_name(icon);
    btn.add_css_class("alis-seg-btn");
    btn.set_focus_on_click(false);
    btn.set_tooltip_text(Some(tooltip));
    btn
}

fn popover_btn(label: &str) -> gtk4::Button {
    let lbl = gtk4::Label::new(Some(label));
    lbl.set_xalign(0.0);
    let btn = gtk4::Button::new();
    btn.set_child(Some(&lbl));
    btn.set_has_frame(false);
    btn.set_focus_on_click(false);
    btn.add_css_class("alis-sidebar-row");
    btn
}

fn collect_window_session(
    primary: &BrowserPane,
    secondary: &BrowserPane,
    window_tabs: &Rc<RefCell<Vec<WindowTab>>>,
    active_tab_idx: usize,
    split_open: bool,
    active_is_secondary: bool,
    split_paned: &gtk4::Paned,
) -> SessionState {
    {
        let mut wtabs = window_tabs.borrow_mut();
        if !wtabs.is_empty() {
            let idx = active_tab_idx.min(wtabs.len() - 1);
            wtabs[idx].left = primary.current_tab_state();
            if split_open && wtabs[idx].right.is_some() {
                wtabs[idx].right = Some(secondary.current_tab_state());
            }
        }
    }
    let wtabs = window_tabs.borrow();
    let active_tab = active_tab_idx.min(wtabs.len().saturating_sub(1));
    let tab_entries: Vec<SessionTab> = wtabs
        .iter()
        .map(|wt| SessionTab {
            path: wt.left.path.to_string_lossy().to_string(),
            split_path: wt
                .right
                .as_ref()
                .map(|r| r.path.to_string_lossy().to_string()),
        })
        .collect();
    let tabs: Vec<String> = tab_entries.iter().map(|e| e.path.clone()).collect();
    let secondary_tabs: Vec<String> = wtabs
        .get(active_tab)
        .and_then(|wt| wt.right.as_ref())
        .map(|r| vec![r.path.to_string_lossy().to_string()])
        .unwrap_or_default();
    let total_w = split_paned.width();
    let split_ratio_milli = if split_open && total_w > 120 {
        let pos = split_paned.position();
        ((f64::from(pos) / f64::from(total_w)) * 1000.0)
            .round()
            .clamp(200.0, 800.0) as u16
    } else {
        500
    };
    SessionState {
        tabs,
        active_tab,
        split_open,
        split_ratio_milli,
        secondary_tabs,
        secondary_active_tab: 0,
        active_is_secondary: split_open && active_is_secondary,
        tab_entries,
    }
}

impl AlisFilesWindow {
    fn schedule_session_save(&self) {
        if self.session_save_scheduled.get() {
            return;
        }
        self.session_save_scheduled.set(true);
        let w = self.clone();
        glib::timeout_add_local_once(std::time::Duration::from_millis(250), move || {
            w.session_save_scheduled.set(false);
            let sess = collect_window_session(
                &w.primary_pane,
                &w.secondary_pane,
                &w.window_tabs,
                w.active_tab_idx.get(),
                w.split_active.get(),
                w.active_is_secondary.get(),
                &w.split_paned,
            );
            w.save_config_patch(|cfg| {
                cfg.session = sess;
            });
        });
    }
}

fn save_disk_config_patch(state: &SharedStateRc, patch: impl FnOnce(&mut AppConfig)) {
    let mut disk = AppConfig::load_from(&config_path());
    patch(&mut disk);
    let _ = disk.save();
    state.borrow_mut().config = disk;
}

fn make_resize_handle(tooltip: &str) -> gtk4::Box {
    let handle = gtk4::Box::new(gtk4::Orientation::Vertical, 0);
    handle.add_css_class("alis-resize-handle");
    handle.set_vexpand(true);
    handle.set_tooltip_text(Some(tooltip));
    handle.set_cursor(gdk::Cursor::from_name("col-resize", None).as_ref());
    let grip = gtk4::Box::new(gtk4::Orientation::Vertical, 0);
    grip.add_css_class("alis-resize-grip");
    grip.set_halign(gtk4::Align::Center);
    grip.set_valign(gtk4::Align::Center);
    grip.set_vexpand(true);
    handle.append(&grip);
    handle
}

#[allow(clippy::too_many_arguments)]
fn attach_pane_resize<P, O>(
    handle: &gtk4::Box,
    outer: &gtk4::Box,
    pane: &P,
    other_pane: &O,
    min_w: i32,
    max_w: i32,
    default_w: i32,
    is_left: bool,
    state: SharedStateRc,
) where
    P: IsA<gtk4::Widget> + Clone + 'static,
    O: IsA<gtk4::Widget> + Clone + 'static,
{
    let anchor_x = Rc::new(Cell::new(0.0_f64));
    let start_w = Rc::new(Cell::new(default_w));
    let drag = gtk4::GestureDrag::new();
    drag.set_button(gdk::BUTTON_PRIMARY);

    {
        let h_ref = handle.clone();
        let outer_ref = outer.clone();
        let pane_ref = pane.clone();
        let ax = anchor_x.clone();
        let sw = start_w.clone();
        drag.connect_drag_begin(move |_, sx, sy| {
            h_ref.add_css_class("dragging");
            let pt = h_ref
                .compute_point(&outer_ref, &gtk4::graphene::Point::new(sx as f32, sy as f32))
                .map(|p| p.x() as f64)
                .unwrap_or(sx);
            ax.set(pt);
            sw.set(pane_ref.width().max(min_w));
        });
    }

    {
        let h_ref = handle.clone();
        let outer_ref = outer.clone();
        let pane_ref = pane.clone();
        let other_ref = other_pane.clone();
        let ax = anchor_x.clone();
        let sw = start_w.clone();
        drag.connect_drag_update(move |g, ox, oy| {
            let (sx, sy) = g.start_point().unwrap_or((0.0, 0.0));
            let cur_x = h_ref
                .compute_point(
                    &outer_ref,
                    &gtk4::graphene::Point::new((sx + ox) as f32, (sy + oy) as f32),
                )
                .map(|p| p.x() as f64)
                .unwrap_or(ax.get() + ox);
            let delta = cur_x - ax.get();
            let other_w = if other_ref.is_visible() {
                other_ref.width()
            } else {
                0
            };
            let dynamic_max = (outer_ref.width() - 360 - other_w).clamp(min_w, max_w);
            let raw = if is_left {
                (sw.get() as f64 + delta).round() as i32
            } else {
                (sw.get() as f64 - delta).round() as i32
            };
            pane_ref.set_width_request(raw.clamp(min_w, dynamic_max));
        });
    }

    {
        let h_ref = handle.clone();
        let pane_ref = pane.clone();
        let st_ref = state.clone();
        drag.connect_drag_end(move |_, _, _| {
            h_ref.remove_css_class("dragging");
            let final_w = pane_ref.width().clamp(min_w, max_w);
            pane_ref.set_width_request(final_w);
            save_disk_config_patch(&st_ref, |cfg| {
                if is_left {
                    cfg.rail_width = final_w;
                } else {
                    cfg.inspector_width = final_w;
                }
            });
        });
    }

    handle.add_controller(drag);

    let dbl = gtk4::GestureClick::new();
    dbl.set_button(gdk::BUTTON_PRIMARY);
    {
        let pane_ref = pane.clone();
        let st_ref = state;
        dbl.connect_pressed(move |_, n_press, _, _| {
            if n_press == 2 {
                pane_ref.set_width_request(default_w);
                save_disk_config_patch(&st_ref, |cfg| {
                    if is_left {
                        cfg.rail_width = default_w;
                    } else {
                        cfg.inspector_width = default_w;
                    }
                });
            }
        });
    }
    handle.add_controller(dbl);
}
