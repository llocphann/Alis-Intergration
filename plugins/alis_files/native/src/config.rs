use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ViewMode {
    List,
    Grid,
    Gallery,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SortField {
    Name,
    Size,
    Modified,
    Kind,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SortOrder {
    Asc,
    Desc,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct AppConfig {
    pub overlay_mode: bool,
    pub view_mode: ViewMode,
    pub show_hidden: bool,
    pub confirm_permanent_delete: bool,
    pub split_view_default: bool,
    pub inspector_open_default: bool,
    pub rail_open: bool,
    pub vim_keybindings: bool,
    pub git_badges: bool,
    pub thumbnails_enabled: bool,
    pub directories_first: bool,
    pub sort_field: SortField,
    pub sort_order: SortOrder,
    pub grid_icon_size: i32,
    pub list_zoom: u8,
    pub window_width: i32,
    pub window_height: i32,
    pub rail_width: i32,
    pub inspector_width: i32,
    pub inspector_preview_ratio_milli: u16,
    pub bookmarks_initialized: bool,
    pub bookmarks: Vec<BookmarkEntry>,
    pub recent_folders: Vec<String>,
    pub session: SessionState,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SessionTab {
    pub path: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub split_path: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct SessionState {
    pub tabs: Vec<String>,
    pub active_tab: usize,
    pub split_open: bool,
    pub split_ratio_milli: u16,
    pub secondary_tabs: Vec<String>,
    pub secondary_active_tab: usize,
    pub active_is_secondary: bool,
    #[serde(default)]
    pub tab_entries: Vec<SessionTab>,
}

impl Default for SessionState {
    fn default() -> Self {
        Self {
            tabs: Vec::new(),
            active_tab: 0,
            split_open: false,
            split_ratio_milli: 500,
            secondary_tabs: Vec::new(),
            secondary_active_tab: 0,
            active_is_secondary: false,
            tab_entries: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct BookmarkEntry {
    pub name: String,
    pub path: String,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            overlay_mode: true,
            view_mode: ViewMode::Grid,
            show_hidden: false,
            confirm_permanent_delete: true,
            split_view_default: false,
            inspector_open_default: false,
            rail_open: true,
            vim_keybindings: true,
            git_badges: true,
            thumbnails_enabled: true,
            directories_first: true,
            sort_field: SortField::Name,
            sort_order: SortOrder::Asc,
            grid_icon_size: 72,
            list_zoom: 1,
            window_width: 1240,
            window_height: 800,
            rail_width: 228,
            inspector_width: 296,
            inspector_preview_ratio_milli: 380,
            bookmarks_initialized: false,
            bookmarks: Vec::new(),
            recent_folders: Vec::new(),
            session: SessionState::default(),
        }
    }
}

pub fn xdg_config_home() -> PathBuf {
    if let Ok(xdg) = std::env::var("XDG_CONFIG_HOME")
        && !xdg.trim().is_empty()
    {
        return PathBuf::from(xdg);
    }
    home_dir().join(".config")
}

pub fn config_dir() -> PathBuf {
    xdg_config_home().join("alis")
}

pub fn config_path() -> PathBuf {
    config_dir().join("alis-files.json")
}

pub fn state_dir() -> PathBuf {
    if let Ok(xdg) = std::env::var("XDG_STATE_HOME")
        && !xdg.trim().is_empty()
    {
        return PathBuf::from(xdg);
    }
    home_dir().join(".local/state")
}

pub fn data_dir() -> PathBuf {
    if let Ok(xdg) = std::env::var("XDG_DATA_HOME")
        && !xdg.trim().is_empty()
    {
        return PathBuf::from(xdg);
    }
    home_dir().join(".local/share")
}

pub fn cache_dir() -> PathBuf {
    if let Ok(xdg) = std::env::var("XDG_CACHE_HOME")
        && !xdg.trim().is_empty()
    {
        return PathBuf::from(xdg);
    }
    home_dir().join(".cache")
}

pub fn home_dir() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}

pub fn gtk_bookmarks_path() -> PathBuf {
    if let Ok(xdg) = std::env::var("XDG_CONFIG_HOME")
        && !xdg.trim().is_empty()
    {
        return PathBuf::from(xdg).join("gtk-3.0/bookmarks");
    }
    home_dir().join(".config/gtk-3.0/bookmarks")
}

impl AppConfig {
    pub fn load() -> Self {
        Self::load_from(&config_path())
    }

    pub fn load_from(path: &Path) -> Self {
        let raw = fs::read_to_string(path).ok();
        let has_bookmarks_key = raw
            .as_deref()
            .and_then(|txt| serde_json::from_str::<serde_json::Value>(txt).ok())
            .and_then(|val| val.as_object().map(|obj| obj.contains_key("bookmarks")))
            .unwrap_or(false);
        let mut cfg = raw
            .as_deref()
            .and_then(|txt| serde_json::from_str::<AppConfig>(txt).ok())
            .unwrap_or_default();
        if !cfg.bookmarks_initialized && !has_bookmarks_key && cfg.bookmarks.is_empty() {
            cfg.bookmarks = read_gtk_bookmarks(&gtk_bookmarks_path());
        }
        if has_bookmarks_key || !cfg.bookmarks.is_empty() {
            cfg.bookmarks_initialized = true;
        }
        cfg.grid_icon_size = cfg.grid_icon_size.clamp(40, 240);
        cfg.list_zoom = cfg.list_zoom.min(2);
        cfg.rail_width = cfg.rail_width.clamp(156, 460);
        cfg.inspector_width = cfg.inspector_width.clamp(200, 560);
        cfg.inspector_preview_ratio_milli = cfg.inspector_preview_ratio_milli.clamp(220, 720);
        cfg.session.split_ratio_milli = cfg.session.split_ratio_milli.clamp(200, 800);
        cfg
    }

    pub fn save(&self) -> std::io::Result<()> {
        self.save_to(&config_path())
    }

    pub fn save_to(&self, path: &Path) -> std::io::Result<()> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let body = serde_json::to_string_pretty(self)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
        let tmp = path.with_extension("json.tmp");
        fs::write(&tmp, format!("{body}\n"))?;
        fs::rename(&tmp, path)?;
        Ok(())
    }

    pub fn add_bookmark(&mut self, path: &Path) -> bool {
        self.bookmarks_initialized = true;
        let canonical = path.to_string_lossy().to_string();
        if self.bookmarks.iter().any(|b| b.path == canonical) {
            return false;
        }
        let name = path
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| canonical.clone());
        self.bookmarks.push(BookmarkEntry {
            name,
            path: canonical,
        });
        true
    }

    pub fn remove_bookmark(&mut self, path: &str) -> bool {
        self.bookmarks_initialized = true;
        let before = self.bookmarks.len();
        self.bookmarks.retain(|b| b.path != path);
        self.bookmarks.len() != before
    }

    pub fn push_recent(&mut self, path: &Path) {
        let s = path.to_string_lossy().to_string();
        self.recent_folders.retain(|x| x != &s);
        self.recent_folders.insert(0, s);
        self.recent_folders.truncate(24);
    }
}

pub fn read_gtk_bookmarks(path: &Path) -> Vec<BookmarkEntry> {
    let Ok(raw) = fs::read_to_string(path) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for line in raw.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let mut parts = trimmed.splitn(2, ' ');
        let uri = parts.next().unwrap_or("");
        let label = parts.next().map(str::trim).filter(|s| !s.is_empty());
        if let Some(decoded) = crate::dbus::uri_to_path(uri) {
            let path_str = decoded.to_string_lossy().to_string();
            let name = label.map(ToOwned::to_owned).unwrap_or_else(|| {
                decoded
                    .file_name()
                    .map(|n| n.to_string_lossy().to_string())
                    .unwrap_or_else(|| path_str.clone())
            });
            if !out.iter().any(|b: &BookmarkEntry| b.path == path_str) {
                out.push(BookmarkEntry {
                    name,
                    path: path_str,
                });
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_roundtrip_and_bookmarks() {
        let dir = std::env::temp_dir().join(format!("alis-files-cfg-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let file = dir.join("alis-files.json");

        let mut cfg = AppConfig {
            view_mode: ViewMode::Grid,
            show_hidden: true,
            ..Default::default()
        };
        assert!(cfg.add_bookmark(Path::new("/tmp/projects")));
        assert!(!cfg.add_bookmark(Path::new("/tmp/projects")));
        cfg.push_recent(Path::new("/tmp/a"));
        cfg.push_recent(Path::new("/tmp/b"));
        cfg.push_recent(Path::new("/tmp/a"));
        assert_eq!(cfg.recent_folders, vec!["/tmp/a", "/tmp/b"]);
        cfg.save_to(&file).unwrap();

        let loaded = AppConfig::load_from(&file);
        assert_eq!(loaded.view_mode, ViewMode::Grid);
        assert!(loaded.show_hidden);
        assert_eq!(loaded.bookmarks.len(), 1);
        assert_eq!(loaded.bookmarks[0].name, "projects");

        // Gallery mode + new rail_open / list_zoom fields roundtrip
        let cfg_gal = AppConfig {
            view_mode: ViewMode::Gallery,
            rail_open: false,
            list_zoom: 2,
            grid_icon_size: 176,
            ..Default::default()
        };
        cfg_gal.save_to(&file).unwrap();
        let loaded_gal = AppConfig::load_from(&file);
        assert_eq!(loaded_gal.view_mode, ViewMode::Gallery);
        assert!(!loaded_gal.rail_open);
        assert_eq!(loaded_gal.list_zoom, 2);
        assert_eq!(loaded_gal.grid_icon_size, 176);

        // Legacy JSON missing new fields deserializes cleanly via #[serde(default)]
        fs::write(&file, r#"{"view_mode":"list","show_hidden":false}"#).unwrap();
        let legacy = AppConfig::load_from(&file);
        assert_eq!(legacy.view_mode, ViewMode::List);
        assert!(legacy.rail_open);
        assert_eq!(legacy.list_zoom, 1);

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn empty_bookmarks_do_not_reimport_gtk_bookmarks() {
        let dir = std::env::temp_dir().join(format!("alis-files-empty-bm-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let file = dir.join("alis-files.json");

        let mut cfg = AppConfig {
            bookmarks: vec![BookmarkEntry {
                name: "Tmp".into(),
                path: "/tmp".into(),
            }],
            ..Default::default()
        };
        assert!(cfg.remove_bookmark("/tmp"));
        assert!(cfg.bookmarks.is_empty());
        assert!(cfg.bookmarks_initialized);
        cfg.save_to(&file).unwrap();

        let reloaded = AppConfig::load_from(&file);
        assert!(reloaded.bookmarks.is_empty());
        assert!(reloaded.bookmarks_initialized);

        // Even legacy JSON with explicit `"bookmarks": []` must not re-import GTK bookmarks.
        fs::write(&file, r#"{"bookmarks":[],"rail_width":999,"inspector_width":10,"inspector_preview_ratio_milli":90}"#).unwrap();
        let clamped = AppConfig::load_from(&file);
        assert!(clamped.bookmarks.is_empty());
        assert!(clamped.bookmarks_initialized);
        assert_eq!(clamped.rail_width, 460);
        assert_eq!(clamped.inspector_width, 200);
        assert_eq!(clamped.inspector_preview_ratio_milli, 220);
        assert_eq!(clamped.session.split_ratio_milli, 500);

        // SessionState + merged split tab_entries + preview split ratio roundtrip + clamping
        let sess_cfg = AppConfig {
            inspector_preview_ratio_milli: 850,
            session: SessionState {
                tabs: vec!["/tmp".into(), "/home".into()],
                active_tab: 1,
                split_open: true,
                split_ratio_milli: 950,
                secondary_tabs: vec!["/var".into()],
                secondary_active_tab: 0,
                active_is_secondary: true,
                tab_entries: vec![
                    SessionTab {
                        path: "/tmp".into(),
                        split_path: Some("/var".into()),
                    },
                    SessionTab {
                        path: "/home".into(),
                        split_path: None,
                    },
                ],
            },
            ..Default::default()
        };
        sess_cfg.save_to(&file).unwrap();
        let reloaded_sess = AppConfig::load_from(&file);
        assert_eq!(reloaded_sess.session.tabs, vec!["/tmp", "/home"]);
        assert_eq!(reloaded_sess.session.active_tab, 1);
        assert!(reloaded_sess.session.split_open);
        assert_eq!(reloaded_sess.session.split_ratio_milli, 800);
        assert_eq!(reloaded_sess.inspector_preview_ratio_milli, 720);
        assert!(reloaded_sess.session.active_is_secondary);
        assert_eq!(reloaded_sess.session.tab_entries.len(), 2);
        assert_eq!(
            reloaded_sess.session.tab_entries[0].split_path.as_deref(),
            Some("/var")
        );
        assert_eq!(reloaded_sess.session.tab_entries[1].split_path, None);

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn gtk_bookmarks_parser_handles_spaces_and_labels() {
        let dir = std::env::temp_dir().join(format!("alis-files-gtk-bm-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let bm = dir.join("bookmarks");
        fs::write(
            &bm,
            "file:///home/user/My%20Docs My Docs\nfile:///tmp/work\n# comment\n",
        )
        .unwrap();
        let parsed = read_gtk_bookmarks(&bm);
        assert_eq!(parsed.len(), 2);
        assert_eq!(parsed[0].path, "/home/user/My Docs");
        assert_eq!(parsed[0].name, "My Docs");
        assert_eq!(parsed[1].path, "/tmp/work");
        assert_eq!(parsed[1].name, "work");
        let _ = fs::remove_dir_all(&dir);
    }
}
