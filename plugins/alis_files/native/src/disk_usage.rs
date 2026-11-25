use rayon::prelude::*;
use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

#[derive(Debug, Clone)]
pub struct DiskUsageItem {
    pub name: String,
    pub path: PathBuf,
    pub is_dir: bool,
    pub bytes: u64,
    pub item_count: u64,
}

#[derive(Debug, Clone)]
pub struct DiskUsageReport {
    #[allow(dead_code)]
    pub root: PathBuf,
    pub total_bytes: u64,
    pub total_items: u64,
    pub children: Vec<DiskUsageItem>,
}

/// Multithreaded directory disk usage analyzer using Rayon parallel traversal.
pub fn analyze_directory(root: &Path, cancel: &Arc<AtomicBool>) -> DiskUsageReport {
    let Ok(rd) = fs::read_dir(root) else {
        return DiskUsageReport {
            root: root.to_path_buf(),
            total_bytes: 0,
            total_items: 0,
            children: Vec::new(),
        };
    };

    let root_dev = fs::metadata(root).ok().map(|m| m.dev());

    let direct_entries: Vec<PathBuf> = rd
        .filter_map(|r| r.ok().map(|e| e.path()))
        .collect();

    let mut children: Vec<DiskUsageItem> = direct_entries
        .into_par_iter()
        .filter_map(|p| {
            if cancel.load(Ordering::Relaxed) {
                return None;
            }
            let name = p
                .file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_else(|| p.to_string_lossy().to_string());
            let meta = fs::symlink_metadata(&p).ok()?;
            if let Some(rdev) = root_dev
                && meta.dev() != rdev
            {
                return None;
            }
            if meta.file_type().is_symlink() {
                return Some(DiskUsageItem {
                    name,
                    path: p,
                    is_dir: false,
                    bytes: meta.len(),
                    item_count: 1,
                });
            }
            if meta.is_dir() {
                let (bytes, count) = dir_size_recursive_same_dev(&p, root_dev, cancel);
                Some(DiskUsageItem {
                    name,
                    path: p,
                    is_dir: true,
                    bytes,
                    item_count: count,
                })
            } else {
                Some(DiskUsageItem {
                    name,
                    path: p,
                    is_dir: false,
                    bytes: meta.len(),
                    item_count: 1,
                })
            }
        })
        .collect();

    children.sort_by(|a, b| b.bytes.cmp(&a.bytes).then_with(|| a.name.cmp(&b.name)));
    let total_bytes = children.iter().map(|c| c.bytes).sum();
    let total_items = children.iter().map(|c| c.item_count).sum();

    DiskUsageReport {
        root: root.to_path_buf(),
        total_bytes,
        total_items,
        children,
    }
}

/// Recursively computes `(logical_bytes, allocated_disk_bytes, item_count)` on the same filesystem.
pub fn dir_size_and_disk_recursive(dir: &Path, cancel: &Arc<AtomicBool>) -> (u64, u64, u64) {
    let root_dev = fs::metadata(dir).ok().map(|m| m.dev());
    dir_size_recursive_same_dev_with_disk(dir, root_dev, cancel)
}

fn dir_size_recursive_same_dev(
    dir: &Path,
    root_dev: Option<u64>,
    cancel: &Arc<AtomicBool>,
) -> (u64, u64) {
    let (bytes, _, count) = dir_size_recursive_same_dev_with_disk(dir, root_dev, cancel);
    (bytes, count)
}

fn dir_size_recursive_same_dev_with_disk(
    dir: &Path,
    root_dev: Option<u64>,
    cancel: &Arc<AtomicBool>,
) -> (u64, u64, u64) {
    let mut bytes = 0u64;
    let mut disk_bytes = 0u64;
    let mut count = 0u64;
    let mut stack = vec![dir.to_path_buf()];
    while let Some(cur) = stack.pop() {
        if cancel.load(Ordering::Relaxed) {
            break;
        }
        let Ok(rd) = fs::read_dir(&cur) else {
            continue;
        };
        for entry_res in rd {
            let Ok(entry) = entry_res else {
                continue;
            };
            let path = entry.path();
            let Ok(meta) = fs::symlink_metadata(&path) else {
                continue;
            };
            if let Some(rdev) = root_dev
                && meta.dev() != rdev
            {
                continue;
            }
            if meta.file_type().is_symlink() {
                count += 1;
                bytes += meta.len();
                disk_bytes += meta.blocks().saturating_mul(512);
            } else if meta.is_dir() {
                disk_bytes += meta.blocks().saturating_mul(512);
                stack.push(path);
            } else {
                count += 1;
                bytes += meta.len();
                disk_bytes += meta.blocks().saturating_mul(512);
            }
        }
    }
    (bytes, disk_bytes, count)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn disk_usage_analyzer_sums_nested_folders_and_sorts_desc() {
        let dir = std::env::temp_dir().join(format!("alis-files-du-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("big")).unwrap();
        fs::create_dir_all(dir.join("small")).unwrap();
        fs::write(dir.join("big/a.bin"), vec![0u8; 4096]).unwrap();
        fs::write(dir.join("big/b.bin"), vec![0u8; 2048]).unwrap();
        fs::write(dir.join("small/s.txt"), vec![0u8; 100]).unwrap();

        let cancel = Arc::new(AtomicBool::new(false));
        let report = analyze_directory(&dir, &cancel);
        assert_eq!(report.total_bytes, 6244);
        assert_eq!(report.total_items, 3);
        assert_eq!(report.children[0].name, "big");
        assert_eq!(report.children[0].bytes, 6144);
        assert_eq!(report.children[1].name, "small");
        assert_eq!(report.children[1].bytes, 100);
        let _ = fs::remove_dir_all(&dir);
    }
}
