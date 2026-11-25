pub mod dialogs;
pub mod file_art;
pub mod inspector;
pub mod keys;
pub mod pane;
pub mod quicklook;
pub mod sidebar;
pub mod window;

use crate::config::AppConfig;
use crate::fs_ops::UndoManager;
use crate::thumbnails::{LruCache, TEXTURE_LRU_CAPACITY, ThumbCacheKey};
use gtk4::gdk;
use gtk4::gio;
use gtk4::glib;
use gtk4::prelude::*;
use std::cell::RefCell;
use std::path::{Path, PathBuf};
use std::rc::Rc;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClipboardOp {
    Copy,
    Cut,
}

#[derive(Debug, Clone, Default)]
pub struct FileClipboard {
    pub op: Option<ClipboardOp>,
    pub paths: Vec<PathBuf>,
}

pub struct SharedState {
    pub config: AppConfig,
    pub undo: UndoManager,
    pub clipboard: FileClipboard,
    pub thumb_cache: LruCache<ThumbCacheKey, gdk::Texture>,
}

pub type SharedStateRc = Rc<RefCell<SharedState>>;

impl SharedState {
    pub fn new(config: AppConfig) -> SharedStateRc {
        Rc::new(RefCell::new(Self {
            config,
            undo: UndoManager::default(),
            clipboard: FileClipboard::default(),
            thumb_cache: LruCache::new(TEXTURE_LRU_CAPACITY),
        }))
    }

    pub fn is_cut_path(&self, path: &Path) -> bool {
        self.clipboard.op == Some(ClipboardOp::Cut)
            && self.clipboard.paths.iter().any(|p| p == path)
    }
}

/// Write selected file paths to both internal clipboard and Wayland/GTK system clipboard
/// (`text/uri-list` + `x-special/gnome-copied-files`) for seamless cross-app paste.
pub fn set_system_clipboard_files(
    state: &SharedStateRc,
    paths: Vec<PathBuf>,
    op: ClipboardOp,
) {
    {
        let mut st = state.borrow_mut();
        st.clipboard = FileClipboard {
            op: Some(op),
            paths: paths.clone(),
        };
    }

    if let Some(display) = gdk::Display::default() {
        let clipboard = display.clipboard();
        let uri_list = crate::dbus::paths_to_uri_list(&paths);
        let gnome_prefix = match op {
            ClipboardOp::Copy => "copy",
            ClipboardOp::Cut => "cut",
        };
        let gnome_payload = format!(
            "{gnome_prefix}\n{}",
            paths
                .iter()
                .map(|p| crate::dbus::path_to_file_uri(p))
                .collect::<Vec<_>>()
                .join("\n")
        );
        let p_uri = gdk::ContentProvider::for_bytes(
            "text/uri-list",
            &glib::Bytes::from_owned(uri_list.into_bytes()),
        );
        let p_gnome = gdk::ContentProvider::for_bytes(
            "x-special/gnome-copied-files",
            &glib::Bytes::from_owned(gnome_payload.into_bytes()),
        );
        let plain = paths
            .iter()
            .map(|p| p.to_string_lossy().to_string())
            .collect::<Vec<_>>()
            .join("\n");
        let p_text = gdk::ContentProvider::for_bytes(
            "text/plain;charset=utf-8",
            &glib::Bytes::from_owned(plain.into_bytes()),
        );
        let union = gdk::ContentProvider::new_union(&[p_uri, p_gnome, p_text]);
        let _ = clipboard.set_content(Some(&union));
    }
}

pub fn set_system_clipboard_text(text: &str) {
    if let Some(display) = gdk::Display::default() {
        display.clipboard().set_text(text);
    }
}

/// Read files from internal clipboard ONLY when this process still owns the Wayland/GTK
/// system clipboard (`clipboard.is_local()`); otherwise read directly from the system clipboard
/// (`x-special/gnome-copied-files` / `text/uri-list`) so external app copies always win.
pub fn read_clipboard_files<F>(state: &SharedStateRc, on_ready: F)
where
    F: FnOnce(Vec<PathBuf>, ClipboardOp) + 'static,
{
    let display = gdk::Display::default();
    let use_local = display
        .as_ref()
        .map(|d| d.clipboard().is_local())
        .unwrap_or(true);
    if use_local {
        let local = state.borrow().clipboard.clone();
        if let Some(op) = local.op
            && !local.paths.is_empty()
        {
            on_ready(local.paths, op);
            return;
        }
    } else {
        let mut st = state.borrow_mut();
        st.clipboard.paths.clear();
        st.clipboard.op = None;
    }

    let Some(display) = display else {
        on_ready(Vec::new(), ClipboardOp::Copy);
        return;
    };
    let clipboard = display.clipboard();
    let cb_cell = Rc::new(RefCell::new(Some(on_ready)));
    let cb_clone = cb_cell.clone();

    clipboard.read_async(
        &["x-special/gnome-copied-files", "text/uri-list"],
        glib::Priority::DEFAULT,
        gio::Cancellable::NONE,
        move |res| {
            let Some(callback) = cb_clone.borrow_mut().take() else {
                return;
            };
            let Ok((stream, mime)) = res else {
                callback(Vec::new(), ClipboardOp::Copy);
                return;
            };
            let mut buf = Vec::new();
            let mut chunk = [0u8; 4096];
            while let Ok(n) = stream.read(&mut chunk, gio::Cancellable::NONE) {
                if n == 0 {
                    break;
                }
                buf.extend_from_slice(&chunk[..n]);
                if buf.len() > 2 * 1024 * 1024 {
                    break;
                }
            }
            let text = String::from_utf8_lossy(&buf);
            if mime == "x-special/gnome-copied-files" {
                let mut lines = text.lines();
                let op = match lines.next().unwrap_or("copy").trim() {
                    "cut" => ClipboardOp::Cut,
                    _ => ClipboardOp::Copy,
                };
                let rest: String = lines.collect::<Vec<_>>().join("\n");
                let paths = crate::dbus::parse_uri_list(&rest);
                callback(paths, op);
            } else {
                let paths = crate::dbus::parse_uri_list(&text);
                callback(paths, ClipboardOp::Copy);
            }
        },
    );
}
