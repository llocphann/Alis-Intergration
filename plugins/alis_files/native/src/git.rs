use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum GitBadge {
    Ignored,
    Untracked,
    Added,
    Modified,
    Deleted,
    Conflict,
}

impl GitBadge {
    pub fn short_label(self) -> &'static str {
        match self {
            Self::Modified => "M",
            Self::Added => "A",
            Self::Untracked => "?",
            Self::Deleted => "D",
            Self::Conflict => "!",
            Self::Ignored => "I",
        }
    }

    pub fn css_class(self) -> &'static str {
        match self {
            Self::Modified => "alis-git-modified",
            Self::Added => "alis-git-added",
            Self::Untracked => "alis-git-untracked",
            Self::Deleted => "alis-git-deleted",
            Self::Conflict => "alis-git-conflict",
            Self::Ignored => "alis-git-ignored",
        }
    }

    pub fn description(self) -> &'static str {
        match self {
            Self::Modified => "Modified",
            Self::Added => "Added / Staged",
            Self::Untracked => "Untracked",
            Self::Deleted => "Deleted",
            Self::Conflict => "Merge Conflict",
            Self::Ignored => "Ignored",
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct GitDirStatus {
    pub branch: Option<String>,
    pub badges: HashMap<PathBuf, GitBadge>,
}

/// Inspect Git repository status for a directory, mapping each direct child path
/// in `dir` to its highest-priority `GitBadge` (propagating modified/untracked states
/// upward onto subdirectories).
pub fn inspect_directory(dir: &Path) -> GitDirStatus {
    let top_out = Command::new("git")
        .current_dir(dir)
        .args(["rev-parse", "--show-toplevel"])
        .output();
    let Ok(top_out) = top_out else {
        return GitDirStatus::default();
    };
    if !top_out.status.success() {
        return GitDirStatus::default();
    }
    let repo_root = PathBuf::from(String::from_utf8_lossy(&top_out.stdout).trim());
    if !repo_root.is_dir() {
        return GitDirStatus::default();
    }

    let branch = Command::new("git")
        .current_dir(dir)
        .args(["rev-parse", "--abbrev-ref", "HEAD"])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .filter(|s| !s.is_empty());

    let status_out = Command::new("git")
        .current_dir(&repo_root)
        .args(["status", "--porcelain=v1", "-z", "--ignored=matching", "--untracked-files=normal"])
        .output();
    let Ok(status_out) = status_out else {
        return GitDirStatus {
            branch,
            badges: HashMap::new(),
        };
    };
    if !status_out.status.success() {
        return GitDirStatus {
            branch,
            badges: HashMap::new(),
        };
    }

    let canon_dir = dir.canonicalize().unwrap_or_else(|_| dir.to_path_buf());
    let canon_root = repo_root.canonicalize().unwrap_or(repo_root);
    let mut badges = parse_porcelain_z(&status_out.stdout, &canon_root, &canon_dir);
    if canon_dir != dir {
        let extra: Vec<(PathBuf, GitBadge)> = badges
            .iter()
            .filter_map(|(k, &v)| {
                k.file_name().map(|name| (dir.join(name), v))
            })
            .collect();
        for (k, v) in extra {
            badges.entry(k).or_insert(v);
        }
    }
    GitDirStatus { branch, badges }
}

pub fn parse_porcelain_z(
    raw: &[u8],
    repo_root: &Path,
    target_dir: &Path,
) -> HashMap<PathBuf, GitBadge> {
    let mut badges: HashMap<PathBuf, GitBadge> = HashMap::new();
    let mut chunks = raw.split(|&b| b == 0).peekable();
    while let Some(entry) = chunks.next() {
        if entry.len() < 4 {
            continue;
        }
        let x = entry[0] as char;
        let y = entry[1] as char;
        if x == 'R' || x == 'C' || y == 'R' || y == 'C' {
            // Skip original path token in -z rename/copy format
            let _ = chunks.next();
        }
        let rel_str = String::from_utf8_lossy(&entry[3..]);
        let rel_clean = rel_str.trim_end_matches('/');
        if rel_clean.is_empty() {
            continue;
        }
        let badge = classify_xy(x, y);
        let abs = repo_root.join(rel_clean);
        // If `abs` is inside `target_dir`, map it to the direct child of `target_dir`
        if let Ok(sub) = abs.strip_prefix(target_dir)
            && let Some(first_comp) = sub.components().next()
        {
            let child_path = target_dir.join(first_comp.as_os_str());
            badges
                .entry(child_path)
                .and_modify(|prev| {
                    if badge > *prev {
                        *prev = badge;
                    }
                })
                .or_insert(badge);
        }
    }
    badges
}

fn classify_xy(x: char, y: char) -> GitBadge {
    if matches!((x, y), ('U', _) | (_, 'U') | ('A', 'A') | ('D', 'D')) {
        GitBadge::Conflict
    } else if x == '!' && y == '!' {
        GitBadge::Ignored
    } else if x == '?' && y == '?' {
        GitBadge::Untracked
    } else if x == 'D' || y == 'D' {
        GitBadge::Deleted
    } else if x == 'A' || y == 'A' {
        GitBadge::Added
    } else {
        GitBadge::Modified
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn porcelain_z_maps_nested_files_to_direct_children() {
        let root = Path::new("/repo");
        let target = Path::new("/repo/src");
        let raw = b" M src/main.rs\0?? src/ui/pane.rs\0!! src/target/\0";
        let badges = parse_porcelain_z(raw, root, target);
        assert_eq!(badges.get(&PathBuf::from("/repo/src/main.rs")), Some(&GitBadge::Modified));
        assert_eq!(badges.get(&PathBuf::from("/repo/src/ui")), Some(&GitBadge::Untracked));
        assert_eq!(badges.get(&PathBuf::from("/repo/src/target")), Some(&GitBadge::Ignored));
    }
}
