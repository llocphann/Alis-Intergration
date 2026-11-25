use gtk4::gio;
use gtk4::prelude::*;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DriveItem {
    pub name: String,
    pub mount_point: Option<PathBuf>,
    pub icon_name: String,
    pub can_eject: bool,
    pub is_removable: bool,
    pub is_mounted: bool,
    pub total_bytes: u64,
    pub used_bytes: u64,
    pub block_device: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProcMountInfo {
    pub mount_point: PathBuf,
    pub source: String,
    pub fs_type: String,
}

impl DriveItem {
    pub fn usage_fraction(&self) -> f64 {
        if self.total_bytes == 0 {
            0.0
        } else {
            (self.used_bytes as f64 / self.total_bytes as f64).clamp(0.0, 1.0)
        }
    }
}

fn unescape_mountinfo_field(raw: &str) -> String {
    raw.replace("\\040", " ")
        .replace("\\011", "\t")
        .replace("\\012", "\n")
        .replace("\\134", "\\")
}

/// Parse `/proc/self/mountinfo` entries, splitting around `" - "` so variable optional fields
/// never shift filesystem type or block source columns.
pub fn parse_mountinfo(raw: &str) -> Vec<ProcMountInfo> {
    let mut out = Vec::new();
    for line in raw.lines() {
        let Some((left, right)) = line.split_once(" - ") else {
            continue;
        };
        let left_parts: Vec<&str> = left.split_whitespace().collect();
        let right_parts: Vec<&str> = right.split_whitespace().collect();
        if left_parts.len() < 5 || right_parts.len() < 2 {
            continue;
        }
        let mp = unescape_mountinfo_field(left_parts[4]);
        let fs_type = unescape_mountinfo_field(right_parts[0]);
        let source = unescape_mountinfo_field(right_parts[1]);
        out.push(ProcMountInfo {
            mount_point: PathBuf::from(mp),
            source,
            fs_type,
        });
    }
    out
}

pub(crate) fn canonical_dev(dev: &str) -> String {
    if dev.starts_with("/dev/") {
        fs::canonicalize(dev)
            .map(|p| p.to_string_lossy().to_string())
            .unwrap_or_else(|_| dev.to_string())
    } else {
        dev.to_string()
    }
}

fn is_user_media_mount(mp: &Path) -> bool {
    let s = mp.to_string_lossy();
    s.starts_with("/run/media/") || s.starts_with("/mnt/")
}

fn pick_preferred_mount<'a>(
    existing: Option<&'a PathBuf>,
    candidate: &'a PathBuf,
) -> &'a PathBuf {
    match existing {
        Some(prev) if is_user_media_mount(prev) => prev,
        Some(prev) if !is_user_media_mount(candidate) => prev,
        _ => candidate,
    }
}

pub(crate) fn reconcile_drives(
    gio_mounts: Vec<DriveItem>,
    gio_volumes: Vec<DriveItem>,
    proc_mounts: &[ProcMountInfo],
    space_fn: impl Fn(&Path) -> (u64, u64),
    is_dir_fn: impl Fn(&Path) -> bool,
) -> Vec<DriveItem> {
    let mut mounted_paths: HashSet<PathBuf> = HashSet::with_capacity(proc_mounts.len());
    let mut dev_to_mount: HashMap<String, PathBuf> = HashMap::new();
    let mut path_to_dev: HashMap<PathBuf, String> = HashMap::new();

    for pm in proc_mounts {
        mounted_paths.insert(pm.mount_point.clone());
        if pm.source.starts_with("/dev/") {
            let dev = canonical_dev(&pm.source);
            path_to_dev.insert(pm.mount_point.clone(), dev.clone());
            let next = match dev_to_mount.get(&dev) {
                Some(prev) => pick_preferred_mount(Some(prev), &pm.mount_point).clone(),
                None => pm.mount_point.clone(),
            };
            dev_to_mount.insert(dev, next);
        }
    }

    let mut items = Vec::new();
    let mut seen_paths: HashSet<PathBuf> = HashSet::new();
    let mut seen_devs: HashSet<String> = HashSet::new();

    // Pass 1: Mounted GIO mounts (filter out stale mounts no longer in /proc/self/mountinfo).
    for mut d in gio_mounts {
        let Some(ref mp) = d.mount_point else {
            continue;
        };
        if !proc_mounts.is_empty() && !mounted_paths.contains(mp) {
            continue;
        }
        if d.block_device.is_none()
            && let Some(dev) = path_to_dev.get(mp)
        {
            d.block_device = Some(dev.clone());
        }
        let canon = d.block_device.as_deref().map(canonical_dev);
        if !seen_paths.insert(mp.clone()) {
            continue;
        }
        if let Some(ref c) = canon {
            seen_devs.insert(c.clone());
        }
        items.push(d);
    }

    // Pass 2: GIO volumes (promote stale headless-daemon unmounted volumes if active in mountinfo).
    for mut v in gio_volumes {
        let Some(ref raw_dev) = v.block_device else {
            continue;
        };
        let canon = canonical_dev(raw_dev);
        if seen_devs.contains(&canon) {
            continue;
        }
        if let Some(mp) = dev_to_mount.get(&canon) {
            if !seen_paths.insert(mp.clone()) {
                seen_devs.insert(canon);
                continue;
            }
            seen_devs.insert(canon);
            let (tot, used) = space_fn(mp);
            v.mount_point = Some(mp.clone());
            v.is_mounted = true;
            v.can_eject = true;
            v.total_bytes = tot;
            v.used_bytes = used;
            items.push(v);
        } else {
            seen_devs.insert(canon);
            items.push(v);
        }
    }

    // Pass 3: Supplement /run/media/* or /mnt/* mounts missed by headless GVfs.
    for pm in proc_mounts {
        if !is_user_media_mount(&pm.mount_point) || !is_dir_fn(&pm.mount_point) {
            continue;
        }
        if seen_paths.contains(&pm.mount_point) {
            continue;
        }
        let dev_opt = if pm.source.starts_with("/dev/") {
            let c = canonical_dev(&pm.source);
            if seen_devs.contains(&c) {
                continue;
            }
            seen_devs.insert(c.clone());
            Some(c)
        } else {
            None
        };
        seen_paths.insert(pm.mount_point.clone());
        let (tot, used) = space_fn(&pm.mount_point);
        let name = pm
            .mount_point
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| pm.mount_point.to_string_lossy().to_string());
        items.push(DriveItem {
            name,
            mount_point: Some(pm.mount_point.clone()),
            icon_name: "drive-removable-media".into(),
            can_eject: true,
            is_removable: true,
            is_mounted: true,
            total_bytes: tot,
            used_bytes: used,
            block_device: dev_opt,
        });
    }

    items.sort_by(|a, b| {
        b.is_removable
            .cmp(&a.is_removable)
            .then_with(|| b.is_mounted.cmp(&a.is_mounted))
            .then_with(|| a.name.cmp(&b.name))
    });
    items
}

/// Enumerate mounted drives & unmounted UDisks2/GVfs volumes via `gio::VolumeMonitor`
/// reconciled against live `/proc/self/mountinfo` (critical in headless overlay daemon mode).
pub fn list_drives() -> Vec<DriveItem> {
    let monitor = gio::VolumeMonitor::get();
    let mut gio_mounts = Vec::new();
    for mount in monitor.mounts() {
        let root = mount.root();
        let Some(path) = root.path() else {
            continue;
        };
        let name = mount.name().to_string();
        let can_eject = mount.can_eject() || mount.can_unmount();
        let volume = mount.volume();
        let is_removable = volume
            .as_ref()
            .and_then(|v| v.drive())
            .map(|d| d.is_removable() || d.is_media_removable())
            .unwrap_or(can_eject);
        let block_device = volume
            .as_ref()
            .and_then(|v| v.identifier(gio::VOLUME_IDENTIFIER_KIND_UNIX_DEVICE))
            .map(|s| s.to_string());
        let icon_name = if is_removable {
            "drive-removable-media"
        } else {
            "drive-harddisk"
        }
        .to_string();
        let (total_bytes, used_bytes) = filesystem_space(&path);
        gio_mounts.push(DriveItem {
            name,
            mount_point: Some(path),
            icon_name,
            can_eject,
            is_removable,
            is_mounted: true,
            total_bytes,
            used_bytes,
            block_device,
        });
    }

    let mut gio_volumes = Vec::new();
    for volume in monitor.volumes() {
        if volume.get_mount().is_some() || !volume.can_mount() {
            continue;
        }
        let block_device = volume
            .identifier(gio::VOLUME_IDENTIFIER_KIND_UNIX_DEVICE)
            .map(|s| s.to_string());
        if block_device.is_none() {
            continue;
        }
        let name = volume.name().to_string();
        let is_removable = volume
            .drive()
            .map(|d| d.is_removable() || d.is_media_removable())
            .unwrap_or(true);
        let icon_name = if is_removable {
            "drive-removable-media"
        } else {
            "drive-harddisk"
        }
        .to_string();
        gio_volumes.push(DriveItem {
            name,
            mount_point: None,
            icon_name,
            can_eject: false,
            is_removable,
            is_mounted: false,
            total_bytes: 0,
            used_bytes: 0,
            block_device,
        });
    }

    let proc_mounts = fs::read_to_string("/proc/self/mountinfo")
        .map(|raw| parse_mountinfo(&raw))
        .unwrap_or_default();

    reconcile_drives(gio_mounts, gio_volumes, &proc_mounts, filesystem_space, |p| {
        p.is_dir()
    })
}

/// Mount an unmounted block device via UDisks2 (`udisksctl mount -b <dev>`) with `gio mount -d` fallback.
pub fn mount_volume(block_device: &str) -> Result<PathBuf, String> {
    if let Ok(out) = Command::new("udisksctl")
        .args(["mount", "-b", block_device])
        .output()
        && out.status.success()
    {
        let stdout = String::from_utf8_lossy(&out.stdout);
        if let Some(mp) = parse_udisksctl_mount_output(&stdout) {
            return Ok(mp);
        }
        if let Some(mp) = findmnt_target(block_device) {
            return Ok(mp);
        }
    }

    let out = Command::new("gio")
        .args(["mount", "-d", block_device])
        .output()
        .map_err(|e| format!("Failed invoking gio mount: {e}"))?;
    if out.status.success()
        && let Some(mp) = findmnt_target(block_device)
    {
        return Ok(mp);
    }
    let stderr = String::from_utf8_lossy(&out.stderr).trim().to_string();
    Err(if stderr.is_empty() {
        format!("Could not mount {block_device}")
    } else {
        stderr
    })
}

pub(crate) fn parse_udisksctl_mount_output(stdout: &str) -> Option<PathBuf> {
    // Typical output: "Mounted /dev/sdb1 at /run/media/user/USB_DRIVE."
    let idx = stdout.find(" at ")?;
    let rest = stdout[idx + 4..].trim().trim_end_matches('.');
    if rest.starts_with('/') {
        Some(PathBuf::from(rest))
    } else {
        None
    }
}

fn findmnt_target(block_device: &str) -> Option<PathBuf> {
    let out = Command::new("findmnt")
        .args(["-n", "-o", "TARGET", block_device])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let target = String::from_utf8_lossy(&out.stdout).lines().next()?.trim().to_string();
    if target.is_empty() {
        None
    } else {
        Some(PathBuf::from(target))
    }
}

/// Safely unmount (and power-off ONLY removable USB drives) using `udisksctl` / `gio`.
pub fn safe_unmount(
    mount_point: &Path,
    block_device: Option<&str>,
    is_removable: bool,
) -> Result<String, String> {
    // 1. Prefer `udisksctl unmount` when we know the block device (clean UDisks2 safe eject).
    if let Some(dev) = block_device {
        let out = Command::new("udisksctl")
            .args(["unmount", "-b", dev])
            .output();
        if let Ok(res) = out
            && res.status.success()
        {
            if is_removable {
                let _ = Command::new("udisksctl")
                    .args(["power-off", "-b", dev])
                    .output();
                return Ok(format!("Safely ejected {}", mount_point.display()));
            }
            return Ok(format!("Unmounted {}", mount_point.display()));
        }
    }

    // 2. Fallback to `gio mount -u <path>`.
    let out = Command::new("gio")
        .args(["mount", "-u"])
        .arg(mount_point)
        .output()
        .map_err(|e| format!("Failed to invoke gio mount: {e}"))?;
    if out.status.success() {
        return Ok(format!("Unmounted {}", mount_point.display()));
    }
    let stderr = String::from_utf8_lossy(&out.stderr).trim().to_string();
    Err(if stderr.is_empty() {
        "Drive is busy and could not be unmounted".into()
    } else {
        stderr
    })
}

/// Query filesystem total & used bytes via `gio::File::query_filesystem_info` (safe, zero unsafe libc).
pub fn filesystem_space(path: &Path) -> (u64, u64) {
    let gfile = gio::File::for_path(path);
    let attrs = format!(
        "{},{}",
        gio::FILE_ATTRIBUTE_FILESYSTEM_SIZE,
        gio::FILE_ATTRIBUTE_FILESYSTEM_FREE
    );
    let Ok(info) = gfile.query_filesystem_info(&attrs, gio::Cancellable::NONE) else {
        return (0, 0);
    };
    let total = info.attribute_uint64(gio::FILE_ATTRIBUTE_FILESYSTEM_SIZE);
    let free = info.attribute_uint64(gio::FILE_ATTRIBUTE_FILESYSTEM_FREE);
    let used = total.saturating_sub(free);
    (total, used)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_udisksctl_mount_output() {
        assert_eq!(
            parse_udisksctl_mount_output("Mounted /dev/sdb1 at /run/media/user/My USB.\n"),
            Some(PathBuf::from("/run/media/user/My USB"))
        );
        assert_eq!(parse_udisksctl_mount_output("Error mounting"), None);
    }

    #[test]
    fn parse_mountinfo_handles_spaces_and_optional_fields() {
        let raw = "\
27 1 259:2 / / rw,relatime shared:1 - ext4 /dev/nvme0n1p2 rw\n\
812 27 259:3 / /run/media/llocphann/Windows\\04011 rw,nosuid,nodev,relatime shared:42 master:9 - fuseblk /dev/nvme0n1p3 rw\n";
        let parsed = parse_mountinfo(raw);
        assert_eq!(parsed.len(), 2);
        assert_eq!(parsed[0].mount_point, PathBuf::from("/"));
        assert_eq!(parsed[0].source, "/dev/nvme0n1p2");
        assert_eq!(
            parsed[1].mount_point,
            PathBuf::from("/run/media/llocphann/Windows 11")
        );
        assert_eq!(parsed[1].fs_type, "fuseblk");
        assert_eq!(parsed[1].source, "/dev/nvme0n1p3");
    }

    #[test]
    fn reconcile_promotes_stale_unmounted_volume_without_duplicating() {
        let proc_mounts = vec![ProcMountInfo {
            mount_point: PathBuf::from("/run/media/llocphann/Windows_11"),
            source: "/dev/nvme0n1p3".into(),
            fs_type: "fuseblk".into(),
        }];
        let stale_vol = DriveItem {
            name: "Windows_11".into(),
            mount_point: None,
            icon_name: "drive-harddisk".into(),
            can_eject: false,
            is_removable: false,
            is_mounted: false,
            total_bytes: 0,
            used_bytes: 0,
            block_device: Some("/dev/nvme0n1p3".into()),
        };

        let out = reconcile_drives(
            Vec::new(),
            vec![stale_vol],
            &proc_mounts,
            |_| (500_000, 100_000),
            |_| true,
        );
        assert_eq!(out.len(), 1);
        assert!(out[0].is_mounted);
        assert!(out[0].can_eject);
        assert_eq!(out[0].name, "Windows_11");
        assert_eq!(
            out[0].mount_point,
            Some(PathBuf::from("/run/media/llocphann/Windows_11"))
        );
        assert_eq!(out[0].block_device.as_deref(), Some("/dev/nvme0n1p3"));
        assert_eq!(out[0].total_bytes, 500_000);
        assert_eq!(out[0].used_bytes, 100_000);
    }

    #[test]
    fn reconcile_drops_stale_unmounted_gio_mount_and_dedups_supplement() {
        let proc_mounts = vec![ProcMountInfo {
            mount_point: PathBuf::from("/run/media/llocphann/USB"),
            source: "/dev/sda1".into(),
            fs_type: "vfat".into(),
        }];
        let stale_old_mount = DriveItem {
            name: "Gone".into(),
            mount_point: Some(PathBuf::from("/run/media/llocphann/Gone")),
            icon_name: "drive-removable-media".into(),
            can_eject: true,
            is_removable: true,
            is_mounted: true,
            total_bytes: 100,
            used_bytes: 10,
            block_device: Some("/dev/sdb1".into()),
        };
        let valid_mount = DriveItem {
            name: "USB".into(),
            mount_point: Some(PathBuf::from("/run/media/llocphann/USB")),
            icon_name: "drive-removable-media".into(),
            can_eject: true,
            is_removable: true,
            is_mounted: true,
            total_bytes: 200,
            used_bytes: 50,
            block_device: Some("/dev/sda1".into()),
        };

        let out = reconcile_drives(
            vec![stale_old_mount, valid_mount],
            Vec::new(),
            &proc_mounts,
            |_| (200, 50),
            |_| true,
        );
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].name, "USB");
    }
}
