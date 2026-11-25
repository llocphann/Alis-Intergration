use crate::config::{SortField, SortOrder, ViewMode};
use crate::git::GitBadge;
use crate::model::{
    FileEntry, FileKind, format_size, format_time, is_trash_dir, read_directory, sort_entries,
};
use crate::thumbnails::{ThumbCacheKey, ThumbJob, ThumbResult, ThumbWorkerPool};
use crate::ui::SharedStateRc;
use gtk4::gdk;
use gtk4::gio;
use gtk4::glib;
use gtk4::prelude::*;
use std::cell::{Cell, RefCell};
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, mpsc};

// ── Lightweight GObject wrapper for FileEntry (virtualized ListView/GridView) ──

mod entry_obj {
    use crate::git::GitBadge;
    use crate::model::FileEntry;
    use gtk4::glib;
    use gtk4::prelude::*;
    use gtk4::subclass::prelude::*;
    use std::cell::RefCell;
    use std::path::PathBuf;
    use std::sync::OnceLock;

    mod imp {
        use super::*;

        #[derive(Default)]
        pub struct FileEntryObject {
            pub entry: RefCell<Option<FileEntry>>,
        }

        #[glib::object_subclass]
        impl ObjectSubclass for FileEntryObject {
            const NAME: &'static str = "AlisFileEntryObject";
            type Type = super::FileEntryObject;
            type ParentType = glib::Object;
        }

        impl ObjectImpl for FileEntryObject {
            fn signals() -> &'static [glib::subclass::Signal] {
                static SIGNALS: OnceLock<Vec<glib::subclass::Signal>> = OnceLock::new();
                SIGNALS.get_or_init(|| {
                    vec![glib::subclass::Signal::builder("badge-changed").build()]
                })
            }
        }
    }

    glib::wrapper! {
        pub struct FileEntryObject(ObjectSubclass<imp::FileEntryObject>);
    }

    impl FileEntryObject {
        pub fn new(entry: FileEntry) -> Self {
            let obj: Self = glib::Object::new();
            *obj.imp().entry.borrow_mut() = Some(entry);
            obj
        }

        pub fn entry(&self) -> Option<FileEntry> {
            self.imp().entry.borrow().clone()
        }

        pub fn path(&self) -> Option<PathBuf> {
            self.imp().entry.borrow().as_ref().map(|e| e.path.clone())
        }

        pub fn is_dir(&self) -> bool {
            self.imp()
                .entry
                .borrow()
                .as_ref()
                .map(|e| e.is_dir)
                .unwrap_or(false)
        }

        pub fn git_badge(&self) -> Option<GitBadge> {
            self.imp()
                .entry
                .borrow()
                .as_ref()
                .and_then(|e| e.git_badge)
        }

        /// Update the Git badge in-place and emit `badge-changed` only when modified.
        pub fn set_git_badge(&self, badge: Option<GitBadge>) -> bool {
            let changed = {
                let mut borrow = self.imp().entry.borrow_mut();
                if let Some(ref mut e) = *borrow {
                    if e.git_badge != badge {
                        e.git_badge = badge;
                        true
                    } else {
                        false
                    }
                } else {
                    false
                }
            };
            if changed {
                self.emit_by_name::<()>("badge-changed", &[]);
            }
            changed
        }

        pub fn connect_badge_changed<F>(&self, f: F) -> glib::SignalHandlerId
        where
            F: Fn(&Self) + 'static,
        {
            self.connect_local("badge-changed", false, move |values| {
                if let Ok(obj) = values[0].get::<Self>() {
                    f(&obj);
                }
                None
            })
        }
    }
}

pub use entry_obj::FileEntryObject;

// ── Virtualized Model Helpers (unit-tested independently of UI display) ────────

fn populate_list_store(store: &gio::ListStore, entries: &[FileEntry]) {
    let prev = store.n_items();
    let objs: Vec<FileEntryObject> = entries
        .iter()
        .cloned()
        .map(FileEntryObject::new)
        .collect();
    store.splice(0, prev, &objs);
}

fn indices_from_bitset(bitset: &gtk4::Bitset) -> Vec<usize> {
    let mut out = Vec::with_capacity(bitset.size() as usize);
    if let Some((iter, first)) = gtk4::BitsetIter::init_first(bitset) {
        out.push(first as usize);
        for pos in iter {
            out.push(pos as usize);
        }
    }
    out
}

fn selected_indices_from_model(selection: &gtk4::MultiSelection) -> Vec<usize> {
    let bitset = selection.selection();
    indices_from_bitset(&bitset)
}

fn matching_positions_in_store(store: &gio::ListStore, targets: &[PathBuf]) -> Vec<u32> {
    let len = store.n_items();
    if len == 0 || targets.is_empty() {
        return Vec::new();
    }
    let target_set: HashSet<&PathBuf> = targets.iter().collect();
    let mut matched = Vec::new();
    for pos in 0..len {
        if let Some(obj) = store.item(pos).and_downcast::<FileEntryObject>()
            && let Some(path) = obj.path()
            && target_set.contains(&path)
        {
            matched.push(pos);
        }
    }
    matched
}

fn select_paths_in_model(
    store: &gio::ListStore,
    selection: &gtk4::MultiSelection,
    targets: &[PathBuf],
) -> Option<usize> {
    let positions = matching_positions_in_store(store, targets);
    let first_match = *positions.first()? as usize;
    let selected = gtk4::Bitset::new_empty();
    for pos in positions {
        selected.add(pos);
    }
    let mask = gtk4::Bitset::new_range(0, store.n_items());
    selection.set_selection(&selected, &mask);
    Some(first_match)
}

fn compute_move_selection_index(len: usize, current: Option<usize>, delta: isize) -> Option<usize> {
    if len == 0 {
        return None;
    }
    let next = match current {
        None => 0,
        Some(i) => {
            let clamped_cur = i.min(len - 1) as isize;
            (clamped_cur + delta).clamp(0, (len - 1) as isize) as usize
        }
    };
    Some(next)
}

/// Pure main-thread in-place badge update (zero filesystem I/O, zero widget rebuild).
fn apply_git_badges_in_place(
    entries: &mut [FileEntry],
    visible: &mut [FileEntry],
    store: &gio::ListStore,
    badges: &HashMap<PathBuf, GitBadge>,
) -> usize {
    for e in entries.iter_mut() {
        e.git_badge = badges.get(&e.path).copied();
    }
    for e in visible.iter_mut() {
        e.git_badge = badges.get(&e.path).copied();
    }
    let mut updated = 0usize;
    let n = store.n_items();
    for pos in 0..n {
        if let Some(obj) = store.item(pos).and_downcast::<FileEntryObject>()
            && let Some(path) = obj.path()
            && obj.set_git_badge(badges.get(&path).copied())
        {
            updated += 1;
        }
    }
    updated
}

/// Runs on a background thread so filesystem canonicalization never blocks the GTK main thread.
/// Canonicalizes `dir` at most once (O(1) syscalls) instead of per-entry to avoid both
/// O(N) syscall overhead and mis-attributing a symlink target's Git status to a clean symlink.
fn resolve_git_badges_background(
    dir: &Path,
    entry_paths: &[PathBuf],
) -> (Option<String>, HashMap<PathBuf, GitBadge>) {
    let status = crate::git::inspect_directory(dir);
    let mut matched = HashMap::new();
    if !status.badges.is_empty() && !entry_paths.is_empty() {
        let canon_dir = dir.canonicalize().ok();
        for p in entry_paths {
            if let Some(&badge) = status.badges.get(p) {
                matched.insert(p.clone(), badge);
            } else if let Some(ref cdir) = canon_dir
                && let Some(name) = p.file_name()
                && let Some(&badge) = status.badges.get(&cdir.join(name))
            {
                matched.insert(p.clone(), badge);
            }
        }
    }
    (status.branch, matched)
}

// ── Recycled Item Widget State ─────────────────────────────────────────────────

type ThumbSlot = Rc<RefCell<Option<(u64, Arc<AtomicBool>)>>>;
type BadgeConnSlot = Rc<RefCell<Option<(FileEntryObject, glib::SignalHandlerId)>>>;

struct ListRowWidgets {
    row: gtk4::Box,
    icon_stack: gtk4::Stack,
    art_pic: gtk4::Picture,
    thumb_pic: gtk4::Picture,
    name_lbl: gtk4::Label,
    badge_lbl: gtk4::Label,
    kind_lbl: gtk4::Label,
    size_lbl: gtk4::Label,
    mod_lbl: gtk4::Label,
    bind_gen: Rc<Cell<u64>>,
    thumb_slot: ThumbSlot,
    badge_conn: BadgeConnSlot,
}

struct GridCardWidgets {
    card: gtk4::Box,
    plate_overlay: gtk4::Overlay,
    plate_box: gtk4::Box,
    icon_stack: gtk4::Stack,
    art_inner_box: gtk4::Box,
    art_pic: gtk4::Picture,
    tile_inner_name: gtk4::Label,
    thumb_pic: gtk4::Picture,
    badge_lbl: gtk4::Label,
    video_lbl: gtk4::Label,
    gallery_ring: gtk4::Label,
    name_pill: gtk4::Box,
    name_lbl: gtk4::Label,
    bind_gen: Rc<Cell<u64>>,
    thumb_slot: ThumbSlot,
    badge_conn: BadgeConnSlot,
}

struct PendingThumbTarget {
    bind_gen: Rc<Cell<u64>>,
    expected_bind_gen: u64,
    expected_render_gen: u64,
    pic: gtk4::Picture,
    icon_stack: gtk4::Stack,
    cancel: Arc<AtomicBool>,
}

const ALL_GIT_BADGE_CLASSES: [&str; 6] = [
    "alis-git-modified",
    "alis-git-added",
    "alis-git-untracked",
    "alis-git-deleted",
    "alis-git-conflict",
    "alis-git-ignored",
];

fn update_badge_label(lbl: &gtk4::Label, badge: Option<GitBadge>) {
    for cls in ALL_GIT_BADGE_CLASSES {
        lbl.remove_css_class(cls);
    }
    if let Some(b) = badge {
        lbl.set_text(b.short_label());
        lbl.add_css_class(b.css_class());
        lbl.set_tooltip_text(Some(b.description()));
        lbl.set_visible(true);
    } else {
        lbl.set_text("");
        lbl.set_tooltip_text(None);
        lbl.set_visible(false);
    }
}

fn drag_action_from_drop(drop: Option<gdk::Drop>) -> gdk::DragAction {
    let action = drop
        .map(|d| d.actions())
        .unwrap_or(gdk::DragAction::COPY);
    if action.contains(gdk::DragAction::MOVE) && !action.contains(gdk::DragAction::COPY) {
        gdk::DragAction::MOVE
    } else {
        gdk::DragAction::COPY
    }
}

fn point_in_root(widget: &impl IsA<gtk4::Widget>, root: &gtk4::Box, x: f64, y: f64) -> (f64, f64) {
    widget
        .compute_point(root, &gtk4::graphene::Point::new(x as f32, y as f32))
        .map(|pt| (f64::from(pt.x()), f64::from(pt.y())))
        .unwrap_or((x, y))
}

fn event_identity(gesture: &gtk4::GestureClick) -> Option<usize> {
    gesture.current_event().map(|ev| ev.as_ptr() as usize)
}

// ── Public Tab & Pane Types ────────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub struct TabState {
    pub path: PathBuf,
    pub back_stack: Vec<PathBuf>,
    pub forward_stack: Vec<PathBuf>,
}

impl TabState {
    pub fn new(path: PathBuf) -> Self {
        Self {
            path,
            back_stack: Vec::new(),
            forward_stack: Vec::new(),
        }
    }

    pub fn title(&self) -> String {
        if is_trash_dir(&self.path) {
            return "Trash".into();
        }
        if self.path == Path::new("/") {
            return "/".into();
        }
        self.path
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| self.path.to_string_lossy().to_string())
    }
}

pub type ContextMenuCallback = Rc<dyn Fn(gtk4::Widget, f64, f64, Vec<FileEntry>, PathBuf)>;

#[derive(Clone)]
pub struct PaneCallbacks {
    pub on_focus: Rc<dyn Fn()>,
    pub on_state_changed: Rc<dyn Fn()>,
    pub on_selection_changed: Rc<dyn Fn(Vec<FileEntry>)>,
    pub on_context_menu: ContextMenuCallback,
    pub on_drop_files: Rc<dyn Fn(Vec<PathBuf>, PathBuf, gdk::DragAction)>,
    pub on_open_file: Rc<dyn Fn(FileEntry)>,
}

#[derive(Clone)]
pub struct BrowserPane {
    pub root: gtk4::Box,
    pub filter_revealer: gtk4::Revealer,
    pub filter_entry: gtk4::SearchEntry,
    recursive_toggle: gtk4::ToggleButton,
    tab_bar: gtk4::Box,
    view_stack: gtk4::Stack,
    list_store: gio::ListStore,
    selection_model: gtk4::MultiSelection,
    list_scroll: gtk4::ScrolledWindow,
    grid_scroll: gtk4::ScrolledWindow,
    list_view: gtk4::ListView,
    grid_view: gtk4::GridView,
    empty_label: gtk4::Label,
    state: SharedStateRc,
    tabs: Rc<RefCell<Vec<TabState>>>,
    active_tab: Rc<Cell<usize>>,
    entries: Rc<RefCell<Vec<FileEntry>>>,
    visible_entries: Rc<RefCell<Vec<FileEntry>>>,
    git_branch: Rc<RefCell<Option<String>>>,
    cursor_index: Rc<Cell<Option<usize>>>,
    mark_mode: Rc<Cell<bool>>,
    last_render_sig: Rc<Cell<(ViewMode, bool, i32, u8)>>,
    load_gen: Rc<Cell<u64>>,
    render_gen: Rc<Cell<u64>>,
    scroll_gen: Rc<Cell<u64>>,
    needs_layout_scroll: Rc<Cell<bool>>,
    next_thumb_job_id: Rc<Cell<u64>>,
    pending_thumbs: Rc<RefCell<HashMap<u64, PendingThumbTarget>>>,
    thumb_tx: mpsc::Sender<ThumbResult>,
    thumb_rx: Rc<RefCell<mpsc::Receiver<ThumbResult>>>,
    thumb_pump_active: Rc<Cell<bool>>,
    search_cancel: Rc<RefCell<Arc<AtomicBool>>>,
    dir_monitor: Rc<RefCell<Option<gio::FileMonitor>>>,
    last_item_rc_event: Rc<Cell<Option<usize>>>,
    callbacks: PaneCallbacks,
    is_active: Rc<Cell<bool>>,
}

impl BrowserPane {
    pub fn new(initial_dir: PathBuf, state: SharedStateRc, callbacks: PaneCallbacks) -> Self {
        let root = gtk4::Box::new(gtk4::Orientation::Vertical, 0);
        root.add_css_class("alis-pane");
        root.add_css_class("pane-inactive");
        root.set_hexpand(true);
        root.set_vexpand(true);

        // Tab bar
        let tab_bar = gtk4::Box::new(gtk4::Orientation::Horizontal, 4);
        tab_bar.add_css_class("alis-tabbar");
        root.append(&tab_bar);

        // Inline Filter & Recursive Search bar
        let filter_revealer = gtk4::Revealer::new();
        filter_revealer.set_transition_type(gtk4::RevealerTransitionType::SlideDown);
        let filter_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
        filter_box.add_css_class("alis-filter-bar");

        let filter_entry = gtk4::SearchEntry::new();
        filter_entry.set_placeholder_text(Some("Filter folder or toggle Recursive search…"));
        filter_entry.set_hexpand(true);

        let recursive_toggle = gtk4::ToggleButton::with_label("Recursive");
        recursive_toggle.add_css_class("alis-tool-btn");
        recursive_toggle.set_tooltip_text(Some("Search recursively across subfolders"));

        let close_filter_btn = gtk4::Button::from_icon_name("window-close-symbolic");
        close_filter_btn.add_css_class("alis-tool-btn");

        filter_box.append(&filter_entry);
        filter_box.append(&recursive_toggle);
        filter_box.append(&close_filter_btn);
        filter_revealer.set_child(Some(&filter_box));
        root.append(&filter_revealer);

        // List header bar (sortable columns: Name | Modified | Size | Type matching inir-files)
        let list_header = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
        list_header.add_css_class("alis-list-header");
        let col_name = sort_col_btn("Name", true, gtk4::Align::Start);
        let col_mod = sort_col_btn("Modified", false, gtk4::Align::Start);
        col_mod.set_width_request(146);
        let col_size = sort_col_btn("Size", false, gtk4::Align::End);
        col_size.set_width_request(96);
        let col_kind = sort_col_btn("Kind", false, gtk4::Align::Start);
        col_kind.set_width_request(124);
        list_header.append(&col_name);
        list_header.append(&col_mod);
        list_header.append(&col_size);
        list_header.append(&col_kind);

        // Virtualized backing store + multi-selection model
        let list_store = gio::ListStore::new::<FileEntryObject>();
        let selection_model = gtk4::MultiSelection::new(Some(list_store.clone()));

        // Virtualized ListView
        let list_container = gtk4::Box::new(gtk4::Orientation::Vertical, 0);
        list_container.append(&list_header);
        let list_scroll = gtk4::ScrolledWindow::new();
        list_scroll.set_vexpand(true);
        list_scroll.set_hexpand(true);
        let list_view = gtk4::ListView::new(
            None::<gtk4::SelectionModel>,
            None::<gtk4::ListItemFactory>,
        );
        list_view.add_css_class("alis-file-list");
        list_view.set_single_click_activate(false);
        list_view.set_enable_rubberband(false);
        list_scroll.set_child(Some(&list_view));
        list_container.append(&list_scroll);

        // Virtualized GridView
        let grid_scroll = gtk4::ScrolledWindow::new();
        grid_scroll.set_vexpand(true);
        grid_scroll.set_hexpand(true);
        let grid_view = gtk4::GridView::new(
            None::<gtk4::SelectionModel>,
            None::<gtk4::ListItemFactory>,
        );
        grid_view.add_css_class("alis-file-grid");
        grid_view.set_single_click_activate(false);
        grid_view.set_enable_rubberband(false);
        grid_view.set_min_columns(1);
        grid_view.set_max_columns(16);
        grid_scroll.set_child(Some(&grid_view));

        // Empty state (full-area Box so right-click & DnD work anywhere in empty folders)
        let empty_box = gtk4::Box::new(gtk4::Orientation::Vertical, 0);
        empty_box.set_hexpand(true);
        empty_box.set_vexpand(true);
        let empty_label = gtk4::Label::new(Some("This folder is empty"));
        empty_label.add_css_class("alis-subtext");
        empty_label.set_vexpand(true);
        empty_label.set_hexpand(true);
        empty_label.set_valign(gtk4::Align::Center);
        empty_label.set_halign(gtk4::Align::Center);
        empty_box.append(&empty_label);

        let view_stack = gtk4::Stack::new();
        view_stack.set_vexpand(true);
        view_stack.set_hexpand(true);
        view_stack.add_named(&list_container, Some("list"));
        view_stack.add_named(&grid_scroll, Some("grid"));
        view_stack.add_named(&empty_box, Some("empty"));
        root.append(&view_stack);

        let (init_mode, init_thumbs, init_icon_size, init_list_zoom) = {
            let st = state.borrow();
            (
                st.config.view_mode,
                st.config.thumbnails_enabled,
                st.config.grid_icon_size,
                st.config.list_zoom,
            )
        };
        let (thumb_tx, thumb_rx) = mpsc::channel();

        let pane = Self {
            root,
            filter_revealer,
            filter_entry,
            recursive_toggle,
            tab_bar,
            view_stack,
            list_store,
            selection_model,
            list_scroll,
            grid_scroll,
            list_view,
            grid_view,
            empty_label,
            state,
            tabs: Rc::new(RefCell::new(vec![TabState::new(initial_dir)])),
            active_tab: Rc::new(Cell::new(0)),
            entries: Rc::new(RefCell::new(Vec::new())),
            visible_entries: Rc::new(RefCell::new(Vec::new())),
            git_branch: Rc::new(RefCell::new(None)),
            cursor_index: Rc::new(Cell::new(None)),
            mark_mode: Rc::new(Cell::new(false)),
            last_render_sig: Rc::new(Cell::new((
                init_mode,
                init_thumbs,
                init_icon_size,
                init_list_zoom,
            ))),
            load_gen: Rc::new(Cell::new(0)),
            render_gen: Rc::new(Cell::new(0)),
            scroll_gen: Rc::new(Cell::new(0)),
            needs_layout_scroll: Rc::new(Cell::new(false)),
            next_thumb_job_id: Rc::new(Cell::new(0)),
            pending_thumbs: Rc::new(RefCell::new(HashMap::new())),
            thumb_tx,
            thumb_rx: Rc::new(RefCell::new(thumb_rx)),
            thumb_pump_active: Rc::new(Cell::new(false)),
            search_cancel: Rc::new(RefCell::new(Arc::new(AtomicBool::new(false)))),
            dir_monitor: Rc::new(RefCell::new(None)),
            last_item_rc_event: Rc::new(Cell::new(None)),
            callbacks,
            is_active: Rc::new(Cell::new(false)),
        };

        // Install recycling factories on ListView & GridView
        pane.list_view.set_factory(Some(&pane.build_list_factory()));
        pane.grid_view.set_factory(Some(&pane.build_grid_factory()));

        // Clean up in-flight thumbnail requests when the pane widget is destroyed
        {
            let p = pane.clone();
            pane.root.connect_destroy(move |_| {
                p.cancel_all_pending_thumbs();
                p.search_cancel.borrow().store(true, Ordering::Relaxed);
                *p.dir_monitor.borrow_mut() = None;
            });
        }

        // Wire focus tracking on click inside pane
        {
            let p = pane.clone();
            let click = gtk4::GestureClick::new();
            click.set_button(0);
            click.set_propagation_phase(gtk4::PropagationPhase::Capture);
            click.connect_pressed(move |_, _, _, _| {
                (p.callbacks.on_focus)();
            });
            pane.root.add_controller(click);
        }

        // Wire column header sort toggles
        for (btn, field) in [
            (col_name, SortField::Name),
            (col_kind, SortField::Kind),
            (col_size, SortField::Size),
            (col_mod, SortField::Modified),
        ] {
            let p = pane.clone();
            btn.connect_clicked(move |_| p.toggle_sort(field));
        }

        // Wire filter & recursive search
        {
            let p = pane.clone();
            pane.filter_entry.connect_search_changed(move |_| {
                p.apply_filter_or_search();
            });
        }
        {
            let p = pane.clone();
            pane.recursive_toggle.connect_toggled(move |tb| {
                if tb.is_active() {
                    tb.add_css_class("toggled");
                } else {
                    tb.remove_css_class("toggled");
                }
                p.apply_filter_or_search();
            });
        }
        {
            let p = pane.clone();
            close_filter_btn.connect_clicked(move |_| p.hide_filter());
        }

        // Wire activation (double-click / Enter) on ListView and GridView
        {
            let p = pane.clone();
            pane.list_view.connect_activate(move |_, pos| {
                if let Some(obj) = p.list_store.item(pos).and_downcast::<FileEntryObject>()
                    && let Some(entry) = obj.entry()
                {
                    p.activate_entry(entry);
                }
            });
        }
        {
            let p = pane.clone();
            pane.grid_view.connect_activate(move |_, pos| {
                if let Some(obj) = p.list_store.item(pos).and_downcast::<FileEntryObject>()
                    && let Some(entry) = obj.entry()
                {
                    p.activate_entry(entry);
                }
            });
        }

        // Wire unified MultiSelection change notifications
        {
            let p = pane.clone();
            pane.selection_model
                .connect_selection_changed(move |_, _, _| {
                    let indices = p.selected_indices();
                    match indices.len() {
                        0 => p.cursor_index.set(None),
                        1 => p.cursor_index.set(Some(indices[0])),
                        _ => {
                            let cur_valid = p
                                .cursor_index
                                .get()
                                .map(|c| p.selection_model.is_selected(c as u32))
                                .unwrap_or(false);
                            if !cur_valid {
                                p.cursor_index.set(indices.first().copied());
                            }
                        }
                    }
                    (p.callbacks.on_selection_changed)(p.selected_entries());
                });
        }

        // Wire background Right-Click Context Menu & DropTarget on ListView and GridView
        for view_widget in [
            pane.list_view.clone().upcast::<gtk4::Widget>(),
            pane.grid_view.clone().upcast::<gtk4::Widget>(),
        ] {
            {
                let p = pane.clone();
                let vw = view_widget.clone();
                let rc_bg = gtk4::GestureClick::new();
                rc_bg.set_button(gdk::BUTTON_SECONDARY);
                rc_bg.connect_pressed(move |gesture, _, x, y| {
                    if let (Some(prev), Some(cur)) =
                        (p.last_item_rc_event.get(), event_identity(gesture))
                        && prev == cur
                    {
                        return;
                    }
                    (p.callbacks.on_focus)();
                    p.selection_model.unselect_all();
                    p.cursor_index.set(None);
                    let (rx, ry) = point_in_root(&vw, &p.root, x, y);
                    let cur = p.current_dir();
                    (p.callbacks.on_context_menu)(
                        p.root.clone().upcast(),
                        rx,
                        ry,
                        Vec::new(),
                        cur,
                    );
                });
                view_widget.add_controller(rc_bg);
            }

            {
                let p = pane.clone();
                let drop_bg = gtk4::DropTarget::new(
                    gdk::FileList::static_type(),
                    gdk::DragAction::COPY | gdk::DragAction::MOVE,
                );
                drop_bg.connect_drop(move |target, val, _, _| {
                    let Ok(file_list) = val.get::<gdk::FileList>() else {
                        return false;
                    };
                    let paths: Vec<PathBuf> = file_list
                        .files()
                        .into_iter()
                        .filter_map(|f| f.path())
                        .collect();
                    if paths.is_empty() {
                        return false;
                    }
                    let chosen = drag_action_from_drop(target.current_drop());
                    (p.callbacks.on_drop_files)(paths, p.current_dir(), chosen);
                    true
                });
                view_widget.add_controller(drop_bg);
            }
        }

        // Wire Right-Click Context Menu & DropTarget on Empty folder view
        {
            let p = pane.clone();
            let eb = empty_box.clone();
            let rc_empty = gtk4::GestureClick::new();
            rc_empty.set_button(gdk::BUTTON_SECONDARY);
            rc_empty.connect_pressed(move |_, _, x, y| {
                (p.callbacks.on_focus)();
                let (rx, ry) = point_in_root(&eb, &p.root, x, y);
                let cur = p.current_dir();
                (p.callbacks.on_context_menu)(
                    p.root.clone().upcast(),
                    rx,
                    ry,
                    Vec::new(),
                    cur,
                );
            });
            empty_box.add_controller(rc_empty);
        }
        {
            let drop_empty = gtk4::DropTarget::new(
                gdk::FileList::static_type(),
                gdk::DragAction::COPY | gdk::DragAction::MOVE,
            );
            let p = pane.clone();
            drop_empty.connect_drop(move |target, val, _, _| {
                let Ok(file_list) = val.get::<gdk::FileList>() else {
                    return false;
                };
                let paths: Vec<PathBuf> = file_list
                    .files()
                    .into_iter()
                    .filter_map(|f| f.path())
                    .collect();
                if paths.is_empty() {
                    return false;
                }
                let chosen = drag_action_from_drop(target.current_drop());
                (p.callbacks.on_drop_files)(paths, p.current_dir(), chosen);
                true
            });
            empty_box.add_controller(drop_empty);
        }

        pane.rebuild_tabs();
        pane.reload();
        pane
    }

    // ── Virtualized Item Factories (ListView & GridView) ──────────────────────

    fn attach_item_controllers(&self, item_widget: &gtk4::Widget, list_item: &gtk4::ListItem) {
        // Right-click context menu on item (selects hovered unselected item, preserves multi-selection)
        {
            let p = self.clone();
            let iw = item_widget.clone();
            let li_weak = list_item.downgrade();
            let rc = gtk4::GestureClick::new();
            rc.set_button(gdk::BUTTON_SECONDARY);
            rc.connect_pressed(move |gesture, _, x, y| {
                (p.callbacks.on_focus)();
                if let Some(li) = li_weak.upgrade() {
                    let pos = li.position();
                    if pos != gtk4::INVALID_LIST_POSITION {
                        if !p.selection_model.is_selected(pos) {
                            p.selection_model.select_item(pos, true);
                        }
                        p.cursor_index.set(Some(pos as usize));
                    }
                }
                p.last_item_rc_event.set(event_identity(gesture));
                gesture.set_state(gtk4::EventSequenceState::Claimed);
                let (rx, ry) = point_in_root(&iw, &p.root, x, y);
                let sel = p.selected_entries();
                let cur = p.current_dir();
                (p.callbacks.on_context_menu)(p.root.clone().upcast(), rx, ry, sel, cur);
            });
            item_widget.add_controller(rc);
        }

        // Wayland Cross-App DragSource (dragging selected or hovered unselected item)
        {
            let p = self.clone();
            let li_weak = list_item.downgrade();
            let drag = gtk4::DragSource::new();
            drag.set_actions(gdk::DragAction::COPY | gdk::DragAction::MOVE);
            drag.connect_prepare(move |_, _, _| {
                if let Some(li) = li_weak.upgrade() {
                    let pos = li.position();
                    if pos != gtk4::INVALID_LIST_POSITION && !p.selection_model.is_selected(pos) {
                        p.selection_model.select_item(pos, true);
                        p.cursor_index.set(Some(pos as usize));
                    }
                }
                let sel = p.selected_paths();
                if sel.is_empty() {
                    return None;
                }
                let gfiles: Vec<gio::File> = sel.iter().map(gio::File::for_path).collect();
                let file_list = gdk::FileList::from_array(&gfiles);
                let uri_list = crate::dbus::paths_to_uri_list(&sel);
                let p_files = gdk::ContentProvider::for_value(&file_list.to_value());
                let p_uri = gdk::ContentProvider::for_bytes(
                    "text/uri-list",
                    &glib::Bytes::from_owned(uri_list.into_bytes()),
                );
                Some(gdk::ContentProvider::new_union(&[p_files, p_uri]))
            });
            item_widget.add_controller(drag);
        }

        // DropTarget on hovered subfolder row/cell: rejects non-directory items in `accept`
        // so GTK4 propagates the drag up to the parent ListView/GridView background DropTarget.
        {
            let p = self.clone();
            let iw_enter = item_widget.clone();
            let iw_leave = item_widget.clone();
            let iw_drop = item_widget.clone();
            let li_accept = list_item.downgrade();
            let li_enter = list_item.downgrade();
            let li_motion = list_item.downgrade();
            let li_drop = list_item.downgrade();

            let drop = gtk4::DropTarget::new(
                gdk::FileList::static_type(),
                gdk::DragAction::COPY | gdk::DragAction::MOVE,
            );
            drop.connect_accept(move |_, gdk_drop| {
                if !gdk_drop
                    .formats()
                    .contains_type(gdk::FileList::static_type())
                {
                    return false;
                }
                li_accept
                    .upgrade()
                    .and_then(|li| li.item())
                    .and_downcast::<FileEntryObject>()
                    .map(|o| o.is_dir())
                    .unwrap_or(false)
            });
            drop.connect_enter(move |target, _, _| {
                let is_dir = li_enter
                    .upgrade()
                    .and_then(|li| li.item())
                    .and_downcast::<FileEntryObject>()
                    .map(|o| o.is_dir())
                    .unwrap_or(false);
                if is_dir {
                    iw_enter.add_css_class("alis-drop-target");
                    drag_action_from_drop(target.current_drop())
                } else {
                    target.reject();
                    gdk::DragAction::empty()
                }
            });
            drop.connect_motion(move |target, _, _| {
                let is_dir = li_motion
                    .upgrade()
                    .and_then(|li| li.item())
                    .and_downcast::<FileEntryObject>()
                    .map(|o| o.is_dir())
                    .unwrap_or(false);
                if is_dir {
                    drag_action_from_drop(target.current_drop())
                } else {
                    target.reject();
                    gdk::DragAction::empty()
                }
            });
            drop.connect_leave(move |_| {
                iw_leave.remove_css_class("alis-drop-target");
            });
            drop.connect_drop(move |target, val, _, _| {
                iw_drop.remove_css_class("alis-drop-target");
                let Ok(file_list) = val.get::<gdk::FileList>() else {
                    return false;
                };
                let paths: Vec<PathBuf> = file_list
                    .files()
                    .into_iter()
                    .filter_map(|f| f.path())
                    .collect();
                if paths.is_empty() {
                    return false;
                }
                let Some(dest_dir) = li_drop
                    .upgrade()
                    .and_then(|li| li.item())
                    .and_downcast::<FileEntryObject>()
                    .and_then(|o| o.entry())
                    .filter(|e| e.is_dir && !paths.contains(&e.path))
                    .map(|e| e.path)
                else {
                    return false;
                };
                let chosen = drag_action_from_drop(target.current_drop());
                (p.callbacks.on_drop_files)(paths, dest_dir, chosen);
                true
            });
            item_widget.add_controller(drop);
        }
    }

    fn build_list_factory(&self) -> gtk4::SignalListItemFactory {
        let factory = gtk4::SignalListItemFactory::new();
        let registry: Rc<RefCell<HashMap<usize, ListRowWidgets>>> =
            Rc::new(RefCell::new(HashMap::new()));

        {
            let p = self.clone();
            let reg = registry.clone();
            factory.connect_setup(move |_, obj| {
                let Some(list_item) = obj.downcast_ref::<gtk4::ListItem>() else {
                    return;
                };
                let row = gtk4::Box::new(gtk4::Orientation::Horizontal, 10);
                row.add_css_class("alis-list-row-inner");
                row.set_hexpand(true);

                let icon_stack = gtk4::Stack::new();
                icon_stack.set_size_request(24, 24);
                icon_stack.set_valign(gtk4::Align::Center);
                let art_pic = gtk4::Picture::new();
                art_pic.set_size_request(22, 22);
                art_pic.set_content_fit(gtk4::ContentFit::Contain);
                icon_stack.add_named(&art_pic, Some("icon"));
                let thumb_pic = gtk4::Picture::new();
                thumb_pic.set_size_request(22, 22);
                thumb_pic.set_content_fit(gtk4::ContentFit::Cover);
                icon_stack.add_named(&thumb_pic, Some("thumb"));
                icon_stack.set_visible_child_name("icon");
                row.append(&icon_stack);

                let name_lbl = gtk4::Label::new(None);
                name_lbl.set_xalign(0.0);
                name_lbl.set_hexpand(true);
                name_lbl.set_ellipsize(gtk4::pango::EllipsizeMode::Middle);
                row.append(&name_lbl);

                let badge_lbl = gtk4::Label::new(None);
                badge_lbl.add_css_class("alis-git-badge");
                badge_lbl.set_visible(false);
                row.append(&badge_lbl);

                let mod_lbl = gtk4::Label::new(None);
                mod_lbl.add_css_class("alis-subtext");
                mod_lbl.set_width_request(146);
                mod_lbl.set_xalign(0.0);
                row.append(&mod_lbl);

                let size_lbl = gtk4::Label::new(None);
                size_lbl.add_css_class("alis-subtext");
                size_lbl.set_width_request(96);
                size_lbl.set_xalign(1.0);
                row.append(&size_lbl);

                let kind_lbl = gtk4::Label::new(None);
                kind_lbl.add_css_class("alis-subtext");
                kind_lbl.set_width_request(124);
                kind_lbl.set_xalign(0.0);
                kind_lbl.set_ellipsize(gtk4::pango::EllipsizeMode::End);
                row.append(&kind_lbl);

                p.attach_item_controllers(row.upcast_ref(), list_item);
                list_item.set_child(Some(&row));

                let key = list_item.as_ptr() as usize;
                reg.borrow_mut().insert(
                    key,
                    ListRowWidgets {
                        row,
                        icon_stack,
                        art_pic,
                        thumb_pic,
                        name_lbl,
                        badge_lbl,
                        kind_lbl,
                        size_lbl,
                        mod_lbl,
                        bind_gen: Rc::new(Cell::new(0)),
                        thumb_slot: Rc::new(RefCell::new(None)),
                        badge_conn: Rc::new(RefCell::new(None)),
                    },
                );
            });
        }

        {
            let p = self.clone();
            let reg = registry.clone();
            factory.connect_bind(move |_, obj| {
                let Some(list_item) = obj.downcast_ref::<gtk4::ListItem>() else {
                    return;
                };
                let Some(entry_obj) = list_item.item().and_downcast::<FileEntryObject>() else {
                    return;
                };
                let Some(entry) = entry_obj.entry() else {
                    return;
                };
                let key = list_item.as_ptr() as usize;
                let reg_borrow = reg.borrow();
                let Some(w) = reg_borrow.get(&key) else {
                    return;
                };

                p.cancel_item_thumb(&w.thumb_slot);
                if let Some((prev_obj, sig_id)) = w.badge_conn.borrow_mut().take() {
                    prev_obj.disconnect(sig_id);
                }
                let next_gen = w.bind_gen.get().wrapping_add(1);
                w.bind_gen.set(next_gen);

                let (thumbs_enabled, list_zoom, is_cut) = {
                    let st = p.state.borrow();
                    (
                        st.config.thumbnails_enabled,
                        st.config.list_zoom.min(2),
                        st.is_cut_path(&entry.path),
                    )
                };
                let (row_h, icon_px) = match list_zoom {
                    0 => (28, 18),
                    2 => (46, 32),
                    _ => (34, 22),
                };

                w.row.remove_css_class("alis-drop-target");
                if is_cut {
                    w.row.add_css_class("alis-item-cut");
                } else {
                    w.row.remove_css_class("alis-item-cut");
                }
                w.row.set_size_request(-1, row_h);
                w.icon_stack.set_size_request(icon_px + 2, icon_px + 2);
                w.art_pic.set_size_request(icon_px, icon_px);
                w.thumb_pic.set_size_request(icon_px, icon_px);
                w.art_pic.set_paintable(
                    crate::ui::file_art::texture_for_entry(&entry, icon_px).as_ref(),
                );
                w.thumb_pic.set_paintable(None::<&gdk::Paintable>);
                w.icon_stack.set_visible_child_name("icon");
                w.name_lbl.set_text(&entry.name);
                w.name_lbl.set_opacity(if entry.is_hidden { 0.62 } else { 1.0 });
                w.kind_lbl.set_text(entry.kind_label());
                w.size_lbl.set_text(&if entry.is_dir {
                    "—".into()
                } else {
                    format_size(entry.size)
                });
                w.mod_lbl.set_text(&format_time(entry.modified));

                update_badge_label(&w.badge_lbl, entry.git_badge);
                let badge_lbl_clone = w.badge_lbl.clone();
                let sig_id = entry_obj.connect_badge_changed(move |eo| {
                    update_badge_label(&badge_lbl_clone, eo.git_badge());
                });
                *w.badge_conn.borrow_mut() = Some((entry_obj, sig_id));

                if thumbs_enabled && matches!(entry.kind, FileKind::Image | FileKind::Video) {
                    p.request_item_thumbnail(
                        &entry,
                        48,
                        w.bind_gen.clone(),
                        next_gen,
                        w.thumb_pic.clone(),
                        w.icon_stack.clone(),
                        &w.thumb_slot,
                    );
                }
            });
        }

        {
            let p = self.clone();
            let reg = registry.clone();
            factory.connect_unbind(move |_, obj| {
                let Some(list_item) = obj.downcast_ref::<gtk4::ListItem>() else {
                    return;
                };
                let key = list_item.as_ptr() as usize;
                if let Some(w) = reg.borrow().get(&key) {
                    w.bind_gen.set(w.bind_gen.get().wrapping_add(1));
                    p.cancel_item_thumb(&w.thumb_slot);
                    if let Some((prev_obj, sig_id)) = w.badge_conn.borrow_mut().take() {
                        prev_obj.disconnect(sig_id);
                    }
                    w.row.remove_css_class("alis-drop-target");
                    w.thumb_pic.set_paintable(None::<&gdk::Paintable>);
                    w.icon_stack.set_visible_child_name("icon");
                }
            });
        }

        {
            let p = self.clone();
            let reg = registry.clone();
            factory.connect_teardown(move |_, obj| {
                let Some(list_item) = obj.downcast_ref::<gtk4::ListItem>() else {
                    return;
                };
                let key = list_item.as_ptr() as usize;
                if let Some(w) = reg.borrow_mut().remove(&key) {
                    p.cancel_item_thumb(&w.thumb_slot);
                    if let Some((prev_obj, sig_id)) = w.badge_conn.borrow_mut().take() {
                        prev_obj.disconnect(sig_id);
                    }
                }
            });
        }

        factory
    }

    fn build_grid_factory(&self) -> gtk4::SignalListItemFactory {
        let factory = gtk4::SignalListItemFactory::new();
        let registry: Rc<RefCell<HashMap<usize, GridCardWidgets>>> =
            Rc::new(RefCell::new(HashMap::new()));

        {
            let p = self.clone();
            let reg = registry.clone();
            factory.connect_setup(move |_, obj| {
                let Some(list_item) = obj.downcast_ref::<gtk4::ListItem>() else {
                    return;
                };
                let card = gtk4::Box::new(gtk4::Orientation::Vertical, 4);
                card.set_hexpand(true);
                card.set_vexpand(true);
                card.set_halign(gtk4::Align::Fill);
                card.set_valign(gtk4::Align::Fill);

                let plate_overlay = gtk4::Overlay::new();
                plate_overlay.set_halign(gtk4::Align::Center);
                let plate_box = gtk4::Box::new(gtk4::Orientation::Vertical, 0);
                plate_box.add_css_class("alis-grid-plate");
                plate_box.set_overflow(gtk4::Overflow::Hidden);
                plate_box.set_halign(gtk4::Align::Center);

                let icon_stack = gtk4::Stack::new();
                icon_stack.set_hexpand(true);
                icon_stack.set_vexpand(true);

                // Art fallback (includes optional inner label in Gallery mode for non-media items)
                let art_inner_box = gtk4::Box::new(gtk4::Orientation::Vertical, 4);
                art_inner_box.set_valign(gtk4::Align::Center);
                art_inner_box.set_halign(gtk4::Align::Center);
                let art_pic = gtk4::Picture::new();
                art_pic.set_halign(gtk4::Align::Center);
                art_pic.set_valign(gtk4::Align::Center);
                art_pic.set_content_fit(gtk4::ContentFit::Contain);
                let tile_inner_name = gtk4::Label::new(None);
                tile_inner_name.set_max_width_chars(14);
                tile_inner_name.set_lines(2);
                tile_inner_name.set_wrap(true);
                tile_inner_name.set_wrap_mode(gtk4::pango::WrapMode::WordChar);
                tile_inner_name.set_ellipsize(gtk4::pango::EllipsizeMode::End);
                tile_inner_name.set_justify(gtk4::Justification::Center);
                tile_inner_name.set_visible(false);
                art_inner_box.append(&art_pic);
                art_inner_box.append(&tile_inner_name);
                icon_stack.add_named(&art_inner_box, Some("icon"));

                let thumb_pic = gtk4::Picture::new();
                thumb_pic.set_can_shrink(true);
                thumb_pic.set_content_fit(gtk4::ContentFit::Contain);
                icon_stack.add_named(&thumb_pic, Some("thumb"));
                icon_stack.set_visible_child_name("icon");

                plate_box.append(&icon_stack);
                plate_overlay.set_child(Some(&plate_box));

                let badge_lbl = gtk4::Label::new(None);
                badge_lbl.add_css_class("alis-git-badge");
                badge_lbl.set_halign(gtk4::Align::End);
                badge_lbl.set_valign(gtk4::Align::Start);
                badge_lbl.set_margin_top(6);
                badge_lbl.set_margin_end(6);
                badge_lbl.set_visible(false);
                plate_overlay.add_overlay(&badge_lbl);

                let video_lbl = gtk4::Label::new(Some("▶"));
                video_lbl.add_css_class("alis-video-badge");
                video_lbl.set_halign(gtk4::Align::Start);
                video_lbl.set_valign(gtk4::Align::End);
                video_lbl.set_margin_bottom(6);
                video_lbl.set_margin_start(6);
                video_lbl.set_visible(false);
                plate_overlay.add_overlay(&video_lbl);

                let gallery_ring = gtk4::Label::new(Some("✓"));
                gallery_ring.add_css_class("alis-gallery-ring");
                gallery_ring.set_halign(gtk4::Align::Start);
                gallery_ring.set_valign(gtk4::Align::Start);
                gallery_ring.set_margin_top(6);
                gallery_ring.set_margin_start(6);
                gallery_ring.set_visible(false);
                plate_overlay.add_overlay(&gallery_ring);

                card.append(&plate_overlay);

                let name_pill = gtk4::Box::new(gtk4::Orientation::Horizontal, 0);
                name_pill.add_css_class("alis-grid-pill");
                name_pill.set_halign(gtk4::Align::Center);
                let name_lbl = gtk4::Label::new(None);
                name_lbl.set_halign(gtk4::Align::Center);
                name_lbl.set_max_width_chars(15);
                name_lbl.set_lines(2);
                name_lbl.set_wrap(true);
                name_lbl.set_wrap_mode(gtk4::pango::WrapMode::WordChar);
                name_lbl.set_ellipsize(gtk4::pango::EllipsizeMode::End);
                name_lbl.set_justify(gtk4::Justification::Center);
                name_pill.append(&name_lbl);
                card.append(&name_pill);

                p.attach_item_controllers(card.upcast_ref(), list_item);
                list_item.set_child(Some(&card));

                let key = list_item.as_ptr() as usize;
                reg.borrow_mut().insert(
                    key,
                    GridCardWidgets {
                        card,
                        plate_overlay,
                        plate_box,
                        icon_stack,
                        art_inner_box,
                        art_pic,
                        tile_inner_name,
                        thumb_pic,
                        badge_lbl,
                        video_lbl,
                        gallery_ring,
                        name_pill,
                        name_lbl,
                        bind_gen: Rc::new(Cell::new(0)),
                        thumb_slot: Rc::new(RefCell::new(None)),
                        badge_conn: Rc::new(RefCell::new(None)),
                    },
                );
            });
        }

        {
            let p = self.clone();
            let reg = registry.clone();
            factory.connect_bind(move |_, obj| {
                let Some(list_item) = obj.downcast_ref::<gtk4::ListItem>() else {
                    return;
                };
                let Some(entry_obj) = list_item.item().and_downcast::<FileEntryObject>() else {
                    return;
                };
                let Some(entry) = entry_obj.entry() else {
                    return;
                };
                let key = list_item.as_ptr() as usize;
                let reg_borrow = reg.borrow();
                let Some(w) = reg_borrow.get(&key) else {
                    return;
                };

                p.cancel_item_thumb(&w.thumb_slot);
                if let Some((prev_obj, sig_id)) = w.badge_conn.borrow_mut().take() {
                    prev_obj.disconnect(sig_id);
                }
                let next_gen = w.bind_gen.get().wrapping_add(1);
                w.bind_gen.set(next_gen);

                let (view_mode, thumbs_enabled, icon_size, is_cut) = {
                    let st = p.state.borrow();
                    (
                        st.config.view_mode,
                        st.config.thumbnails_enabled,
                        st.config.grid_icon_size,
                        st.is_cut_path(&entry.path),
                    )
                };
                let is_gallery = view_mode == ViewMode::Gallery;
                let is_media = thumbs_enabled
                    && matches!(entry.kind, FileKind::Image | FileKind::Pdf | FileKind::Video);

                w.card.remove_css_class("alis-drop-target");
                if is_cut {
                    w.card.add_css_class("alis-item-cut");
                } else {
                    w.card.remove_css_class("alis-item-cut");
                }
                w.plate_box.remove_css_class("alis-grid-plate");
                w.plate_box.remove_css_class("alis-gallery-tile");

                if is_gallery {
                    let side = (icon_size + 36).clamp(80, 260);
                    w.card.set_size_request(side + 4, side + 4);
                    w.plate_overlay.set_size_request(side, side);
                    w.plate_box.set_size_request(side, side);
                    w.plate_box.add_css_class("alis-gallery-tile");
                    w.thumb_pic.set_content_fit(gtk4::ContentFit::Cover);
                    let art_sz = (side as f64 * 0.44).round() as i32;
                    w.art_pic.set_size_request(art_sz, art_sz);
                    w.art_pic.set_paintable(
                        crate::ui::file_art::texture_for_entry(&entry, art_sz).as_ref(),
                    );
                    w.tile_inner_name.set_text(&entry.name);
                    w.tile_inner_name.set_visible(!is_media);
                    w.gallery_ring.set_visible(true);
                    w.name_pill.set_visible(false);
                } else {
                    let plate_sz = icon_size + 18;
                    let cell_w = (icon_size + 46).max(106);
                    w.card.set_size_request(cell_w, icon_size + 62);
                    w.plate_overlay.set_size_request(plate_sz, plate_sz);
                    w.plate_box.set_size_request(plate_sz, plate_sz);
                    w.plate_box.add_css_class("alis-grid-plate");
                    w.thumb_pic.set_content_fit(gtk4::ContentFit::Contain);
                    w.art_pic.set_size_request(icon_size, icon_size);
                    w.art_pic.set_paintable(
                        crate::ui::file_art::texture_for_entry(&entry, icon_size).as_ref(),
                    );
                    w.tile_inner_name.set_visible(false);
                    w.gallery_ring.set_visible(false);
                    w.name_pill.set_visible(true);
                    w.name_lbl.set_text(&entry.name);
                    w.name_lbl.set_opacity(if entry.is_hidden { 0.62 } else { 1.0 });
                }

                w.art_inner_box
                    .set_opacity(if entry.is_hidden { 0.62 } else { 1.0 });
                w.thumb_pic.set_paintable(None::<&gdk::Paintable>);
                w.icon_stack.set_visible_child_name("icon");
                w.video_lbl.set_visible(thumbs_enabled && entry.kind == FileKind::Video);

                update_badge_label(&w.badge_lbl, entry.git_badge);
                let badge_lbl_clone = w.badge_lbl.clone();
                let sig_id = entry_obj.connect_badge_changed(move |eo| {
                    update_badge_label(&badge_lbl_clone, eo.git_badge());
                });
                *w.badge_conn.borrow_mut() = Some((entry_obj, sig_id));

                if is_media {
                    let max_dim = ((icon_size + 24) * 2).clamp(128, 384);
                    p.request_item_thumbnail(
                        &entry,
                        max_dim,
                        w.bind_gen.clone(),
                        next_gen,
                        w.thumb_pic.clone(),
                        w.icon_stack.clone(),
                        &w.thumb_slot,
                    );
                }
            });
        }

        {
            let p = self.clone();
            let reg = registry.clone();
            factory.connect_unbind(move |_, obj| {
                let Some(list_item) = obj.downcast_ref::<gtk4::ListItem>() else {
                    return;
                };
                let key = list_item.as_ptr() as usize;
                if let Some(w) = reg.borrow().get(&key) {
                    w.bind_gen.set(w.bind_gen.get().wrapping_add(1));
                    p.cancel_item_thumb(&w.thumb_slot);
                    if let Some((prev_obj, sig_id)) = w.badge_conn.borrow_mut().take() {
                        prev_obj.disconnect(sig_id);
                    }
                    w.card.remove_css_class("alis-drop-target");
                    w.thumb_pic.set_paintable(None::<&gdk::Paintable>);
                    w.icon_stack.set_visible_child_name("icon");
                }
            });
        }

        {
            let p = self.clone();
            let reg = registry.clone();
            factory.connect_teardown(move |_, obj| {
                let Some(list_item) = obj.downcast_ref::<gtk4::ListItem>() else {
                    return;
                };
                let key = list_item.as_ptr() as usize;
                if let Some(w) = reg.borrow_mut().remove(&key) {
                    p.cancel_item_thumb(&w.thumb_slot);
                    if let Some((prev_obj, sig_id)) = w.badge_conn.borrow_mut().take() {
                        prev_obj.disconnect(sig_id);
                    }
                }
            });
        }

        factory
    }

    // ── On-Demand Parallel Thumbnail Pipeline + LRU Texture Cache ─────────────

    fn cancel_item_thumb(&self, slot: &ThumbSlot) {
        if let Some((job_id, cancel)) = slot.borrow_mut().take() {
            cancel.store(true, Ordering::Relaxed);
            self.pending_thumbs.borrow_mut().remove(&job_id);
        }
    }

    fn cancel_all_pending_thumbs(&self) {
        self.render_gen.set(self.render_gen.get().wrapping_add(1));
        for (_, target) in self.pending_thumbs.borrow_mut().drain() {
            target.cancel.store(true, Ordering::Relaxed);
        }
        let rx = self.thumb_rx.borrow();
        while rx.try_recv().is_ok() {}
    }

    #[allow(clippy::too_many_arguments)]
    fn request_item_thumbnail(
        &self,
        entry: &FileEntry,
        max_dim: i32,
        bind_gen: Rc<Cell<u64>>,
        expected_bind_gen: u64,
        pic: gtk4::Picture,
        icon_stack: gtk4::Stack,
        slot: &ThumbSlot,
    ) {
        let key = ThumbCacheKey {
            path: entry.path.clone(),
            max_dim,
            size: entry.size,
            modified: entry.modified,
        };

        // Fast path: synchronous in-memory LRU hit (0ms, zero flicker on scroll)
        if let Some(tex) = self.state.borrow_mut().thumb_cache.get(&key).cloned() {
            pic.set_paintable(Some(&tex));
            icon_stack.set_visible_child_name("thumb");
            return;
        }

        let job_id = self.next_thumb_job_id.get().wrapping_add(1);
        self.next_thumb_job_id.set(job_id);
        let cancel = Arc::new(AtomicBool::new(false));
        *slot.borrow_mut() = Some((job_id, cancel.clone()));

        self.pending_thumbs.borrow_mut().insert(
            job_id,
            PendingThumbTarget {
                bind_gen,
                expected_bind_gen,
                expected_render_gen: self.render_gen.get(),
                pic,
                icon_stack,
                cancel: cancel.clone(),
            },
        );

        ThumbWorkerPool::global().submit(ThumbJob {
            job_id,
            key,
            kind: entry.kind,
            cancel,
            tx: self.thumb_tx.clone(),
        });

        self.ensure_thumb_pump();
    }

    fn ensure_thumb_pump(&self) {
        if self.thumb_pump_active.get() {
            return;
        }
        self.thumb_pump_active.set(true);
        let p = self.clone();
        glib::timeout_add_local(std::time::Duration::from_millis(16), move || {
            let mut applied = 0usize;
            let mut drained = 0usize;
            while applied < 8 && drained < 256 {
                let recv_res = p.thumb_rx.borrow().try_recv();
                match recv_res {
                    Ok(res) => {
                        drained += 1;
                        let target = p.pending_thumbs.borrow_mut().remove(&res.job_id);
                        if let Some(target) = target
                            && !target.cancel.load(Ordering::Relaxed)
                            && target.bind_gen.get() == target.expected_bind_gen
                            && p.render_gen.get() == target.expected_render_gen
                            && let Some(png_path) = res.png_path
                        {
                            let cached = p
                                .state
                                .borrow_mut()
                                .thumb_cache
                                .get(&res.key)
                                .cloned();
                            let tex = cached.or_else(|| {
                                let loaded =
                                    crate::thumbnails::load_texture_from_path(&png_path)?;
                                p.state
                                    .borrow_mut()
                                    .thumb_cache
                                    .insert(res.key, loaded.clone());
                                Some(loaded)
                            });
                            if let Some(tex) = tex {
                                target.pic.set_paintable(Some(&tex));
                                target.icon_stack.set_visible_child_name("thumb");
                                applied += 1;
                            }
                        }
                    }
                    Err(mpsc::TryRecvError::Empty) => break,
                    Err(mpsc::TryRecvError::Disconnected) => {
                        p.thumb_pump_active.set(false);
                        return glib::ControlFlow::Break;
                    }
                }
            }
            if p.pending_thumbs.borrow().is_empty() {
                p.thumb_pump_active.set(false);
                glib::ControlFlow::Break
            } else {
                glib::ControlFlow::Continue
            }
        });
    }

    // ── Public Pane API ───────────────────────────────────────────────────────

    pub fn set_active(&self, active: bool) {
        self.is_active.set(active);
        if active {
            self.root.remove_css_class("pane-inactive");
            self.root.add_css_class("pane-active");
        } else {
            self.root.remove_css_class("pane-active");
            self.root.add_css_class("pane-inactive");
        }
    }

    pub fn current_dir(&self) -> PathBuf {
        let tabs = self.tabs.borrow();
        let idx = self.active_tab.get().min(tabs.len().saturating_sub(1));
        tabs[idx].path.clone()
    }

    pub fn git_branch(&self) -> Option<String> {
        self.git_branch.borrow().clone()
    }

    pub fn can_go_back(&self) -> bool {
        let tabs = self.tabs.borrow();
        let idx = self.active_tab.get().min(tabs.len().saturating_sub(1));
        !tabs[idx].back_stack.is_empty()
    }

    pub fn can_go_forward(&self) -> bool {
        let tabs = self.tabs.borrow();
        let idx = self.active_tab.get().min(tabs.len().saturating_sub(1));
        !tabs[idx].forward_stack.is_empty()
    }

    pub fn navigate_to(&self, dir: PathBuf) {
        let target = if dir.is_dir() {
            dir
        } else if is_trash_dir(&dir) {
            let _ = std::fs::create_dir_all(&dir);
            dir
        } else {
            return;
        };
        {
            let mut tabs = self.tabs.borrow_mut();
            let idx = self.active_tab.get().min(tabs.len().saturating_sub(1));
            if tabs[idx].path != target {
                let prev = tabs[idx].path.clone();
                tabs[idx].back_stack.push(prev);
                tabs[idx].forward_stack.clear();
                tabs[idx].path = target.clone();
            }
        }
        {
            let mut st = self.state.borrow_mut();
            st.config.push_recent(&target);
            let _ = st.config.save();
        }
        self.filter_entry.set_text("");
        self.recursive_toggle.set_active(false);
        self.filter_revealer.set_reveal_child(false);
        self.rebuild_tabs();
        self.reload();
        (self.callbacks.on_state_changed)();
    }

    pub fn go_back(&self) {
        let changed = {
            let mut tabs = self.tabs.borrow_mut();
            let idx = self.active_tab.get().min(tabs.len().saturating_sub(1));
            if let Some(prev) = tabs[idx].back_stack.pop() {
                let cur = tabs[idx].path.clone();
                tabs[idx].forward_stack.push(cur);
                tabs[idx].path = prev;
                true
            } else {
                false
            }
        };
        if changed {
            self.rebuild_tabs();
            self.reload();
            (self.callbacks.on_state_changed)();
        }
    }

    pub fn go_forward(&self) {
        let changed = {
            let mut tabs = self.tabs.borrow_mut();
            let idx = self.active_tab.get().min(tabs.len().saturating_sub(1));
            if let Some(next) = tabs[idx].forward_stack.pop() {
                let cur = tabs[idx].path.clone();
                tabs[idx].back_stack.push(cur);
                tabs[idx].path = next;
                true
            } else {
                false
            }
        };
        if changed {
            self.rebuild_tabs();
            self.reload();
            (self.callbacks.on_state_changed)();
        }
    }

    pub fn go_parent(&self) {
        let cur = self.current_dir();
        if let Some(parent) = cur.parent() {
            self.navigate_to(parent.to_path_buf());
        }
    }

    pub fn open_new_tab(&self, path: PathBuf) {
        self.apply_tab_state(TabState::new(path), true);
        (self.callbacks.on_state_changed)();
    }

    pub fn current_tab_state(&self) -> TabState {
        let tabs = self.tabs.borrow();
        let active = self.active_tab.get().min(tabs.len().saturating_sub(1));
        tabs[active].clone()
    }

    pub fn apply_tab_state(&self, tab: TabState, clear_selection_if_changed: bool) {
        let prev_dir = self.current_dir();
        let changed = prev_dir != tab.path;
        *self.tabs.borrow_mut() = vec![tab];
        self.active_tab.set(0);
        self.rebuild_tabs();
        if changed {
            self.filter_entry.set_text("");
            self.recursive_toggle.set_active(false);
            self.filter_revealer.set_reveal_child(false);
            if clear_selection_if_changed {
                self.mark_mode.set(false);
                self.selection_model.unselect_all();
                self.cursor_index.set(None);
            }
            self.reload();
        }
    }

    pub fn visible_entries_snapshot(&self) -> Vec<FileEntry> {
        self.visible_entries.borrow().clone()
    }

    fn rebuild_tabs(&self) {
        // Unified TabStrip in AlisFilesWindow owns tab presentation matching inir-files.
        self.tab_bar.set_visible(false);
    }

    pub fn show_filter(&self) {
        self.filter_revealer.set_reveal_child(true);
        self.filter_entry.grab_focus();
    }

    pub fn hide_filter(&self) {
        self.search_cancel.borrow().store(true, Ordering::Relaxed);
        self.filter_entry.set_text("");
        self.recursive_toggle.set_active(false);
        self.filter_revealer.set_reveal_child(false);
        self.apply_filter_or_search();
    }

    pub fn toggle_sort(&self, field: SortField) {
        {
            let mut st = self.state.borrow_mut();
            if st.config.sort_field == field {
                st.config.sort_order = match st.config.sort_order {
                    SortOrder::Asc => SortOrder::Desc,
                    SortOrder::Desc => SortOrder::Asc,
                };
            } else {
                st.config.sort_field = field;
                st.config.sort_order = SortOrder::Asc;
            }
            let _ = st.config.save();
        }
        self.render_entries();
    }

    pub fn reload(&self) {
        self.reload_and_select(None);
    }

    fn reload_preserving_selection(&self) {
        let prev_selected = self.selected_paths();
        let active_vadj = match self.state.borrow().config.view_mode {
            ViewMode::List => self.list_scroll.vadjustment(),
            ViewMode::Grid | ViewMode::Gallery => self.grid_scroll.vadjustment(),
        };
        let saved_scroll = active_vadj.value();
        let expected_dir = self.current_dir();
        self.reload_and_select(None);
        if !prev_selected.is_empty() {
            self.select_paths(&prev_selected);
        }
        if saved_scroll > 0.0 {
            let p = self.clone();
            glib::idle_add_local_once(move || {
                if p.current_dir() == expected_dir {
                    let vadj = match p.state.borrow().config.view_mode {
                        ViewMode::List => p.list_scroll.vadjustment(),
                        ViewMode::Grid | ViewMode::Gallery => p.grid_scroll.vadjustment(),
                    };
                    let max_val = (vadj.upper() - vadj.page_size()).max(0.0);
                    vadj.set_value(saved_scroll.min(max_val));
                }
            });
        }
    }

    pub fn reload_and_select(&self, select_target: Option<PathBuf>) {
        self.mark_mode.set(false);
        let mut dir = self.current_dir();
        let (show_hidden, git_badges_enabled) = {
            let st = self.state.borrow();
            (st.config.show_hidden, st.config.git_badges)
        };
        let seq = self.load_gen.get().wrapping_add(1);
        self.load_gen.set(seq);

        // Recover gracefully if the open folder was deleted or unmounted while open.
        if !is_trash_dir(&dir) && !dir.is_dir() {
            let fallback = dir
                .ancestors()
                .find(|a| a.is_dir())
                .map(Path::to_path_buf)
                .unwrap_or_else(crate::config::home_dir);
            if fallback != dir {
                let mut tabs = self.tabs.borrow_mut();
                let idx = self.active_tab.get().min(tabs.len().saturating_sub(1));
                tabs[idx].path = fallback.clone();
                dir = fallback;
                drop(tabs);
                (self.callbacks.on_state_changed)();
            }
        }

        // Install directory monitor so external changes refresh automatically
        self.watch_directory(&dir);

        let (dir_opened, entry_paths_for_git) = match read_directory(&dir, show_hidden) {
            Ok(items) => {
                let paths: Vec<PathBuf> = items.iter().map(|e| e.path.clone()).collect();
                *self.entries.borrow_mut() = items;
                *self.git_branch.borrow_mut() = None;
                self.apply_filter_or_search();
                if let Some(target) = select_target {
                    self.select_path(&target);
                }
                (true, paths)
            }
            Err(err) => {
                self.cancel_all_pending_thumbs();
                self.entries.borrow_mut().clear();
                self.visible_entries.borrow_mut().clear();
                self.list_store.remove_all();
                self.cursor_index.set(None);
                self.empty_label
                    .set_text(&format!("Cannot open folder: {err}"));
                self.view_stack.set_visible_child_name("empty");
                (false, Vec::new())
            }
        };

        // Async Git status badge & branch lookup: path resolution happens off-thread,
        // and UI badges update in-place via FileEntryObject signals (no widget rebuild, no flicker).
        if dir_opened && git_badges_enabled && !is_trash_dir(&dir) {
            let dir_bg = dir.clone();
            let pane_ui = self.clone();
            let (tx, rx) = mpsc::channel();
            std::thread::spawn(move || {
                let resolved = resolve_git_badges_background(&dir_bg, &entry_paths_for_git);
                let _ = tx.send(resolved);
            });
            glib::timeout_add_local(std::time::Duration::from_millis(40), move || {
                if pane_ui.load_gen.get() != seq {
                    return glib::ControlFlow::Break;
                }
                match rx.try_recv() {
                    Ok((branch, matched_badges)) => {
                        *pane_ui.git_branch.borrow_mut() = branch;
                        if !matched_badges.is_empty() {
                            let mut entries = pane_ui.entries.borrow_mut();
                            let mut visible = pane_ui.visible_entries.borrow_mut();
                            apply_git_badges_in_place(
                                &mut entries,
                                &mut visible,
                                &pane_ui.list_store,
                                &matched_badges,
                            );
                        }
                        (pane_ui.callbacks.on_state_changed)();
                        glib::ControlFlow::Break
                    }
                    Err(mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
                    Err(mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                }
            });
        }
    }

    fn watch_directory(&self, dir: &Path) {
        *self.dir_monitor.borrow_mut() = None;
        let gdir = gio::File::for_path(dir);
        if let Ok(mon) = gdir.monitor_directory(gio::FileMonitorFlags::NONE, gio::Cancellable::NONE)
        {
            let pane_weak = self.clone();
            let pending = Rc::new(Cell::new(false));
            let watched_dir = dir.to_path_buf();
            mon.connect_changed(move |_, _, _, event| {
                if !matches!(
                    event,
                    gio::FileMonitorEvent::Created
                        | gio::FileMonitorEvent::Deleted
                        | gio::FileMonitorEvent::MovedIn
                        | gio::FileMonitorEvent::MovedOut
                        | gio::FileMonitorEvent::Renamed
                ) {
                    return;
                }
                if pending.get() {
                    return;
                }
                pending.set(true);
                let p = pane_weak.clone();
                let pend = pending.clone();
                let wd = watched_dir.clone();
                glib::timeout_add_local_once(std::time::Duration::from_millis(220), move || {
                    pend.set(false);
                    if p.current_dir() == wd && !p.recursive_toggle.is_active() {
                        p.reload_preserving_selection();
                    }
                });
            });
            *self.dir_monitor.borrow_mut() = Some(mon);
        }
    }

    fn sort_config(&self) -> (SortField, SortOrder, bool) {
        let st = self.state.borrow();
        (
            st.config.sort_field,
            st.config.sort_order,
            st.config.directories_first,
        )
    }

    pub fn apply_filter_or_search(&self) {
        let query = self.filter_entry.text().to_string();
        let recursive = self.recursive_toggle.is_active();
        self.search_cancel.borrow().store(true, Ordering::Relaxed);

        if recursive && !query.trim().is_empty() {
            let cancel = Arc::new(AtomicBool::new(false));
            *self.search_cancel.borrow_mut() = cancel.clone();
            let dir = self.current_dir();
            let hidden = self.state.borrow().config.show_hidden;
            let q = query.clone();
            let pane_ui = self.clone();
            let (tx, rx) = mpsc::channel();
            std::thread::spawn(move || {
                let hits = crate::search::recursive_search(&dir, &q, hidden, 400, &cancel);
                let _ = tx.send(hits);
            });
            let cancel_check = self.search_cancel.borrow().clone();
            glib::timeout_add_local(std::time::Duration::from_millis(40), move || {
                if cancel_check.load(Ordering::Relaxed) {
                    return glib::ControlFlow::Break;
                }
                match rx.try_recv() {
                    Ok(mut hits) => {
                        let (field, order, dirs_first) = pane_ui.sort_config();
                        sort_entries(&mut hits, field, order, dirs_first);
                        *pane_ui.visible_entries.borrow_mut() = hits;
                        pane_ui.render_visible_list();
                        glib::ControlFlow::Break
                    }
                    Err(mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
                    Err(mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                }
            });
            return;
        }

        let q_lower = query.trim().to_lowercase();
        let mut filtered: Vec<FileEntry> = self
            .entries
            .borrow()
            .iter()
            .filter(|e| q_lower.is_empty() || e.name.to_lowercase().contains(&q_lower))
            .cloned()
            .collect();

        let (field, order, dirs_first) = self.sort_config();
        sort_entries(&mut filtered, field, order, dirs_first);
        *self.visible_entries.borrow_mut() = filtered;
        self.render_visible_list();
    }

    pub fn render_entries(&self) {
        let prev_selected = self.selected_paths();
        let query = self.filter_entry.text().to_string();
        if self.recursive_toggle.is_active() && !query.trim().is_empty() {
            // Re-sort and re-render current recursive hits in place without re-crawling disk.
            let (field, order, dirs_first) = self.sort_config();
            {
                let mut vis = self.visible_entries.borrow_mut();
                sort_entries(&mut vis, field, order, dirs_first);
            }
            self.render_visible_list();
        } else {
            self.apply_filter_or_search();
        }
        if !prev_selected.is_empty() {
            self.select_paths(&prev_selected);
        }
    }

    fn render_visible_list(&self) {
        let items = self.visible_entries.borrow().clone();
        let sig = {
            let st = self.state.borrow();
            (
                st.config.view_mode,
                st.config.thumbnails_enabled,
                st.config.grid_icon_size,
                st.config.list_zoom,
            )
        };
        let (view_mode, _, _, _) = sig;
        let prev_sig = self.last_render_sig.replace(sig);

        self.cancel_all_pending_thumbs();
        self.cursor_index.set(None);
        self.needs_layout_scroll.set(true);
        let layout_gen = self.render_gen.get();
        let pane_layout = self.clone();
        glib::idle_add_local_once(move || {
            if pane_layout.render_gen.get() == layout_gen {
                pane_layout.needs_layout_scroll.set(false);
            }
        });

        if items.is_empty() {
            self.list_store.remove_all();
            self.empty_label.set_text(if self.filter_entry.text().is_empty() {
                "This folder is empty"
            } else {
                "No matching items"
            });
            self.view_stack.set_visible_child_name("empty");
            (self.callbacks.on_selection_changed)(Vec::new());
            (self.callbacks.on_state_changed)();
            return;
        }

        let rebind_active = sig != prev_sig;
        // Detach inactive (or rebinding) view BEFORE splicing list_store so we never bind
        // recycled widgets or submit throwaway thumbnails on the outgoing view.
        match view_mode {
            ViewMode::List => {
                if self.grid_view.model().is_some() {
                    self.grid_view.set_model(None::<&gtk4::SelectionModel>);
                }
                if rebind_active && self.list_view.model().is_some() {
                    self.list_view.set_model(None::<&gtk4::SelectionModel>);
                }
            }
            ViewMode::Grid | ViewMode::Gallery => {
                if self.list_view.model().is_some() {
                    self.list_view.set_model(None::<&gtk4::SelectionModel>);
                }
                if rebind_active && self.grid_view.model().is_some() {
                    self.grid_view.set_model(None::<&gtk4::SelectionModel>);
                }
            }
        }

        populate_list_store(&self.list_store, &items);

        match view_mode {
            ViewMode::List => {
                if self.list_view.model().is_none() {
                    self.list_view.set_model(Some(&self.selection_model));
                }
                self.view_stack.set_visible_child_name("list");
            }
            ViewMode::Grid | ViewMode::Gallery => {
                if self.grid_view.model().is_none() {
                    self.grid_view.set_model(Some(&self.selection_model));
                }
                self.view_stack.set_visible_child_name("grid");
            }
        }

        (self.callbacks.on_selection_changed)(Vec::new());
        (self.callbacks.on_state_changed)();
    }

    pub fn visible_count(&self) -> usize {
        self.list_store.n_items() as usize
    }

    pub fn selected_indices(&self) -> Vec<usize> {
        selected_indices_from_model(&self.selection_model)
    }

    pub fn selected_entries(&self) -> Vec<FileEntry> {
        self.selected_indices()
            .into_iter()
            .filter_map(|i| {
                self.list_store
                    .item(i as u32)
                    .and_downcast::<FileEntryObject>()
                    .and_then(|o| o.entry())
            })
            .collect()
    }

    pub fn selected_paths(&self) -> Vec<PathBuf> {
        self.selected_entries().into_iter().map(|e| e.path).collect()
    }

    pub fn focused_entry(&self) -> Option<FileEntry> {
        let len = self.list_store.n_items() as usize;
        if let Some(cur) = self.cursor_index.get().filter(|&i| i < len)
            && let Some(entry) = self
                .list_store
                .item(cur as u32)
                .and_downcast::<FileEntryObject>()
                .and_then(|o| o.entry())
        {
            return Some(entry);
        }
        self.selected_entries().into_iter().next()
    }

    pub fn action_entries(&self) -> Vec<FileEntry> {
        let sel = self.selected_entries();
        if !sel.is_empty() {
            sel
        } else {
            self.focused_entry().into_iter().collect()
        }
    }

    pub fn action_paths(&self) -> Vec<PathBuf> {
        self.action_entries().into_iter().map(|e| e.path).collect()
    }

    fn scroll_index_into_view(&self, pos: u32, focus: bool) {
        if pos >= self.list_store.n_items() {
            return;
        }
        let flags = if focus {
            gtk4::ListScrollFlags::FOCUS
        } else {
            gtk4::ListScrollFlags::NONE
        };
        let scroll_seq = self.scroll_gen.get().wrapping_add(1);
        self.scroll_gen.set(scroll_seq);
        let mode = self.state.borrow().config.view_mode;
        let is_mapped = match mode {
            ViewMode::List => {
                if self.list_view.model().is_some() {
                    self.list_view.scroll_to(pos, flags, None);
                }
                self.list_view.is_mapped()
            }
            ViewMode::Grid | ViewMode::Gallery => {
                if self.grid_view.model().is_some() {
                    self.grid_view.scroll_to(pos, flags, None);
                }
                self.grid_view.is_mapped()
            }
        };
        if !is_mapped || self.needs_layout_scroll.get() {
            let p = self.clone();
            let expected_render = self.render_gen.get();
            glib::idle_add_local_once(move || {
                if p.render_gen.get() != expected_render
                    || p.scroll_gen.get() != scroll_seq
                    || pos >= p.list_store.n_items()
                {
                    return;
                }
                match p.state.borrow().config.view_mode {
                    ViewMode::List if p.list_view.model().is_some() => {
                        p.list_view.scroll_to(pos, flags, None)
                    }
                    ViewMode::Grid | ViewMode::Gallery if p.grid_view.model().is_some() => {
                        p.grid_view.scroll_to(pos, flags, None)
                    }
                    _ => {}
                }
            });
        }
    }

    pub fn select_index(&self, idx: usize) {
        let len = self.list_store.n_items() as usize;
        if len == 0 {
            return;
        }
        let clamped = idx.min(len - 1);
        self.mark_mode.set(false);
        self.cursor_index.set(Some(clamped));
        self.selection_model.select_item(clamped as u32, true);
        self.scroll_index_into_view(clamped as u32, true);
    }

    pub fn toggle_select_and_advance(&self) {
        let len = self.list_store.n_items() as usize;
        if len == 0 {
            return;
        }
        let cur = self
            .cursor_index
            .get()
            .filter(|&i| i < len)
            .or_else(|| self.selected_indices().into_iter().next())
            .unwrap_or(0);
        let cur_selected = self.selection_model.is_selected(cur as u32);
        let selected_len = self.selected_indices().len();
        if yazi_space_should_select(self.mark_mode.get(), selected_len, cur_selected) {
            if !cur_selected {
                self.selection_model.select_item(cur as u32, false);
            }
        } else {
            self.selection_model.unselect_item(cur as u32);
        }
        self.mark_mode.set(!self.selected_indices().is_empty());
        let next = (cur + 1).min(len - 1);
        self.cursor_index.set(Some(next));
        self.scroll_index_into_view(next as u32, true);
    }

    pub fn select_path(&self, target: &Path) {
        let len = self.list_store.n_items();
        for pos in 0..len {
            if let Some(obj) = self.list_store.item(pos).and_downcast::<FileEntryObject>()
                && obj.path().as_deref() == Some(target)
            {
                self.select_index(pos as usize);
                return;
            }
        }
    }

    pub fn select_paths(&self, targets: &[PathBuf]) {
        if let Some(first) = select_paths_in_model(&self.list_store, &self.selection_model, targets)
        {
            self.cursor_index.set(Some(first));
            self.scroll_index_into_view(first as u32, false);
        }
    }

    pub fn focus_view(&self) {
        let len = self.list_store.n_items() as usize;
        if len > 0 {
            let target = self
                .cursor_index
                .get()
                .or_else(|| self.selected_indices().into_iter().next())
                .unwrap_or(0)
                .min(len - 1);
            self.scroll_index_into_view(target as u32, true);
        }
        match self.state.borrow().config.view_mode {
            ViewMode::List => {
                self.list_view.grab_focus();
            }
            ViewMode::Grid | ViewMode::Gallery => {
                self.grid_view.grab_focus();
            }
        }
    }

    pub fn move_selection(&self, delta: isize) {
        let len = self.list_store.n_items() as usize;
        let current = self
            .cursor_index
            .get()
            .filter(|&i| i < len)
            .or_else(|| self.selected_indices().into_iter().next());
        if let Some(next) = compute_move_selection_index(len, current, delta) {
            if self.mark_mode.get() {
                self.cursor_index.set(Some(next));
                self.scroll_index_into_view(next as u32, true);
            } else {
                self.select_index(next);
            }
        }
    }

    pub fn select_first(&self) {
        if self.list_store.n_items() == 0 {
            return;
        }
        if self.mark_mode.get() {
            self.cursor_index.set(Some(0));
            self.scroll_index_into_view(0, true);
        } else {
            self.select_index(0);
        }
    }

    pub fn select_last(&self) {
        let len = self.list_store.n_items() as usize;
        if len > 0 {
            let last = len - 1;
            if self.mark_mode.get() {
                self.cursor_index.set(Some(last));
                self.scroll_index_into_view(last as u32, true);
            } else {
                self.select_index(last);
            }
        }
    }

    pub fn select_all(&self) {
        self.selection_model.select_all();
    }

    pub fn clear_selection(&self) {
        self.mark_mode.set(false);
        self.selection_model.unselect_all();
        self.cursor_index.set(None);
    }

    pub fn activate_selected(&self) {
        if let Some(first) = self.focused_entry() {
            self.activate_entry(first);
        }
    }

    fn activate_entry(&self, entry: FileEntry) {
        if entry.is_dir {
            self.navigate_to(entry.path);
        } else {
            (self.callbacks.on_open_file)(entry);
        }
    }
}

fn yazi_space_should_select(mark_mode: bool, selected_len: usize, cur_selected: bool) -> bool {
    !cur_selected || (!mark_mode && selected_len == 1)
}

fn sort_col_btn(label: &str, expand: bool, align: gtk4::Align) -> gtk4::Button {
    let btn = gtk4::Button::with_label(label);
    btn.set_has_frame(false);
    btn.set_focus_on_click(false);
    btn.set_hexpand(expand);
    btn.set_halign(align);
    btn
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_entry(name: &str, is_dir: bool) -> FileEntry {
        FileEntry {
            name: name.into(),
            path: PathBuf::from(format!("/tmp/virt-test/{name}")),
            is_dir,
            is_symlink: false,
            is_broken_symlink: false,
            is_hidden: name.starts_with('.'),
            size: if is_dir { 0 } else { 1024 },
            modified: None,
            mode: if is_dir { 0o755 } else { 0o644 },
            kind: if is_dir {
                FileKind::Directory
            } else {
                FileKind::Image
            },
            git_badge: None,
            trash_original_path: None,
        }
    }

    #[test]
    fn virtualized_store_selection_matching_and_navigation_bounds() {
        let store = gio::ListStore::new::<FileEntryObject>();
        let entries: Vec<FileEntry> = (0..600)
            .map(|i| sample_entry(&format!("photo_{i:04}.png"), i == 0))
            .collect();
        populate_list_store(&store, &entries);
        assert_eq!(store.n_items(), 600);

        // Multi-select by paths across large virtualized list (past old 120 cap)
        let targets = vec![
            PathBuf::from("/tmp/virt-test/photo_0000.png"),
            PathBuf::from("/tmp/virt-test/photo_0150.png"),
            PathBuf::from("/tmp/virt-test/photo_0599.png"),
        ];
        let matched = matching_positions_in_store(&store, &targets);
        assert_eq!(matched, vec![0, 150, 599]);

        // Re-populating store with fewer items cleanly replaces previous items in one splice
        populate_list_store(&store, &entries[..10]);
        assert_eq!(store.n_items(), 10);
        assert_eq!(
            matching_positions_in_store(&store, &targets),
            vec![0]
        );

        // Missing path returns empty without panicking
        let missing = vec![PathBuf::from("/tmp/virt-test/does_not_exist.png")];
        assert!(matching_positions_in_store(&store, &missing).is_empty());

        // Keyboard / Vim navigation clamping
        assert_eq!(compute_move_selection_index(0, None, 1), None);
        assert_eq!(compute_move_selection_index(600, None, 1), Some(0));
        assert_eq!(compute_move_selection_index(600, Some(0), -1), Some(0));
        assert_eq!(compute_move_selection_index(600, Some(0), 1), Some(1));
        assert_eq!(compute_move_selection_index(600, Some(599), 1), Some(599));
        assert_eq!(compute_move_selection_index(600, Some(599), -1), Some(598));

        // First Space on an implicit single-cursor item promotes it to mark mode instead of unselecting
        assert!(yazi_space_should_select(false, 1, true));
        assert!(yazi_space_should_select(false, 0, false));
        assert!(!yazi_space_should_select(true, 1, true));
        assert!(!yazi_space_should_select(false, 3, true));
    }

    #[test]
    fn background_git_resolution_matches_without_main_thread_canonicalize() {
        let base =
            std::env::temp_dir().join(format!("alis-files-git-bg-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        std::fs::create_dir_all(base.join("sub")).unwrap();
        std::fs::create_dir_all(base.join("empty_sub")).unwrap();

        let init = std::process::Command::new("git")
            .current_dir(&base)
            .args(["init", "-q"])
            .status();
        if init.map(|s| s.success()).unwrap_or(false) {
            std::fs::write(base.join("untracked.txt"), "hello").unwrap();
            std::fs::write(base.join("sub/nested.txt"), "world").unwrap();
            let paths = vec![base.join("untracked.txt"), base.join("sub")];
            let (_branch, matched) = resolve_git_badges_background(&base, &paths);
            assert_eq!(
                matched.get(&base.join("untracked.txt")),
                Some(&GitBadge::Untracked)
            );
            assert_eq!(matched.get(&base.join("sub")), Some(&GitBadge::Untracked));

            // Empty subfolder inside a Git repo should still resolve cleanly without panicking.
            let (_empty_branch, empty_matched) =
                resolve_git_badges_background(&base.join("empty_sub"), &[]);
            assert!(empty_matched.is_empty());

            // Clean symlink to a modified/untracked target must NOT inherit the target's badge.
            #[cfg(unix)]
            {
                let link_path = base.join("clean_link.txt");
                let _ = std::os::unix::fs::symlink(base.join("untracked.txt"), &link_path);
                let _ = std::process::Command::new("git")
                    .current_dir(&base)
                    .args(["add", "clean_link.txt"])
                    .status();
                let _ = std::process::Command::new("git")
                    .current_dir(&base)
                    .args([
                        "-c",
                        "user.name=Test",
                        "-c",
                        "user.email=test@example.com",
                        "commit",
                        "-q",
                        "-m",
                        "track symlink",
                    ])
                    .status();
                let (_, sym_matched) = resolve_git_badges_background(
                    &base,
                    &[link_path.clone(), base.join("untracked.txt")],
                );
                assert_eq!(
                    sym_matched.get(&base.join("untracked.txt")),
                    Some(&GitBadge::Untracked)
                );
                assert_eq!(
                    sym_matched.get(&link_path),
                    None,
                    "committed clean symlink must not inherit target's untracked badge"
                );
            }
        }

        let _ = std::fs::remove_dir_all(&base);
    }

    /// Live GTK4 integration test meant to be run under a silent headless backend
    /// (`GDK_BACKEND=broadway BROADWAY_DISPLAY=:... cargo test -- --ignored --test-threads=1`).
    #[test]
    #[ignore = "requires GTK4 display (run under GDK_BACKEND=broadway with --test-threads=1)"]
    fn gtk4_broadway_live_pane_virtualization_selection_and_git_badges() {
        gtk4::init().expect("gtk4::init under broadway");

        let base = std::env::temp_dir().join(format!(
            "alis-files-gtk4-live-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&base);
        std::fs::create_dir_all(base.join("sub")).unwrap();

        // Populate 300 entries (exceeding old 120 thumbnail cap)
        for i in 0..300 {
            let p = base.join(format!("item_{i:04}.txt"));
            std::fs::write(&p, format!("content {i}")).unwrap();
        }

        let cfg = crate::config::AppConfig {
            view_mode: ViewMode::List,
            git_badges: false,
            thumbnails_enabled: true,
            ..Default::default()
        };
        let state = crate::ui::SharedState::new(cfg);

        let sel_counts = Rc::new(RefCell::new(Vec::<usize>::new()));
        let sel_counts_cb = sel_counts.clone();
        let pane = BrowserPane::new(
            base.clone(),
            state.clone(),
            PaneCallbacks {
                on_focus: Rc::new(|| {}),
                on_state_changed: Rc::new(|| {}),
                on_selection_changed: Rc::new(move |entries| {
                    sel_counts_cb.borrow_mut().push(entries.len());
                }),
                on_context_menu: Rc::new(|_, _, _, _, _| {}),
                on_drop_files: Rc::new(|_, _, _| {}),
                on_open_file: Rc::new(|_| {}),
            },
        );

        let win = gtk4::Window::new();
        win.set_default_size(900, 600);
        win.set_child(Some(&pane.root));
        win.present();

        let ctx = glib::MainContext::default();
        for _ in 0..20 {
            ctx.iteration(false);
        }

        assert_eq!(pane.visible_count(), 301); // sub + 300 files
        assert!(pane.list_view.model().is_some());
        assert!(pane.grid_view.model().is_none());

        // Exercise real MultiSelection + BitsetIter + select_paths past #120
        let multi = vec![
            base.join("item_0005.txt"),
            base.join("item_0150.txt"),
            base.join("item_0299.txt"),
        ];
        pane.select_paths(&multi);
        assert_eq!(pane.selected_indices().len(), 3);
        let selected_set: HashSet<PathBuf> = pane.selected_paths().into_iter().collect();
        for m in &multi {
            assert!(selected_set.contains(m));
        }

        // Switch List -> Grid and confirm selection preservation + single attached model
        state.borrow_mut().config.view_mode = ViewMode::Grid;
        pane.render_entries();
        for _ in 0..20 {
            ctx.iteration(false);
        }
        assert!(pane.list_view.model().is_none());
        assert!(pane.grid_view.model().is_some());
        assert_eq!(pane.selected_indices().len(), 3);

        // Keyboard / Vim navigation helpers (select_first, move_selection, select_last, select_all)
        pane.select_first();
        assert_eq!(pane.selected_indices(), vec![0]);
        pane.move_selection(1);
        assert_eq!(pane.selected_indices(), vec![1]);
        pane.move_selection(-1);
        assert_eq!(pane.selected_indices(), vec![0]);
        pane.select_last();
        assert_eq!(pane.selected_indices(), vec![300]);
        pane.select_all();
        assert_eq!(pane.selected_indices().len(), 301);

        // In-place Git badge update preserves exact FileEntryObject identity & selection
        let obj0_before = pane
            .list_store
            .item(0)
            .and_downcast::<FileEntryObject>()
            .unwrap();
        let mut badge_map = HashMap::new();
        badge_map.insert(base.join("sub"), GitBadge::Modified);
        {
            let mut entries = pane.entries.borrow_mut();
            let mut visible = pane.visible_entries.borrow_mut();
            let updated = apply_git_badges_in_place(
                &mut entries,
                &mut visible,
                &pane.list_store,
                &badge_map,
            );
            assert_eq!(updated, 1);
        }
        let obj0_after = pane
            .list_store
            .item(0)
            .and_downcast::<FileEntryObject>()
            .unwrap();
        assert_eq!(obj0_before, obj0_after);
        assert_eq!(obj0_after.git_badge(), Some(GitBadge::Modified));
        assert_eq!(pane.selected_indices().len(), 301);

        // Recursive search preserves sort order and selection across view toggle
        pane.filter_entry.set_text("item_029");
        pane.recursive_toggle.set_active(true);
        for _ in 0..10 {
            std::thread::sleep(std::time::Duration::from_millis(30));
            while ctx.iteration(false) {}
        }
        assert_eq!(pane.visible_count(), 10); // item_0290..item_0299
        pane.select_index(2);
        let picked = pane.selected_paths();
        assert_eq!(picked.len(), 1);
        state.borrow_mut().config.view_mode = ViewMode::List;
        pane.render_entries();
        assert_eq!(pane.selected_paths(), picked);

        win.destroy();
        for _ in 0..10 {
            ctx.iteration(false);
        }
        let _ = std::fs::remove_dir_all(&base);
    }

    #[test]
    fn git_badges_update_in_place_and_emit_signal_without_rebuilding_store() {
        let store = gio::ListStore::new::<FileEntryObject>();
        let mut entries = vec![
            sample_entry("README.md", false),
            sample_entry("src", true),
            sample_entry("clean.txt", false),
        ];
        let mut visible = entries.clone();
        populate_list_store(&store, &visible);

        // Keep references to the exact GObject instances to verify identity preservation (no rebuild)
        let obj0 = store.item(0).and_downcast::<FileEntryObject>().unwrap();
        let obj1 = store.item(1).and_downcast::<FileEntryObject>().unwrap();
        let obj2 = store.item(2).and_downcast::<FileEntryObject>().unwrap();

        let signals_fired = Rc::new(Cell::new(0usize));
        for o in [&obj0, &obj1, &obj2] {
            let counter = signals_fired.clone();
            o.connect_badge_changed(move |_| {
                counter.set(counter.get() + 1);
            });
        }

        let mut badges = HashMap::new();
        badges.insert(PathBuf::from("/tmp/virt-test/README.md"), GitBadge::Modified);
        badges.insert(PathBuf::from("/tmp/virt-test/src"), GitBadge::Untracked);

        let updated = apply_git_badges_in_place(&mut entries, &mut visible, &store, &badges);
        assert_eq!(updated, 2);
        assert_eq!(signals_fired.get(), 2);
        assert_eq!(obj0.git_badge(), Some(GitBadge::Modified));
        assert_eq!(obj1.git_badge(), Some(GitBadge::Untracked));
        assert_eq!(obj2.git_badge(), None);
        assert_eq!(entries[0].git_badge, Some(GitBadge::Modified));
        assert_eq!(visible[1].git_badge, Some(GitBadge::Untracked));

        // Applying the same badges again is a no-op (zero extra signals)
        let updated_again = apply_git_badges_in_place(&mut entries, &mut visible, &store, &badges);
        assert_eq!(updated_again, 0);
        assert_eq!(signals_fired.get(), 2);

        // Clearing badges updates back to None in-place
        let empty = HashMap::new();
        let cleared = apply_git_badges_in_place(&mut entries, &mut visible, &store, &empty);
        assert_eq!(cleared, 2);
        assert_eq!(signals_fired.get(), 4);
        assert_eq!(obj0.git_badge(), None);
        assert_eq!(obj1.git_badge(), None);
    }
}
