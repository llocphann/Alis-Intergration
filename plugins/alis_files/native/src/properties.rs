use crate::model::{FileEntry, format_permissions, format_size, is_trash_dir, read_trash_original_path};
use chrono::{DateTime, Local};
use gtk4::gio;
use gtk4::prelude::*;
use serde::Serialize;
use std::collections::HashSet;
use std::fs;
use std::io::Read;
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::Path;
use std::process::Command;
use std::sync::OnceLock;
use std::time::SystemTime;

#[derive(Debug, Clone, Serialize)]
pub struct AppChoice {
    pub id: String,
    pub name: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct ItemProperties {
    pub path: String,
    pub name: String,
    pub location: String,
    pub is_dir: bool,
    pub is_symlink: bool,
    pub is_broken_symlink: bool,
    pub symlink_target: Option<String>,
    pub kind_label: String,
    pub type_description: String,
    pub mime_type: String,
    pub default_app_id: Option<String>,
    pub default_app_name: Option<String>,
    pub available_apps: Vec<AppChoice>,
    pub size: u64,
    pub size_label: String,
    pub size_on_disk: u64,
    pub size_on_disk_label: String,
    pub created_label: String,
    pub modified_label: String,
    pub accessed_label: String,
    pub mode: u32,
    pub permissions_label: String,
    pub is_executable: bool,
    pub can_chmod: bool,
    pub owner: String,
    pub group: String,
    pub inode: u64,
    pub hard_links: u64,
    pub device_id: u64,
    pub direct_children: Option<usize>,
    pub trash_original_path: Option<String>,
    pub git_status: Option<String>,
    pub image_dimensions: Option<String>,
}

fn current_euid() -> u32 {
    static EUID: OnceLock<u32> = OnceLock::new();
    *EUID.get_or_init(|| {
        fs::read_to_string("/proc/self/status")
            .ok()
            .and_then(|txt| {
                txt.lines()
                    .find(|l| l.starts_with("Uid:"))
                    .and_then(|l| l.split_whitespace().nth(2))
                    .and_then(|s| s.parse::<u32>().ok())
            })
            .unwrap_or(u32::MAX)
    })
}

fn lookup_unix_name(db_path: &str, id: u32) -> String {
    let target = id.to_string();
    if let Ok(raw) = fs::read_to_string(db_path) {
        for line in raw.lines() {
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let mut parts = line.split(':');
            let Some(name) = parts.next() else { continue };
            let _passwd = parts.next();
            let Some(num) = parts.next() else { continue };
            if num == target && !name.is_empty() {
                return name.to_string();
            }
        }
    }
    target
}

fn format_time_long(t: Option<SystemTime>) -> String {
    let Some(st) = t else {
        return "—".into();
    };
    let dt: DateTime<Local> = st.into();
    dt.format("%a, %b %d, %Y %H:%M").to_string()
}

fn resolve_mime_and_apps(path: &Path, is_dir: bool) -> (String, String, Option<String>, Option<String>, Vec<AppChoice>) {
    if is_dir {
        let ct = gio::content_type_from_mime_type("inode/directory")
            .unwrap_or_else(|| "inode/directory".into());
        let default_app = gio::AppInfo::default_for_type(&ct, false);
        let default_id = default_app.as_ref().and_then(|a| a.id()).map(|s| s.to_string());
        let default_name = default_app.as_ref().map(|a| a.display_name().to_string());
        return (
            "inode/directory".into(),
            "Folder".into(),
            default_id,
            default_name,
            Vec::new(),
        );
    }

    let sample = fs::File::open(path)
        .ok()
        .map(|mut f| {
            let mut buf = vec![0u8; 4096];
            let n = f.read(&mut buf).unwrap_or(0);
            buf.truncate(n);
            buf
        })
        .unwrap_or_default();

    let (ct, _) = gio::content_type_guess(Some(path), sample.as_slice());
    let mime = gio::content_type_get_mime_type(&ct)
        .map(|s| s.to_string())
        .unwrap_or_else(|| ct.to_string());
    let desc = gio::content_type_get_description(&ct).to_string();

    let default_app = gio::AppInfo::default_for_type(&ct, false);
    let default_id = default_app.as_ref().and_then(|a| a.id()).map(|s| s.to_string());
    let default_name = default_app.as_ref().map(|a| a.display_name().to_string());

    let mut seen = HashSet::new();
    let mut apps = Vec::new();
    for app in gio::AppInfo::all_for_type(&ct) {
        let Some(id) = app.id().map(|s| s.to_string()) else {
            continue;
        };
        if !seen.insert(id.clone()) {
            continue;
        }
        apps.push(AppChoice {
            id,
            name: app.display_name().to_string(),
        });
        if apps.len() >= 24 {
            break;
        }
    }

    (mime, desc, default_id, default_name, apps)
}

/// Pure-Rust header-only probe for PNG, GIF, JPEG, and WebP image dimensions.
pub fn probe_image_dimensions(path: &Path) -> Option<String> {
    let mut f = fs::File::open(path).ok()?;
    let mut buf = vec![0u8; 64 * 1024];
    let n = f.read(&mut buf).ok()?;
    buf.truncate(n);
    if n < 10 {
        return None;
    }

    // PNG: 8-byte signature + IHDR width/height at offsets 16..24
    if n >= 24 && &buf[0..8] == b"\x89PNG\r\n\x1a\n" && &buf[12..16] == b"IHDR" {
        let w = u32::from_be_bytes([buf[16], buf[17], buf[18], buf[19]]);
        let h = u32::from_be_bytes([buf[20], buf[21], buf[22], buf[23]]);
        if w > 0 && h > 0 {
            return Some(format!("{w} × {h} px"));
        }
    }

    // GIF87a / GIF89a: little-endian u16 width/height at 6..10
    if (&buf[0..6] == b"GIF87a" || &buf[0..6] == b"GIF89a") && n >= 10 {
        let w = u16::from_le_bytes([buf[6], buf[7]]) as u32;
        let h = u16::from_le_bytes([buf[8], buf[9]]) as u32;
        if w > 0 && h > 0 {
            return Some(format!("{w} × {h} px"));
        }
    }

    // WebP: RIFF....WEBP
    if n >= 30 && &buf[0..4] == b"RIFF" && &buf[8..12] == b"WEBP" {
        let chunk = &buf[12..16];
        if chunk == b"VP8X" {
            let w = 1 + (u32::from(buf[24]) | (u32::from(buf[25]) << 8) | (u32::from(buf[26]) << 16));
            let h = 1 + (u32::from(buf[27]) | (u32::from(buf[28]) << 8) | (u32::from(buf[29]) << 16));
            return Some(format!("{w} × {h} px"));
        }
        if chunk == b"VP8L" && n >= 25 {
            let bits = u32::from_le_bytes([buf[21], buf[22], buf[23], buf[24]]);
            let w = (bits & 0x3FFF) + 1;
            let h = ((bits >> 14) & 0x3FFF) + 1;
            return Some(format!("{w} × {h} px"));
        }
        if chunk == b"VP8 " && n >= 30 && buf[23] == 0x9d && buf[24] == 0x01 && buf[25] == 0x2a {
            let w = u32::from(u16::from_le_bytes([buf[26], buf[27]]) & 0x3FFF);
            let h = u32::from(u16::from_le_bytes([buf[28], buf[29]]) & 0x3FFF);
            if w > 0 && h > 0 {
                return Some(format!("{w} × {h} px"));
            }
        }
    }

    // JPEG: SOI (FF D8), walk markers until SOF
    if buf[0] == 0xFF && buf[1] == 0xD8 {
        let mut i = 2usize;
        while i + 3 < n {
            if buf[i] != 0xFF {
                i += 1;
                continue;
            }
            while i < n && buf[i] == 0xFF {
                i += 1;
            }
            if i >= n {
                break;
            }
            let marker = buf[i];
            i += 1;
            if marker == 0x00 || (0xD0..=0xD9).contains(&marker) {
                continue;
            }
            if marker == 0xDA {
                break; // SOS
            }
            if i + 2 > n {
                break;
            }
            let seg_len = u16::from_be_bytes([buf[i], buf[i + 1]]) as usize;
            if matches!(
                marker,
                0xC0 | 0xC1 | 0xC2 | 0xC3 | 0xC5 | 0xC6 | 0xC7 | 0xC9 | 0xCA | 0xCB | 0xCD | 0xCE | 0xCF
            ) {
                if i + 7 <= n {
                    let h = u16::from_be_bytes([buf[i + 3], buf[i + 4]]) as u32;
                    let w = u16::from_be_bytes([buf[i + 5], buf[i + 6]]) as u32;
                    if w > 0 && h > 0 {
                        return Some(format!("{w} × {h} px"));
                    }
                }
                break;
            }
            if seg_len < 2 || i + seg_len > n {
                break;
            }
            i += seg_len;
        }
    }

    None
}

pub fn inspect_item(path: &Path, git_status: Option<String>) -> Result<ItemProperties, String> {
    let entry = FileEntry::from_path(path.to_path_buf())
        .map_err(|e| format!("Cannot inspect '{}': {e}", path.display()))?;
    let lmeta = fs::symlink_metadata(path)
        .map_err(|e| format!("Cannot inspect '{}': {e}", path.display()))?;
    let meta = if entry.is_symlink && !entry.is_broken_symlink {
        fs::metadata(path).unwrap_or(lmeta)
    } else {
        lmeta
    };

    let symlink_target = if entry.is_symlink {
        fs::read_link(path).ok().map(|t| t.to_string_lossy().to_string())
    } else {
        None
    };

    let location = path
        .parent()
        .map(|p| p.to_string_lossy().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "/".into());

    let (mime_type, type_description, default_app_id, default_app_name, available_apps) =
        if entry.is_broken_symlink {
            (
                "inode/symlink".into(),
                "Broken Symbolic Link".into(),
                None,
                None,
                Vec::new(),
            )
        } else {
            resolve_mime_and_apps(path, entry.is_dir)
        };

    let size_on_disk = meta.blocks().saturating_mul(512);
    let uid = meta.uid();
    let gid = meta.gid();
    let euid = current_euid();
    let can_chmod = !entry.is_broken_symlink && !entry.is_symlink && (euid == 0 || euid == uid);

    let direct_children = if entry.is_dir {
        fs::read_dir(path)
            .ok()
            .map(|rd| rd.filter_map(Result::ok).count())
    } else {
        None
    };

    let trash_original_path = path
        .parent()
        .filter(|p| is_trash_dir(p))
        .and_then(|_| read_trash_original_path(&entry.name));

    let image_dimensions = if !entry.is_dir && mime_type.starts_with("image/") {
        probe_image_dimensions(path)
    } else {
        None
    };

    let mode = meta.permissions().mode() & 0o7777;
    Ok(ItemProperties {
        path: path.to_string_lossy().to_string(),
        name: entry.name.clone(),
        location,
        is_dir: entry.is_dir,
        is_symlink: entry.is_symlink,
        is_broken_symlink: entry.is_broken_symlink,
        symlink_target,
        kind_label: entry.kind_label().to_string(),
        type_description,
        mime_type,
        default_app_id,
        default_app_name,
        available_apps,
        size: if entry.is_dir { 0 } else { meta.len() },
        size_label: if entry.is_dir {
            "Calculating…".into()
        } else {
            format_size(meta.len())
        },
        size_on_disk,
        size_on_disk_label: if entry.is_dir {
            "Calculating…".into()
        } else {
            format_size(size_on_disk)
        },
        created_label: format_time_long(meta.created().ok()),
        modified_label: format_time_long(meta.modified().ok()),
        accessed_label: format_time_long(meta.accessed().ok()),
        mode,
        permissions_label: format_permissions(mode),
        is_executable: !entry.is_dir && (mode & 0o100) != 0,
        can_chmod,
        owner: lookup_unix_name("/etc/passwd", uid),
        group: lookup_unix_name("/etc/group", gid),
        inode: meta.ino(),
        hard_links: meta.nlink(),
        device_id: meta.dev(),
        direct_children,
        trash_original_path,
        git_status,
        image_dimensions,
    })
}

pub fn set_mode(path: &Path, mode: u32) -> Result<ItemProperties, String> {
    let masked = mode & 0o777;
    if let Err(e) = fs::set_permissions(path, fs::Permissions::from_mode(masked)) {
        if crate::fs_ops::is_permission_error(&e) {
            let oct = format!("{masked:o}");
            crate::fs_ops::run_pkexec(
                "chmod",
                &[
                    std::ffi::OsStr::new(&oct),
                    std::ffi::OsStr::new("--"),
                    path.as_os_str(),
                ],
            )?;
        } else {
            return Err(format!("Failed updating permissions: {e}"));
        }
    }
    inspect_item(path, None)
}

pub fn set_default_app(mime_type: &str, app_id: &str) -> Result<(), String> {
    if mime_type.trim().is_empty() || app_id.trim().is_empty() {
        return Err("Missing MIME type or application id".into());
    }
    let ct = gio::content_type_from_mime_type(mime_type).unwrap_or_else(|| mime_type.into());
    if let Some(app) = gio::DesktopAppInfo::new(app_id)
        && app.set_as_default_for_type(&ct).is_ok()
    {
        return Ok(());
    }
    let out = Command::new("xdg-mime")
        .args(["default", app_id, mime_type])
        .output()
        .map_err(|e| format!("Failed running xdg-mime: {e}"))?;
    if out.status.success() {
        Ok(())
    } else {
        let err = String::from_utf8_lossy(&out.stderr).trim().to_string();
        Err(if err.is_empty() {
            "Could not update default application".into()
        } else {
            err
        })
    }
}

pub fn compute_checksum(path: &Path, algo: &str) -> Result<String, String> {
    let meta = fs::metadata(path).map_err(|e| format!("Cannot read file: {e}"))?;
    if !meta.is_file() {
        return Err("Checksums are only supported for regular files".into());
    }
    let bin = match algo.to_ascii_lowercase().as_str() {
        "md5" => "md5sum",
        "sha1" => "sha1sum",
        "sha256" => "sha256sum",
        "sha512" => "sha512sum",
        other => return Err(format!("Unsupported checksum algorithm: {other}")),
    };
    let out = Command::new(bin)
        .arg("--")
        .arg(path)
        .output()
        .map_err(|e| format!("Failed running {bin}: {e}"))?;
    if !out.status.success() {
        let err = String::from_utf8_lossy(&out.stderr).trim().to_string();
        return Err(if err.is_empty() {
            format!("{bin} failed")
        } else {
            err
        });
    }
    String::from_utf8_lossy(&out.stdout)
        .split_whitespace()
        .next()
        .filter(|s| !s.is_empty())
        .map(ToOwned::to_owned)
        .ok_or_else(|| format!("Empty digest from {bin}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;
    use std::sync::atomic::AtomicBool;

    #[test]
    fn inspect_set_mode_checksum_and_png_probe() {
        let dir = std::env::temp_dir().join(format!("alis-files-props-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("sub")).unwrap();

        let txt = dir.join("hello.txt");
        fs::write(&txt, b"hello alis").unwrap();
        let props = inspect_item(&txt, Some("Modified".into())).unwrap();
        assert_eq!(props.name, "hello.txt");
        assert_eq!(props.size, 10);
        assert_eq!(props.git_status.as_deref(), Some("Modified"));
        assert!(props.can_chmod);

        let updated = set_mode(&txt, 0o750).unwrap();
        assert_eq!(updated.mode & 0o777, 0o750);
        assert!(updated.is_executable);

        let sha = compute_checksum(&txt, "sha256").unwrap();
        assert_eq!(sha.len(), 64);

        // Minimal 128x64 PNG header check
        let mut png_bytes = vec![0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A];
        png_bytes.extend_from_slice(&13u32.to_be_bytes());
        png_bytes.extend_from_slice(b"IHDR");
        png_bytes.extend_from_slice(&128u32.to_be_bytes());
        png_bytes.extend_from_slice(&64u32.to_be_bytes());
        png_bytes.extend_from_slice(&[8, 6, 0, 0, 0]);
        let png = dir.join("sample.png");
        fs::write(&png, &png_bytes).unwrap();
        assert_eq!(probe_image_dimensions(&png).as_deref(), Some("128 × 64 px"));

        let cancel = Arc::new(AtomicBool::new(false));
        let (bytes, disk_bytes, count) = crate::disk_usage::dir_size_and_disk_recursive(&dir, &cancel);
        assert!(bytes >= 10 + png_bytes.len() as u64);
        assert!(disk_bytes >= bytes || disk_bytes > 0);
        assert_eq!(count, 2);

        let _ = fs::remove_dir_all(&dir);
    }
}
