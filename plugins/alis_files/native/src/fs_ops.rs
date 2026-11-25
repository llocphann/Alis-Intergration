use chrono::Local;
use regex::Regex;
use std::collections::HashSet;
use std::ffi::{OsStr, OsString};
use std::fs;
use std::io;
use std::io::Write;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

pub fn is_permission_error(err: &io::Error) -> bool {
    err.kind() == io::ErrorKind::PermissionDenied || matches!(err.raw_os_error(), Some(1 | 13))
}

fn pkexec_error_message(code: Option<i32>, stderr: &str) -> String {
    let lower = stderr.to_ascii_lowercase();
    if code == Some(126) || lower.contains("dismissed") || lower.contains("request dismissed") {
        return "Authentication cancelled".into();
    }
    if code == Some(127) {
        return "Polkit authentication failed or pkexec is unavailable".into();
    }
    let msg = stderr.trim();
    if !msg.is_empty() {
        return msg.to_string();
    }
    match code {
        Some(c) => format!("Elevated command failed (exit status {c})"),
        None => "Elevated command terminated unexpectedly".into(),
    }
}

/// Runs `<program>` via `pkexec` using positional arguments (never shell interpolation).
pub fn run_pkexec<S: AsRef<OsStr>>(program: &str, args: &[S]) -> Result<(), String> {
    let out = Command::new("pkexec")
        .stdin(Stdio::null())
        .arg(program)
        .args(args)
        .output()
        .map_err(|e| format!("Failed launching pkexec: {e}"))?;
    if out.status.success() {
        return Ok(());
    }
    let stderr = String::from_utf8_lossy(&out.stderr);
    Err(pkexec_error_message(out.status.code(), &stderr))
}

#[derive(Debug, Clone)]
pub enum UndoAction {
    /// Created paths (new file/folder, paste copy, extract) -> undo trashes them.
    Created { label: String, paths: Vec<PathBuf> },
    /// Moved/renamed `(from -> to)` pairs -> undo moves `to -> from`.
    Moved {
        label: String,
        pairs: Vec<(PathBuf, PathBuf)>,
    },
    /// Trashed `(original_path, trash_file_path, trash_info_path)` -> undo restores.
    Trashed {
        label: String,
        items: Vec<TrashedRecord>,
    },
}

#[derive(Debug, Clone)]
pub struct TrashedRecord {
    pub original: PathBuf,
    pub trash_file: PathBuf,
    pub trash_info: PathBuf,
}

#[derive(Debug, Default)]
pub struct UndoManager {
    undo_stack: Vec<UndoAction>,
    redo_stack: Vec<UndoAction>,
}

impl UndoManager {
    pub fn push(&mut self, action: UndoAction) {
        self.undo_stack.push(action);
        if self.undo_stack.len() > 64 {
            self.undo_stack.remove(0);
        }
        self.redo_stack.clear();
    }

    pub fn can_undo(&self) -> bool {
        !self.undo_stack.is_empty()
    }

    #[allow(dead_code)]
    pub fn can_redo(&self) -> bool {
        !self.redo_stack.is_empty()
    }

    pub fn undo(&mut self) -> Result<Option<String>, String> {
        let Some(action) = self.undo_stack.pop() else {
            return Ok(None);
        };
        match action {
            UndoAction::Moved { label, pairs } => {
                let reversed: Vec<(PathBuf, PathBuf)> = pairs
                    .iter()
                    .rev()
                    .map(|(from, to)| (to.clone(), from.clone()))
                    .collect();
                batch_move_pairs(&reversed)?;
                self.redo_stack.push(UndoAction::Moved {
                    label: label.clone(),
                    pairs,
                });
                Ok(Some(format!("Undid {label}")))
            }
            UndoAction::Trashed { label, items } => {
                let mut restored = Vec::new();
                for rec in items.iter().rev() {
                    if let Some(parent) = rec.original.parent() {
                        let _ = fs::create_dir_all(parent);
                    }
                    let target = unique_destination(&rec.original);
                    move_path_any_fs(&rec.trash_file, &target)
                        .map_err(|e| format!("Restore failed: {e}"))?;
                    let _ = fs::remove_file(&rec.trash_info);
                    restored.push(target);
                }
                self.redo_stack.push(UndoAction::Created {
                    label: label.clone(),
                    paths: restored,
                });
                Ok(Some(format!("Undid {label}")))
            }
            UndoAction::Created { label, paths } => {
                let mut trashed = Vec::new();
                for p in paths.iter().rev() {
                    if p.exists() || p.symlink_metadata().is_ok() {
                        let rec = trash_path(p).map_err(|e| format!("Undo trash failed: {e}"))?;
                        trashed.push(rec);
                    }
                }
                self.redo_stack.push(UndoAction::Trashed {
                    label: label.clone(),
                    items: trashed,
                });
                Ok(Some(format!("Undid {label}")))
            }
        }
    }

    pub fn redo(&mut self) -> Result<Option<String>, String> {
        let Some(action) = self.redo_stack.pop() else {
            return Ok(None);
        };
        match action {
            UndoAction::Moved { label, pairs } => {
                batch_move_pairs(&pairs)?;
                self.undo_stack.push(UndoAction::Moved {
                    label: label.clone(),
                    pairs,
                });
                Ok(Some(format!("Redid {label}")))
            }
            UndoAction::Trashed { label, items } => {
                // Undo of Created turned it into Trashed; redoing restores it back.
                let mut restored = Vec::new();
                for rec in items.iter().rev() {
                    if let Some(parent) = rec.original.parent() {
                        let _ = fs::create_dir_all(parent);
                    }
                    let target = unique_destination(&rec.original);
                    move_path_any_fs(&rec.trash_file, &target)
                        .map_err(|e| format!("Redo restore failed: {e}"))?;
                    let _ = fs::remove_file(&rec.trash_info);
                    restored.push(target);
                }
                self.undo_stack.push(UndoAction::Created {
                    label: label.clone(),
                    paths: restored,
                });
                Ok(Some(format!("Redid {label}")))
            }
            UndoAction::Created { label, paths } => {
                // Undo of Trashed turned it into Created; redoing re-trashes it.
                let mut trashed = Vec::new();
                for p in paths.iter().rev() {
                    if p.exists() || p.symlink_metadata().is_ok() {
                        let rec = trash_path(p).map_err(|e| format!("Redo trash failed: {e}"))?;
                        trashed.push(rec);
                    }
                }
                self.undo_stack.push(UndoAction::Trashed {
                    label: label.clone(),
                    items: trashed,
                });
                Ok(Some(format!("Redid {label}")))
            }
        }
    }
}

pub fn unique_destination(desired: &Path) -> PathBuf {
    let is_dir = fs::symlink_metadata(desired)
        .map(|m| m.is_dir())
        .unwrap_or(false);
    unique_destination_for(desired, is_dir)
}

pub fn unique_destination_for(desired: &Path, is_dir: bool) -> PathBuf {
    if !desired.exists() && desired.symlink_metadata().is_err() {
        return desired.to_path_buf();
    }
    let parent = desired.parent().unwrap_or_else(|| Path::new("/"));
    let file_name = desired
        .file_name()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| "item".into());
    let (stem, ext) = if is_dir {
        (file_name, String::new())
    } else {
        split_name_ext(&file_name)
    };
    for idx in 1..10_000 {
        let candidate_name = if ext.is_empty() {
            format!("{stem} ({idx})")
        } else {
            format!("{stem} ({idx}).{ext}")
        };
        let candidate = parent.join(candidate_name);
        if !candidate.exists() && candidate.symlink_metadata().is_err() {
            return candidate;
        }
    }
    desired.to_path_buf()
}

pub fn split_name_ext(name: &str) -> (String, String) {
    if name.starts_with('.') && name[1..].find('.').is_none() {
        return (name.to_string(), String::new());
    }
    if let Some(dot) = name.rfind('.')
        && dot > 0
    {
        return (name[..dot].to_string(), name[dot + 1..].to_string());
    }
    (name.to_string(), String::new())
}

pub fn path_exists_or_symlink(p: &Path) -> bool {
    p.exists() || p.symlink_metadata().is_ok()
}

pub fn is_same_or_descendant(src: &Path, dst: &Path) -> bool {
    let canon_src = match src.canonicalize() {
        Ok(p) => p,
        Err(_) => return dst.starts_with(src),
    };
    let canon_dst = dst.canonicalize().ok().or_else(|| {
        dst.parent()
            .and_then(|p| p.canonicalize().ok())
            .map(|p| match dst.file_name() {
                Some(n) => p.join(n),
                None => p,
            })
    });
    match canon_dst {
        Some(cd) => cd == canon_src || cd.starts_with(&canon_src),
        None => dst.starts_with(src),
    }
}

pub fn copy_recursive(src: &Path, dst: &Path) -> io::Result<()> {
    let meta = fs::symlink_metadata(src)?;
    if meta.file_type().is_symlink() {
        let target = fs::read_link(src)?;
        std::os::unix::fs::symlink(target, dst)?;
        return Ok(());
    }
    if meta.is_dir() {
        if is_same_or_descendant(src, dst) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "Cannot copy a folder inside itself",
            ));
        }
        fs::create_dir_all(dst)?;
        for entry in fs::read_dir(src)? {
            let entry = entry?;
            let child_src = entry.path();
            let child_dst = dst.join(entry.file_name());
            copy_recursive(&child_src, &child_dst)?;
        }
        let _ = fs::set_permissions(dst, meta.permissions());
        Ok(())
    } else if meta.file_type().is_file() {
        fs::copy(src, dst)?;
        let _ = fs::set_permissions(dst, meta.permissions());
        Ok(())
    } else {
        Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "Cannot copy special file (FIFO, socket, or device)",
        ))
    }
}

pub fn move_path_any_fs(src: &Path, dst: &Path) -> io::Result<()> {
    if src == dst {
        return Ok(());
    }
    match fs::rename(src, dst) {
        Ok(()) => Ok(()),
        Err(err) if err.raw_os_error() == Some(18) => {
            // EXDEV: cross-device move -> copy + remove; clean partial dst on copy failure
            if let Err(copy_err) = copy_recursive(src, dst) {
                let _ = remove_permanent(dst);
                return Err(copy_err);
            }
            remove_permanent(src)?;
            Ok(())
        }
        Err(err) => Err(err),
    }
}

pub fn remove_permanent(path: &Path) -> io::Result<()> {
    let meta = fs::symlink_metadata(path)?;
    if meta.is_dir() && !meta.file_type().is_symlink() {
        fs::remove_dir_all(path)
    } else {
        fs::remove_file(path)
    }
}

pub fn remove_permanent_batch(paths: &[PathBuf]) -> Result<(), String> {
    for p in paths {
        if p.as_os_str().is_empty() || p == Path::new("/") {
            return Err("Refusing unsafe permanent delete target".into());
        }
    }
    let mut denied: Vec<&PathBuf> = Vec::new();
    for p in paths {
        if let Err(e) = remove_permanent(p) {
            if is_permission_error(&e) {
                denied.push(p);
            } else {
                return Err(format!("Delete failed: {e}"));
            }
        }
    }
    if !denied.is_empty() {
        let mut args: Vec<OsString> = Vec::with_capacity(denied.len() + 2);
        args.push(OsString::from("-rf"));
        args.push(OsString::from("--"));
        for p in denied {
            args.push(p.as_os_str().to_os_string());
        }
        run_pkexec("rm", &args)?;
    }
    Ok(())
}

pub type TransferResult = (Vec<PathBuf>, Vec<(PathBuf, PathBuf)>);

pub fn transfer_batch(
    is_move: bool,
    pairs: &[(PathBuf, PathBuf)],
) -> Result<TransferResult, String> {
    let mut created = Vec::new();
    let mut moved = Vec::new();
    let mut denied: Vec<(PathBuf, PathBuf)> = Vec::new();
    for (src, dst) in pairs {
        if is_move {
            match move_path_any_fs(src, dst) {
                Ok(()) => moved.push((src.clone(), dst.clone())),
                Err(e) if is_permission_error(&e) => denied.push((src.clone(), dst.clone())),
                Err(e) => return Err(format!("Move failed: {e}")),
            }
        } else {
            match copy_recursive(src, dst) {
                Ok(()) => created.push(dst.clone()),
                Err(e) if is_permission_error(&e) => denied.push((src.clone(), dst.clone())),
                Err(e) => return Err(format!("Copy failed: {e}")),
            }
        }
    }
    if !denied.is_empty() {
        if denied.len() == 1 {
            let (src, dst) = &denied[0];
            if is_move {
                run_pkexec("mv", &[OsStr::new("--"), src.as_os_str(), dst.as_os_str()])?;
            } else {
                run_pkexec(
                    "cp",
                    &[
                        OsStr::new("-a"),
                        OsStr::new("--"),
                        src.as_os_str(),
                        dst.as_os_str(),
                    ],
                )?;
            }
        } else {
            let step = if is_move {
                "while [ $# -ge 2 ]; do mv -- \"$1\" \"$2\" || exit $?; shift 2; done"
            } else {
                "while [ $# -ge 2 ]; do cp -a -- \"$1\" \"$2\" || exit $?; shift 2; done"
            };
            let mut args: Vec<OsString> = Vec::with_capacity(denied.len() * 2 + 3);
            args.push(OsString::from("-c"));
            args.push(OsString::from(step));
            args.push(OsString::from("--"));
            for (src, dst) in &denied {
                args.push(src.as_os_str().to_os_string());
                args.push(dst.as_os_str().to_os_string());
            }
            run_pkexec("sh", &args)?;
        }
        for (src, dst) in denied {
            if is_move {
                moved.push((src, dst));
            } else {
                created.push(dst);
            }
        }
    }
    Ok((created, moved))
}

fn allocate_trash_slot(abs: &Path) -> io::Result<(PathBuf, PathBuf)> {
    let trash_files = crate::model::trash_files_dir();
    let trash_info = crate::model::trash_info_dir();
    let base_name = abs
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "item".into());
    let encoded_path = percent_encode_path(&abs.to_string_lossy());
    let deletion_date = Local::now().format("%Y-%m-%dT%H:%M:%S").to_string();
    let info_content =
        format!("[Trash Info]\nPath={encoded_path}\nDeletionDate={deletion_date}\n");
    let mut counter = 0usize;
    loop {
        let candidate_name = if counter == 0 {
            base_name.clone()
        } else {
            format!("{base_name}.{counter}")
        };
        counter += 1;
        let df = trash_files.join(&candidate_name);
        let di = trash_info.join(format!("{candidate_name}.trashinfo"));
        if path_exists_or_symlink(&df) {
            continue;
        }
        match fs::OpenOptions::new().write(true).create_new(true).open(&di) {
            Ok(mut f) => {
                if let Err(e) = f.write_all(info_content.as_bytes()) {
                    let _ = fs::remove_file(&di);
                    return Err(e);
                }
                return Ok((df, di));
            }
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(e),
        }
    }
}

pub fn trash_batch(paths: &[PathBuf]) -> Result<Vec<TrashedRecord>, String> {
    let mut records = Vec::new();
    let mut denied = Vec::new();
    for p in paths {
        match trash_path(p) {
            Ok(rec) => records.push(rec),
            Err(e) if is_permission_error(&e) => denied.push(p.clone()),
            Err(e) => return Err(format!("Trash failed: {e}")),
        }
    }
    if !denied.is_empty() {
        let trash_files = crate::model::trash_files_dir();
        let trash_info = crate::model::trash_info_dir();
        fs::create_dir_all(&trash_files).map_err(|e| format!("Trash failed: {e}"))?;
        fs::create_dir_all(&trash_info).map_err(|e| format!("Trash failed: {e}"))?;
        let mut pending: Vec<TrashedRecord> = Vec::with_capacity(denied.len());
        for p in &denied {
            let abs = if p.is_absolute() {
                p.clone()
            } else {
                std::env::current_dir()
                    .map_err(|e| format!("Trash failed: {e}"))?
                    .join(p)
            };
            match allocate_trash_slot(&abs) {
                Ok((df, di)) => pending.push(TrashedRecord {
                    original: abs,
                    trash_file: df,
                    trash_info: di,
                }),
                Err(e) => {
                    for rec in &pending {
                        let _ = fs::remove_file(&rec.trash_info);
                    }
                    return Err(format!("Trash failed: {e}"));
                }
            }
        }
        let exec_res = if pending.len() == 1 {
            let rec = &pending[0];
            run_pkexec(
                "mv",
                &[
                    OsStr::new("--"),
                    rec.original.as_os_str(),
                    rec.trash_file.as_os_str(),
                ],
            )
        } else {
            let mut args: Vec<OsString> = Vec::with_capacity(pending.len() * 2 + 3);
            args.push(OsString::from("-c"));
            args.push(OsString::from(
                "while [ $# -ge 2 ]; do mv -- \"$1\" \"$2\" || exit $?; shift 2; done",
            ));
            args.push(OsString::from("--"));
            for rec in &pending {
                args.push(rec.original.as_os_str().to_os_string());
                args.push(rec.trash_file.as_os_str().to_os_string());
            }
            run_pkexec("sh", &args)
        };
        if let Err(err) = exec_res {
            for rec in &pending {
                let _ = fs::remove_file(&rec.trash_info);
            }
            return Err(err);
        }
        records.extend(pending);
    }
    Ok(records)
}

/// Move a file or directory to XDG Trash (`$XDG_DATA_HOME/Trash` on same device,
/// or per-mount trash via `gio trash` on external filesystems) with atomic `.trashinfo` creation.
pub fn trash_path(path: &Path) -> io::Result<TrashedRecord> {
    let trash_files = crate::model::trash_files_dir();
    let trash_info = crate::model::trash_info_dir();
    fs::create_dir_all(&trash_files)?;
    fs::create_dir_all(&trash_info)?;

    let abs = if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir()?.join(path)
    };
    if abs.starts_with(&trash_files) || abs.starts_with(&trash_info) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "Item is already in the Trash",
        ));
    }

    // For cross-device paths (e.g., USB drives), prefer `gio trash` so it uses per-mount
    // `.Trash-$uid` in O(1) without copying gigabytes into $HOME.
    let src_dev = fs::symlink_metadata(&abs).ok().map(|m| m.dev());
    let home_trash_dev = fs::metadata(&trash_files).ok().map(|m| m.dev());
    if let (Some(sd), Some(hd)) = (src_dev, home_trash_dev)
        && sd != hd
        && let Ok(out) = Command::new("gio")
            .stdin(Stdio::null())
            .args(["trash", "--"])
            .arg(&abs)
            .output()
        && out.status.success()
        && !path_exists_or_symlink(&abs)
        && let Some(rec) = find_mount_trash_record(&abs)
    {
        return Ok(rec);
    }

    let (dest_file, dest_info) = allocate_trash_slot(&abs)?;

    if let Err(e) = move_path_any_fs(&abs, &dest_file) {
        let _ = fs::remove_file(&dest_info);
        return Err(e);
    }
    Ok(TrashedRecord {
        original: abs,
        trash_file: dest_file,
        trash_info: dest_info,
    })
}

fn find_mount_trash_record(original: &Path) -> Option<TrashedRecord> {
    let base = original.file_name()?.to_string_lossy().to_string();
    let mut anc = original.parent();
    while let Some(dir) = anc {
        if let Ok(entries) = fs::read_dir(dir) {
            for ent in entries.flatten() {
                let name = ent.file_name().to_string_lossy().to_string();
                if name.starts_with(".Trash") {
                    let files_dir = ent.path().join("files");
                    let info_dir = ent.path().join("info");
                    let candidate_file = files_dir.join(&base);
                    let candidate_info = info_dir.join(format!("{base}.trashinfo"));
                    if path_exists_or_symlink(&candidate_file) && candidate_info.is_file() {
                        return Some(TrashedRecord {
                            original: original.to_path_buf(),
                            trash_file: candidate_file,
                            trash_info: candidate_info,
                        });
                    }
                }
            }
        }
        anc = dir.parent();
    }
    None
}

pub fn restore_from_trash(trash_item: &Path) -> Result<PathBuf, String> {
    let name = trash_item
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .ok_or_else(|| "Invalid trash item".to_string())?;
    let info_path = crate::model::trash_info_dir().join(format!("{name}.trashinfo"));
    let orig = crate::model::read_trash_original_path(&name)
        .map(|p| {
            let pb = PathBuf::from(&p);
            if pb.is_absolute() {
                pb
            } else {
                crate::config::home_dir().join(pb)
            }
        })
        .unwrap_or_else(|| crate::config::home_dir().join(&name));
    if let Some(parent) = orig.parent() {
        fs::create_dir_all(parent).map_err(|e| format!("Failed creating parent: {e}"))?;
    }
    let target = unique_destination(&orig);
    move_path_any_fs(trash_item, &target).map_err(|e| format!("Failed restoring item: {e}"))?;
    let _ = fs::remove_file(info_path);
    Ok(target)
}

pub fn empty_trash() -> Result<usize, String> {
    let files_dir = crate::model::trash_files_dir();
    let info_dir = crate::model::trash_info_dir();
    let mut paths = Vec::new();
    if files_dir.is_dir() {
        for entry in fs::read_dir(&files_dir).map_err(|e| e.to_string())? {
            let entry = entry.map_err(|e| e.to_string())?;
            paths.push(entry.path());
        }
        if !paths.is_empty() {
            remove_permanent_batch(&paths)?;
        }
    }
    if info_dir.is_dir() {
        for e in fs::read_dir(&info_dir).map_err(|e| e.to_string())?.flatten() {
            let _ = fs::remove_file(e.path());
        }
    }
    Ok(paths.len())
}

fn percent_encode_path(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        let keep = b.is_ascii_alphanumeric() || matches!(b, b'/' | b'-' | b'_' | b'.' | b'~');
        if keep {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

pub fn create_folder(parent: &Path, name: &str) -> Result<PathBuf, String> {
    let clean = validate_single_name(name)?;
    let target = parent.join(clean);
    if path_exists_or_symlink(&target) {
        return Err(format!("'{clean}' already exists"));
    }
    if let Err(e) = fs::create_dir(&target) {
        if is_permission_error(&e) {
            run_pkexec("mkdir", &[OsStr::new("-p"), OsStr::new("--"), target.as_os_str()])?;
        } else {
            return Err(format!("Could not create folder: {e}"));
        }
    }
    Ok(target)
}

pub fn create_file(parent: &Path, name: &str) -> Result<PathBuf, String> {
    let clean = validate_single_name(name)?;
    let target = parent.join(clean);
    if path_exists_or_symlink(&target) {
        return Err(format!("'{clean}' already exists"));
    }
    if let Err(e) = fs::write(&target, b"") {
        if is_permission_error(&e) {
            run_pkexec("touch", &[OsStr::new("--"), target.as_os_str()])?;
        } else {
            return Err(format!("Could not create file: {e}"));
        }
    }
    Ok(target)
}

/// Yazi-style `create`: names ending with `/` create a folder (including missing
/// parent segments); all other names create an empty file.
pub fn create_entry_yazi(parent: &Path, spec: &str) -> Result<(PathBuf, bool), String> {
    let trimmed = spec.trim();
    if trimmed.is_empty()
        || trimmed.starts_with('/')
        || trimmed.contains('\0')
        || trimmed.contains('\n')
        || trimmed.contains('\r')
    {
        return Err("Invalid file name".into());
    }
    let is_dir = trimmed.ends_with('/');
    let rel = trimmed.trim_end_matches('/');
    if rel.is_empty() {
        return Err("Invalid file name".into());
    }
    let mut target = parent.to_path_buf();
    for seg in rel.split('/') {
        if seg.is_empty() {
            return Err("Invalid file name".into());
        }
        let clean = validate_single_name(seg)?;
        target.push(clean);
    }
    if path_exists_or_symlink(&target) {
        return Err(format!("'{rel}' already exists"));
    }
    if is_dir {
        if let Err(e) = fs::create_dir_all(&target) {
            if is_permission_error(&e) {
                run_pkexec("mkdir", &[OsStr::new("-p"), OsStr::new("--"), target.as_os_str()])?;
            } else {
                return Err(format!("Could not create folder: {e}"));
            }
        }
    } else {
        let mut need_elevated = false;
        if let Some(p) = target.parent()
            && let Err(e) = fs::create_dir_all(p)
        {
            if is_permission_error(&e) {
                need_elevated = true;
            } else {
                return Err(format!("Could not create parent folder: {e}"));
            }
        }
        if !need_elevated && let Err(e) = fs::write(&target, b"") {
            if is_permission_error(&e) {
                need_elevated = true;
            } else {
                return Err(format!("Could not create file: {e}"));
            }
        }
        if need_elevated {
            let parent_dir = target.parent().unwrap_or(parent);
            run_pkexec(
                "sh",
                &[
                    OsStr::new("-c"),
                    OsStr::new("mkdir -p -- \"$1\" && : > \"$2\""),
                    OsStr::new("--"),
                    parent_dir.as_os_str(),
                    target.as_os_str(),
                ],
            )?;
        }
    }
    Ok((target, is_dir))
}

pub fn rename_single(path: &Path, new_name: &str) -> Result<PathBuf, String> {
    let clean = validate_single_name(new_name)?;
    let parent = path.parent().ok_or_else(|| "Cannot rename root".to_string())?;
    let target = parent.join(clean);
    if target == path {
        return Ok(target);
    }
    if path_exists_or_symlink(&target) {
        return Err(format!("'{clean}' already exists"));
    }
    if let Err(e) = fs::rename(path, &target) {
        if is_permission_error(&e) {
            run_pkexec(
                "mv",
                &[OsStr::new("--"), path.as_os_str(), target.as_os_str()],
            )?;
        } else {
            return Err(format!("Rename failed: {e}"));
        }
    }
    Ok(target)
}

pub fn validate_single_name(name: &str) -> Result<&str, String> {
    let clean = name.trim();
    if clean.is_empty()
        || clean == "."
        || clean == ".."
        || clean.contains('/')
        || clean.contains('\0')
        || clean.contains('\n')
        || clean.contains('\r')
    {
        return Err("Invalid file name".into());
    }
    if clean.len() > 255 {
        return Err("File name exceeds 255 bytes".into());
    }
    Ok(clean)
}

// ── Bulk Rename Engine ───────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CaseTransform {
    None,
    Lowercase,
    Uppercase,
    TitleCase,
}

#[derive(Debug, Clone)]
pub struct BulkRenameRule {
    pub find: String,
    pub replace: String,
    pub use_regex: bool,
    pub prefix: String,
    pub suffix: String,
    pub add_numbering: bool,
    pub number_start: usize,
    pub number_step: usize,
    pub number_pad: usize,
    pub number_at_start: bool,
    pub case_transform: CaseTransform,
    pub preserve_extension: bool,
}

impl Default for BulkRenameRule {
    fn default() -> Self {
        Self {
            find: String::new(),
            replace: String::new(),
            use_regex: false,
            prefix: String::new(),
            suffix: String::new(),
            add_numbering: false,
            number_start: 1,
            number_step: 1,
            number_pad: 2,
            number_at_start: false,
            case_transform: CaseTransform::None,
            preserve_extension: true,
        }
    }
}

#[derive(Debug, Clone)]
pub struct BulkRenamePreviewItem {
    pub source: PathBuf,
    pub old_name: String,
    pub new_name: String,
    pub destination: PathBuf,
    pub conflict: Option<String>,
}

pub fn preview_bulk_rename(
    sources: &[PathBuf],
    rule: &BulkRenameRule,
) -> Result<Vec<BulkRenamePreviewItem>, String> {
    let compiled_regex = if rule.use_regex && !rule.find.is_empty() {
        Some(Regex::new(&rule.find).map_err(|e| format!("Invalid regex: {e}"))?)
    } else {
        None
    };

    let source_set: HashSet<PathBuf> = sources.iter().cloned().collect();
    let mut seen_destinations: HashSet<PathBuf> = HashSet::new();
    let mut items = Vec::with_capacity(sources.len());

    for (idx, src) in sources.iter().enumerate() {
        let old_name = src
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_default();
        let is_dir = src
            .symlink_metadata()
            .map(|m| m.is_dir())
            .unwrap_or(false);
        let (mut stem, ext) = if rule.preserve_extension && !is_dir {
            split_name_ext(&old_name)
        } else {
            (old_name.clone(), String::new())
        };

        if let Some(ref re) = compiled_regex {
            stem = re.replace_all(&stem, rule.replace.as_str()).into_owned();
        } else if !rule.find.is_empty() {
            stem = stem.replace(&rule.find, &rule.replace);
        }

        stem = match rule.case_transform {
            CaseTransform::None => stem,
            CaseTransform::Lowercase => stem.to_lowercase(),
            CaseTransform::Uppercase => stem.to_uppercase(),
            CaseTransform::TitleCase => title_case(&stem),
        };

        let mut base = format!("{}{}{}", rule.prefix, stem, rule.suffix);
        if rule.add_numbering {
            let num = rule.number_start + idx * rule.number_step.max(1);
            let formatted = format!("{:0width$}", num, width = rule.number_pad.max(1));
            if rule.number_at_start {
                base = format!("{formatted}_{base}");
            } else {
                base = format!("{base}_{formatted}");
            }
        }

        let new_name = if ext.is_empty() {
            base
        } else {
            format!("{base}.{ext}")
        };

        let parent = src.parent().unwrap_or_else(|| Path::new("/"));
        let destination = parent.join(&new_name);
        let mut conflict = None;
        if validate_single_name(&new_name).is_err() {
            conflict = Some("Invalid name".into());
        } else if !seen_destinations.insert(destination.clone()) {
            conflict = Some("Duplicate target name".into());
        } else if destination != *src && path_exists_or_symlink(&destination) && !source_set.contains(&destination) {
            conflict = Some("Target already exists".into());
        }

        items.push(BulkRenamePreviewItem {
            source: src.clone(),
            old_name,
            new_name,
            destination,
            conflict,
        });
    }

    Ok(items)
}

pub fn execute_bulk_rename(items: &[BulkRenamePreviewItem]) -> Result<Vec<(PathBuf, PathBuf)>, String> {
    if let Some(bad) = items.iter().find(|i| i.conflict.is_some()) {
        return Err(format!(
            "Cannot bulk rename '{}': {}",
            bad.old_name,
            bad.conflict.as_deref().unwrap_or("conflict")
        ));
    }
    let pairs: Vec<(PathBuf, PathBuf)> = items
        .iter()
        .filter(|i| i.source != i.destination)
        .map(|i| (i.source.clone(), i.destination.clone()))
        .collect();
    batch_move_pairs(&pairs)?;
    Ok(pairs)
}

/// Two-phase rename via unique temporary names so cycles (e.g. a->b, b->a) succeed safely,
/// while refusing to silently overwrite any non-source existing destination.
pub fn batch_move_pairs(pairs: &[(PathBuf, PathBuf)]) -> Result<(), String> {
    if pairs.is_empty() {
        return Ok(());
    }
    let source_set: HashSet<&PathBuf> = pairs.iter().map(|(from, _)| from).collect();
    for (from, to) in pairs {
        if from != to && path_exists_or_symlink(to) && !source_set.contains(to) {
            return Err(format!(
                "Target '{}' already exists; aborting to prevent overwrite",
                to.display()
            ));
        }
    }
    let pid = std::process::id();
    let mut staged: Vec<(PathBuf, PathBuf, PathBuf)> = Vec::with_capacity(pairs.len());
    for (idx, (from, to)) in pairs.iter().enumerate() {
        let parent = from.parent().unwrap_or_else(|| Path::new("/"));
        let tmp = unique_destination(&parent.join(format!(".alis-rename-tmp-{pid}-{idx}")));
        if let Err(e) = move_path_any_fs(from, &tmp) {
            // Roll back already staged items
            for (orig, t, _) in staged.into_iter().rev() {
                let _ = move_path_any_fs(&t, &orig);
            }
            return Err(format!("Move failed for '{}': {e}", from.display()));
        }
        staged.push((from.clone(), tmp, to.clone()));
    }
    for (i, (_, tmp, to)) in staged.iter().enumerate() {
        if let Some(to_parent) = to.parent() {
            let _ = fs::create_dir_all(to_parent);
        }
        if let Err(e) = move_path_any_fs(tmp, to) {
            // Best-effort rollback of remaining & completed
            for (orig, _, done_to) in staged[..i].iter().rev() {
                let _ = move_path_any_fs(done_to, orig);
            }
            for (orig, rem_tmp, _) in staged[i..].iter().rev() {
                let _ = move_path_any_fs(rem_tmp, orig);
            }
            return Err(format!("Finalize move failed for '{}': {e}", to.display()));
        }
    }
    Ok(())
}

fn title_case(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut new_word = true;
    for ch in s.chars() {
        if ch.is_alphanumeric() {
            if new_word {
                out.extend(ch.to_uppercase());
                new_word = false;
            } else {
                out.extend(ch.to_lowercase());
            }
        } else {
            out.push(ch);
            new_word = true;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bulk_rename_and_undo_redo_cycle() {
        let dir = std::env::temp_dir().join(format!("alis-files-fsops-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();

        let a = create_file(&dir, "photo_a.jpg").unwrap();
        let b = create_file(&dir, "photo_b.jpg").unwrap();

        let rule = BulkRenameRule {
            find: "photo_".into(),
            replace: "trip_".into(),
            add_numbering: true,
            number_start: 1,
            number_step: 1,
            number_pad: 3,
            ..Default::default()
        };
        let preview = preview_bulk_rename(&[a.clone(), b.clone()], &rule).unwrap();
        assert_eq!(preview[0].new_name, "trip_a_001.jpg");
        assert_eq!(preview[1].new_name, "trip_b_002.jpg");
        assert!(preview.iter().all(|p| p.conflict.is_none()));

        let pairs = execute_bulk_rename(&preview).unwrap();
        let mut undo = UndoManager::default();
        undo.push(UndoAction::Moved {
            label: "Bulk Rename".into(),
            pairs,
        });
        assert!(dir.join("trip_a_001.jpg").exists());
        assert!(dir.join("trip_b_002.jpg").exists());
        assert!(!a.exists());

        assert!(undo.undo().unwrap().is_some());
        assert!(a.exists());
        assert!(b.exists());
        assert!(!dir.join("trip_a_001.jpg").exists());

        assert!(undo.redo().unwrap().is_some());
        assert!(dir.join("trip_a_001.jpg").exists());

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn batch_move_handles_swap_cycle() {
        let dir = std::env::temp_dir().join(format!("alis-files-swap-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let a = dir.join("a.txt");
        let b = dir.join("b.txt");
        fs::write(&a, "AAA").unwrap();
        fs::write(&b, "BBB").unwrap();
        batch_move_pairs(&[(a.clone(), b.clone()), (b.clone(), a.clone())]).unwrap();
        assert_eq!(fs::read_to_string(&a).unwrap(), "BBB");
        assert_eq!(fs::read_to_string(&b).unwrap(), "AAA");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn copy_recursive_rejects_descendant_and_symlink_overwrite_blocked() {
        let dir = std::env::temp_dir().join(format!("alis-files-guard-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        let sub = dir.join("parent/child");
        fs::create_dir_all(&sub).unwrap();
        let err = copy_recursive(&dir.join("parent"), &sub.join("parent"));
        assert!(err.is_err());

        // Broken symlink must not be overwritten by create_file
        let broken = dir.join("dangling.txt");
        std::os::unix::fs::symlink("/nonexistent/target", &broken).unwrap();
        assert!(create_file(&dir, "dangling.txt").is_err());

        // Dotted folder names append " (1)" instead of splitting after the last dot
        let dotted = dir.join("release-v1.0");
        fs::create_dir_all(&dotted).unwrap();
        assert_eq!(unique_destination(&dotted), dir.join("release-v1.0 (1)"));

        // Overwrite guard in batch_move_pairs refuses clobbering an unrelated existing file
        let f1 = dir.join("orig.txt");
        let f2 = dir.join("occupied.txt");
        fs::write(&f1, "1").unwrap();
        fs::write(&f2, "2").unwrap();
        assert!(batch_move_pairs(&[(f1.clone(), f2.clone())]).is_err());
        assert_eq!(fs::read_to_string(&f2).unwrap(), "2");

        // validate_single_name rejects newlines and >255 byte names
        assert!(validate_single_name("bad\nname").is_err());
        assert!(validate_single_name(&"a".repeat(256)).is_err());

        // Yazi-style create_entry_yazi: trailing '/' -> folder, else file
        let (f_created, f_is_dir) = create_entry_yazi(&dir, "notes.txt").unwrap();
        assert!(!f_is_dir);
        assert!(f_created.is_file());
        let (d_created, d_is_dir) = create_entry_yazi(&dir, "docs/").unwrap();
        assert!(d_is_dir);
        assert!(d_created.is_dir());
        let (nf_created, nf_is_dir) = create_entry_yazi(&dir, "nested/sub/mod.rs").unwrap();
        assert!(!nf_is_dir);
        assert!(nf_created.is_file());
        let (nd_created, nd_is_dir) = create_entry_yazi(&dir, "nested/deep/dir/").unwrap();
        assert!(nd_is_dir);
        assert!(nd_created.is_dir());
        assert!(create_entry_yazi(&dir, "../escape").is_err());
        assert!(create_entry_yazi(&dir, "/abs").is_err());
        assert!(create_entry_yazi(&dir, "a//b").is_err());
        assert!(create_entry_yazi(&dir, "/").is_err());
        assert!(create_entry_yazi(&dir, "").is_err());

        // Permission error & pkexec error mapping helpers
        assert!(is_permission_error(&io::Error::from_raw_os_error(13)));
        assert!(is_permission_error(&io::Error::from_raw_os_error(1)));
        assert!(!is_permission_error(&io::Error::from_raw_os_error(2)));
        assert_eq!(pkexec_error_message(Some(126), ""), "Authentication cancelled");
        assert_eq!(
            pkexec_error_message(Some(1), "Error executing command as another user: Request dismissed"),
            "Authentication cancelled"
        );
        assert_eq!(
            pkexec_error_message(Some(127), ""),
            "Polkit authentication failed or pkexec is unavailable"
        );
        assert_eq!(pkexec_error_message(Some(1), "Custom denied"), "Custom denied");

        let _ = fs::remove_dir_all(&dir);
    }
}
