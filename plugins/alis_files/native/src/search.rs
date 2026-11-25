use crate::model::FileEntry;
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

/// Fast recursive search inside `root` matching `query` (case-insensitive substring).
/// Prefers `fd` when installed, with a pure-Rust breadth/depth fallback.
pub fn recursive_search(
    root: &Path,
    query: &str,
    include_hidden: bool,
    max_results: usize,
    cancel: &Arc<AtomicBool>,
) -> Vec<FileEntry> {
    let q = query.trim();
    if q.is_empty() {
        return Vec::new();
    }

    if let Some(entries) = try_fd_search(root, q, include_hidden, max_results, cancel) {
        return entries;
    }

    let q_lower = q.to_lowercase();
    let mut results = Vec::new();
    let mut stack = vec![root.to_path_buf()];

    while let Some(dir) = stack.pop() {
        if cancel.load(Ordering::Relaxed) || results.len() >= max_results {
            break;
        }
        let Ok(rd) = fs::read_dir(&dir) else {
            continue;
        };
        for entry_res in rd {
            if cancel.load(Ordering::Relaxed) || results.len() >= max_results {
                break;
            }
            let Ok(entry) = entry_res else {
                continue;
            };
            let name = entry.file_name().to_string_lossy().to_string();
            if !include_hidden && name.starts_with('.') {
                continue;
            }
            if matches!(name.as_str(), ".git" | "node_modules" | "target") && !include_hidden {
                continue;
            }
            let path = entry.path();
            if name.to_lowercase().contains(&q_lower)
                && let Ok(fe) = FileEntry::from_path(path.clone())
            {
                results.push(fe);
            }
            if let Ok(ft) = entry.file_type()
                && ft.is_dir()
                && !ft.is_symlink()
            {
                stack.push(path);
            }
        }
    }
    results
}

fn try_fd_search(
    root: &Path,
    query: &str,
    include_hidden: bool,
    max_results: usize,
    cancel: &Arc<AtomicBool>,
) -> Option<Vec<FileEntry>> {
    let mut cmd = Command::new("fd");
    cmd.stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .args([
            "--fixed-strings",
            "--ignore-case",
            "--color=never",
            "-0",
            "--max-results",
        ])
        .arg(max_results.to_string());
    if include_hidden {
        cmd.args(["--hidden", "--no-ignore"]);
    }
    cmd.arg("--").arg(query).arg(root);
    let mut child = cmd.spawn().ok()?;
    let mut stdout = child.stdout.take()?;

    // Read stdout on a dedicated thread so cancel can kill `fd` immediately without blocking.
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let mut buf = Vec::new();
        let _ = stdout.read_to_end(&mut buf);
        let _ = tx.send(buf);
    });

    let stdout_bytes = loop {
        if cancel.load(Ordering::Relaxed) {
            let _ = child.kill();
            let _ = child.wait();
            return Some(Vec::new());
        }
        match child.try_wait() {
            Ok(Some(_)) => break rx.recv_timeout(Duration::from_millis(500)).ok()?,
            Ok(None) => std::thread::sleep(Duration::from_millis(15)),
            Err(_) => {
                let _ = child.kill();
                let _ = child.wait();
                return None;
            }
        }
    };

    let mut entries = Vec::new();
    for raw in stdout_bytes.split(|&b| b == 0) {
        if cancel.load(Ordering::Relaxed) || entries.len() >= max_results {
            break;
        }
        if raw.is_empty() {
            continue;
        }
        let s = String::from_utf8_lossy(raw);
        let p = PathBuf::from(s.as_ref());
        if let Ok(fe) = FileEntry::from_path(p) {
            entries.push(fe);
        }
    }
    Some(entries)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recursive_search_finds_nested_files() {
        let dir = std::env::temp_dir().join(format!("alis-files-search-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("sub/deep")).unwrap();
        fs::write(dir.join("sub/deep/AlisReport-2026.md"), "ok").unwrap();
        fs::write(dir.join("sub/other.txt"), "ok").unwrap();

        let cancel = Arc::new(AtomicBool::new(false));
        let hits = recursive_search(&dir, "report-2026", false, 50, &cancel);
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].name, "AlisReport-2026.md");

        // Leading-dash query must not be parsed as an `fd` option flag
        let dash_hits = recursive_search(&dir, "-2026", false, 50, &cancel);
        assert_eq!(dash_hits.len(), 1);
        assert_eq!(dash_hits[0].name, "AlisReport-2026.md");
        let _ = fs::remove_dir_all(&dir);
    }
}
