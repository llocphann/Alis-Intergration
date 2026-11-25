use crate::config::{SortField, SortOrder};
use crate::git::GitBadge;
use chrono::{DateTime, Local};
use std::cmp::Ordering;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileKind {
    Directory,
    Image,
    Audio,
    Video,
    Pdf,
    Archive,
    Markdown,
    Code,
    Document,
    Text,
    Executable,
    Other,
}

#[derive(Debug, Clone)]
pub struct FileEntry {
    pub name: String,
    pub path: PathBuf,
    pub is_dir: bool,
    pub is_symlink: bool,
    pub is_broken_symlink: bool,
    pub is_hidden: bool,
    pub size: u64,
    pub modified: Option<SystemTime>,
    pub mode: u32,
    pub kind: FileKind,
    pub git_badge: Option<GitBadge>,
    pub trash_original_path: Option<String>,
}

impl FileEntry {
    pub fn from_path(path: PathBuf) -> std::io::Result<Self> {
        let name = path
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_else(|| path.to_string_lossy().to_string());
        let lmeta = fs::symlink_metadata(&path)?;
        let is_symlink = lmeta.file_type().is_symlink();
        let (meta, is_broken_symlink) = if is_symlink {
            match fs::metadata(&path) {
                Ok(m) => (m, false),
                Err(_) => (lmeta, true),
            }
        } else {
            (lmeta, false)
        };
        let is_dir = !is_broken_symlink && meta.is_dir();
        let mode = meta.permissions().mode();
        let kind = if is_broken_symlink {
            FileKind::Other
        } else {
            classify_path(&path, is_dir, mode)
        };
        Ok(Self {
            is_hidden: name.starts_with('.'),
            name,
            path,
            is_dir,
            is_symlink,
            is_broken_symlink,
            size: if is_dir { 0 } else { meta.len() },
            modified: meta.modified().ok(),
            mode,
            kind,
            git_badge: None,
            trash_original_path: None,
        })
    }

    pub fn icon_name(&self) -> &'static str {
        if self.is_broken_symlink {
            return "dialog-warning-symbolic";
        }
        if self.is_dir {
            return match self.name.as_str() {
                "Desktop" => "user-desktop",
                "Documents" => "folder-documents",
                "Downloads" => "folder-download",
                "Music" => "folder-music",
                "Pictures" => "folder-pictures",
                "Videos" => "folder-videos",
                _ => "folder",
            };
        }
        match self.kind {
            FileKind::Directory => "folder",
            FileKind::Image => "image-x-generic",
            FileKind::Audio => "audio-x-generic",
            FileKind::Video => "video-x-generic",
            FileKind::Pdf => "application-pdf",
            FileKind::Archive => "package-x-generic",
            FileKind::Markdown | FileKind::Document => "x-office-document",
            FileKind::Code => "text-x-script",
            FileKind::Text => "text-x-generic",
            FileKind::Executable => "application-x-executable",
            FileKind::Other => "text-x-generic",
        }
    }

    pub fn kind_label(&self) -> &'static str {
        if self.is_broken_symlink {
            return "Broken Symlink";
        }
        match self.kind {
            FileKind::Directory => "Folder",
            FileKind::Image => "Image",
            FileKind::Audio => "Audio",
            FileKind::Video => "Video",
            FileKind::Pdf => "PDF Document",
            FileKind::Archive => "Archive",
            FileKind::Markdown => "Markdown Note",
            FileKind::Code => "Source Code",
            FileKind::Document => "Document",
            FileKind::Text => "Plain Text",
            FileKind::Executable => "Executable",
            FileKind::Other => "File",
        }
    }

    pub fn supports_wallpaper(&self) -> bool {
        !self.is_dir && matches!(self.kind, FileKind::Image | FileKind::Video)
    }

    pub fn supports_local_music(&self) -> bool {
        !self.is_dir && self.kind == FileKind::Audio
    }

    pub fn supports_nexus(&self) -> bool {
        !self.is_dir
            && matches!(
                self.kind,
                FileKind::Markdown | FileKind::Pdf | FileKind::Text | FileKind::Document | FileKind::Image
            )
    }

    pub fn is_extractable_archive(&self) -> bool {
        !self.is_dir && crate::archive::is_supported_archive(&self.path)
    }
}

pub fn classify_path(path: &Path, is_dir: bool, mode: u32) -> FileKind {
    if is_dir {
        return FileKind::Directory;
    }
    let name_lower = path
        .file_name()
        .map(|s| s.to_string_lossy().to_lowercase())
        .unwrap_or_default();
    if name_lower.ends_with(".tar.gz")
        || name_lower.ends_with(".tar.xz")
        || name_lower.ends_with(".tar.zst")
        || name_lower.ends_with(".tar.bz2")
    {
        return FileKind::Archive;
    }
    let ext = path
        .extension()
        .map(|e| e.to_string_lossy().to_lowercase())
        .unwrap_or_default();
    match ext.as_str() {
        "png" | "jpg" | "jpeg" | "webp" | "gif" | "bmp" | "svg" | "avif" | "ico" | "tif" | "tiff" | "jxl" => {
            FileKind::Image
        }
        "mp3" | "flac" | "ogg" | "opus" | "wav" | "m4a" | "aac" | "wma" | "aiff" => FileKind::Audio,
        "mp4" | "mkv" | "webm" | "mov" | "avi" | "m4v" | "flv" | "wmv" => FileKind::Video,
        "pdf" => FileKind::Pdf,
        "zip" | "tar" | "tgz" | "txz" | "tzst" | "tbz2" | "7z" | "rar" | "gz" | "xz" | "zst" | "bz2" => {
            FileKind::Archive
        }
        "md" | "markdown" | "mdx" | "org" | "base" => FileKind::Markdown,
        "rs" | "py" | "js" | "ts" | "jsx" | "tsx" | "qml" | "c" | "h" | "cpp" | "hpp" | "go" | "java"
        | "kt" | "swift" | "sh" | "bash" | "zsh" | "fish" | "kdl" | "toml" | "yaml" | "yml" | "json"
        | "xml" | "html" | "htm" | "css" | "scss" | "sql" | "lua" | "zig" | "nix" | "rb" | "php"
        | "makefile" | "cmake" | "dockerfile" => FileKind::Code,
        "doc" | "docx" | "odt" | "rtf" | "epub" | "pptx" | "xlsx" | "ods" | "odp" | "csv" => {
            FileKind::Document
        }
        "txt" | "log" | "conf" | "cfg" | "ini" | "env" | "gitignore" | "desktop" | "service" => {
            FileKind::Text
        }
        _ => {
            if matches!(
                name_lower.as_str(),
                "makefile" | "dockerfile" | "readme" | "license" | "justfile" | "pkgbuild"
            ) {
                FileKind::Text
            } else if (mode & 0o111) != 0 {
                FileKind::Executable
            } else {
                FileKind::Other
            }
        }
    }
}

pub fn trash_files_dir() -> PathBuf {
    crate::config::data_dir().join("Trash/files")
}

pub fn trash_info_dir() -> PathBuf {
    crate::config::data_dir().join("Trash/info")
}

pub fn is_trash_dir(path: &Path) -> bool {
    path == trash_files_dir()
}

pub fn read_directory(dir: &Path, show_hidden: bool) -> std::io::Result<Vec<FileEntry>> {
    let mut items = Vec::new();
    let in_trash = is_trash_dir(dir);
    for entry_res in fs::read_dir(dir)? {
        let Ok(entry) = entry_res else {
            continue;
        };
        let path = entry.path();
        let Ok(mut fe) = FileEntry::from_path(path) else {
            continue;
        };
        if !show_hidden && fe.is_hidden {
            continue;
        }
        if in_trash {
            fe.trash_original_path = read_trash_original_path(&fe.name);
        }
        items.push(fe);
    }
    Ok(items)
}

pub fn read_trash_original_path(name: &str) -> Option<String> {
    let info_file = trash_info_dir().join(format!("{name}.trashinfo"));
    let raw = fs::read_to_string(info_file).ok()?;
    for line in raw.lines() {
        if let Some(rest) = line.strip_prefix("Path=") {
            return Some(crate::dbus::percent_decode(rest));
        }
    }
    None
}

pub fn sort_entries(entries: &mut [FileEntry], field: SortField, order: SortOrder, dirs_first: bool) {
    entries.sort_by(|a, b| {
        if dirs_first && a.is_dir != b.is_dir {
            return if a.is_dir {
                Ordering::Less
            } else {
                Ordering::Greater
            };
        }
        let cmp = match field {
            SortField::Name => natural_cmp(&a.name, &b.name),
            SortField::Size => a
                .size
                .cmp(&b.size)
                .then_with(|| natural_cmp(&a.name, &b.name)),
            SortField::Modified => a
                .modified
                .cmp(&b.modified)
                .then_with(|| natural_cmp(&a.name, &b.name)),
            SortField::Kind => a
                .kind_label()
                .cmp(b.kind_label())
                .then_with(|| natural_cmp(&a.name, &b.name)),
        };
        match order {
            SortOrder::Asc => cmp,
            SortOrder::Desc => cmp.reverse(),
        }
    });
}

/// Natural case-insensitive filename comparison (e.g. `img2.png` < `img10.png`).
pub fn natural_cmp(a: &str, b: &str) -> Ordering {
    let mut ia = a.chars().peekable();
    let mut ib = b.chars().peekable();
    loop {
        match (ia.peek(), ib.peek()) {
            (None, None) => return a.cmp(b),
            (None, Some(_)) => return Ordering::Less,
            (Some(_), None) => return Ordering::Greater,
            (Some(&ca), Some(&cb)) if ca.is_ascii_digit() && cb.is_ascii_digit() => {
                let mut na = String::new();
                while let Some(&c) = ia.peek() {
                    if c.is_ascii_digit() {
                        na.push(c);
                        ia.next();
                    } else {
                        break;
                    }
                }
                let mut nb = String::new();
                while let Some(&c) = ib.peek() {
                    if c.is_ascii_digit() {
                        nb.push(c);
                        ib.next();
                    } else {
                        break;
                    }
                }
                let ta = na.trim_start_matches('0');
                let tb = nb.trim_start_matches('0');
                let cmp = ta.len().cmp(&tb.len()).then_with(|| ta.cmp(tb));
                if cmp != Ordering::Equal {
                    return cmp;
                }
            }
            (Some(_), Some(_)) => {
                let ca = ia.next().unwrap().to_ascii_lowercase();
                let cb = ib.next().unwrap().to_ascii_lowercase();
                if ca != cb {
                    return ca.cmp(&cb);
                }
            }
        }
    }
}

pub fn format_size(bytes: u64) -> String {
    const UNITS: [&str; 5] = ["B", "KB", "MB", "GB", "TB"];
    if bytes < 1024 {
        return format!("{bytes} B");
    }
    let mut val = bytes as f64;
    let mut idx = 0usize;
    while val >= 1024.0 && idx + 1 < UNITS.len() {
        val /= 1024.0;
        idx += 1;
    }
    if val >= 100.0 {
        format!("{val:.0} {}", UNITS[idx])
    } else if val >= 10.0 {
        format!("{val:.1} {}", UNITS[idx])
    } else {
        format!("{val:.2} {}", UNITS[idx])
    }
}

pub fn format_time(t: Option<SystemTime>) -> String {
    let Some(st) = t else {
        return "—".into();
    };
    let dt: DateTime<Local> = st.into();
    dt.format("%Y-%m-%d %H:%M").to_string()
}

pub fn format_permissions(mode: u32) -> String {
    let mut out = String::with_capacity(9);
    let bits = [
        (0o400, 'r'),
        (0o200, 'w'),
        (0o100, 'x'),
        (0o040, 'r'),
        (0o020, 'w'),
        (0o010, 'x'),
        (0o004, 'r'),
        (0o002, 'w'),
        (0o001, 'x'),
    ];
    for (mask, ch) in bits {
        out.push(if (mode & mask) != 0 { ch } else { '-' });
    }
    format!("{out} ({:03o})", mode & 0o777)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn natural_sorting_orders_numbers_properly() {
        let mut names = vec!["file10.txt", "file2.txt", "file1.txt", "File03.txt"];
        names.sort_by(|a, b| natural_cmp(a, b));
        assert_eq!(names, vec!["file1.txt", "file2.txt", "File03.txt", "file10.txt"]);
    }

    #[test]
    fn classify_extensions_and_human_size() {
        assert_eq!(classify_path(Path::new("wall.webp"), false, 0o644), FileKind::Image);
        assert_eq!(classify_path(Path::new("song.flac"), false, 0o644), FileKind::Audio);
        assert_eq!(classify_path(Path::new("note.md"), false, 0o644), FileKind::Markdown);
        assert_eq!(classify_path(Path::new("backup.tar.zst"), false, 0o644), FileKind::Archive);
        assert_eq!(classify_path(Path::new("run.sh"), false, 0o755), FileKind::Code);
        assert_eq!(classify_path(Path::new("bin"), false, 0o755), FileKind::Executable);
        assert_eq!(format_size(512), "512 B");
        assert_eq!(format_size(1536), "1.50 KB");
        assert_eq!(format_size(12 * 1024 * 1024), "12.0 MB");
    }
}
