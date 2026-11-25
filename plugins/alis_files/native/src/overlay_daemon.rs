use crate::alis_actions;
use crate::archive::{self, ArchiveFormat};
use crate::config::{AppConfig, SortField, SortOrder, config_path, home_dir};
use crate::disk_usage;
use crate::fs_ops::{
    self, UndoAction, UndoManager, create_entry_yazi, create_file, create_folder, empty_trash,
    remove_permanent_batch, rename_single, restore_from_trash, transfer_batch, trash_batch,
    unique_destination_for,
};
use crate::git;
use crate::model::{
    FileEntry, FileKind, format_permissions, format_size, format_time, is_trash_dir,
    read_directory, sort_entries, trash_files_dir,
};
use crate::mounts;
use crate::properties;
use crate::search;
use crate::thumbnails;
use serde::Deserialize;
use serde_json::{Value, json};
use std::collections::{HashSet, VecDeque};
use std::fs;
use std::io::{self, BufRead, BufWriter, Read, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Deserialize)]
struct RpcRequest {
    id: u64,
    cmd: String,
    #[serde(default)]
    params: Value,
}

#[derive(Default)]
struct DaemonState {
    config: AppConfig,
    undo: UndoManager,
    active_search_cancel: Option<Arc<AtomicBool>>,
    active_props_dir_cancel: Option<Arc<AtomicBool>>,
}

type SharedDaemon = Arc<Mutex<DaemonState>>;
type SharedWriter = Arc<Mutex<BufWriter<io::Stdout>>>;

const OVERLAY_THUMB_MAX_PENDING: usize = 256;

struct ThumbJob {
    id: u64,
    epoch: u64,
    params: Value,
}

struct ThumbPool {
    queue: Mutex<VecDeque<ThumbJob>>,
    cvar: Condvar,
    closed: AtomicBool,
    generation: Arc<AtomicU64>,
    writer: SharedWriter,
}

fn send_thumb_cancelled(writer: &SharedWriter, job: &ThumbJob) {
    let path = job
        .params
        .get("path")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    send_result(
        writer,
        job.id,
        Ok(json!({ "path": path, "thumb_path": "", "cancelled": true })),
    );
}

impl ThumbPool {
    fn start(writer: SharedWriter, generation: Arc<AtomicU64>) -> Arc<Self> {
        let pool = Arc::new(Self {
            queue: Mutex::new(VecDeque::with_capacity(64)),
            cvar: Condvar::new(),
            closed: AtomicBool::new(false),
            generation,
            writer: writer.clone(),
        });
        let workers = std::thread::available_parallelism()
            .map(|n| n.get().clamp(2, 4))
            .unwrap_or(2);
        for idx in 0..workers {
            let p = pool.clone();
            let wr = writer.clone();
            let _ = std::thread::Builder::new()
                .name(format!("alis-files-thumb-{idx}"))
                .spawn(move || p.worker_loop(&wr));
        }
        pool
    }

    fn enqueue(&self, id: u64, params: Value) {
        let epoch = self.generation.load(Ordering::Relaxed);
        let mut evicted = Vec::new();
        if let Ok(mut q) = self.queue.lock() {
            while q.len() >= OVERLAY_THUMB_MAX_PENDING {
                if let Some(old) = q.pop_front() {
                    evicted.push(old);
                }
            }
            q.push_back(ThumbJob { id, epoch, params });
            self.cvar.notify_one();
        }
        for job in &evicted {
            send_thumb_cancelled(&self.writer, job);
        }
    }

    fn cancel_stale(&self) {
        self.generation.fetch_add(1, Ordering::Relaxed);
        let drained: Vec<ThumbJob> = if let Ok(mut q) = self.queue.lock() {
            q.drain(..).collect()
        } else {
            Vec::new()
        };
        for job in &drained {
            send_thumb_cancelled(&self.writer, job);
        }
    }

    fn shutdown(&self) {
        self.closed.store(true, Ordering::Relaxed);
        let drained: Vec<ThumbJob> = if let Ok(mut q) = self.queue.lock() {
            q.drain(..).collect()
        } else {
            Vec::new()
        };
        self.cvar.notify_all();
        for job in &drained {
            send_thumb_cancelled(&self.writer, job);
        }
    }

    fn worker_loop(&self, writer: &SharedWriter) {
        loop {
            let job = {
                let mut q = match self.queue.lock() {
                    Ok(g) => g,
                    Err(poisoned) => poisoned.into_inner(),
                };
                while q.is_empty() && !self.closed.load(Ordering::Relaxed) {
                    q = match self.cvar.wait(q) {
                        Ok(g) => g,
                        Err(poisoned) => poisoned.into_inner(),
                    };
                }
                if self.closed.load(Ordering::Relaxed) {
                    return;
                }
                // LIFO prioritizes the most recently scrolled-into-view items.
                q.pop_back()
            };
            let Some(job) = job else {
                continue;
            };
            if job.epoch != self.generation.load(Ordering::Relaxed) {
                send_thumb_cancelled(writer, &job);
                continue;
            }
            let res = cmd_thumb(&job.params);
            if job.epoch == self.generation.load(Ordering::Relaxed) {
                send_result(writer, job.id, res);
            } else {
                send_thumb_cancelled(writer, &job);
            }
        }
    }
}

/// Runs the persistent newline-delimited JSON-RPC stdio bridge for the Alis Abyss Overlay.
/// Starts in <5ms with zero GTK display dependency; heavy operations run on background threads
/// and thumbnails share a bounded worker pool so memory stays compact and navigation stays instant.
pub fn run_stdio_daemon() {
    let state = Arc::new(Mutex::new(DaemonState {
        config: AppConfig::load(),
        undo: UndoManager::default(),
        active_search_cancel: None,
        active_props_dir_cancel: None,
    }));
    let writer: SharedWriter = Arc::new(Mutex::new(BufWriter::new(io::stdout())));
    let thumb_gen = Arc::new(AtomicU64::new(1));
    let thumb_pool = ThumbPool::start(writer.clone(), thumb_gen);

    let stdin = io::stdin();
    for line_res in stdin.lock().lines() {
        let Ok(line) = line_res else {
            break;
        };
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let req: RpcRequest = match serde_json::from_str(trimmed) {
            Ok(r) => r,
            Err(e) => {
                send_error(&writer, 0, format!("Invalid JSON request: {e}"));
                continue;
            }
        };

        if req.cmd == "thumb" {
            thumb_pool.enqueue(req.id, req.params);
            continue;
        }

        if req.cmd == "list" {
            thumb_pool.cancel_stale();
        }

        let async_cmds = matches!(
            req.cmd.as_str(),
            "git_status"
                | "search"
                | "mkdir"
                | "mkfile"
                | "create"
                | "rename"
                | "copy"
                | "move"
                | "trash"
                | "restore"
                | "delete_permanent"
                | "empty_trash"
                | "undo"
                | "redo"
                | "compress"
                | "extract"
                | "disk_usage"
                | "mount"
                | "unmount"
                | "alis_action"
                | "read_text_preview"
                | "properties"
                | "properties_dir_size"
                | "checksum"
                | "set_permissions"
                | "set_default_app"
        );

        if async_cmds {
            let st = state.clone();
            let wr = writer.clone();
            std::thread::spawn(move || {
                let res = handle_command(&req.cmd, &req.params, &st);
                send_result(&wr, req.id, res);
            });
        } else {
            let res = handle_command(&req.cmd, &req.params, &state);
            send_result(&writer, req.id, res);
        }
    }
    thumb_pool.shutdown();
}

fn send_result(writer: &SharedWriter, id: u64, res: Result<Value, String>) {
    match res {
        Ok(data) => send_json(
            writer,
            &json!({
                "id": id,
                "ok": true,
                "data": data,
            }),
        ),
        Err(err) => send_error(writer, id, err),
    }
}

fn send_error(writer: &SharedWriter, id: u64, err: String) {
    send_json(
        writer,
        &json!({
            "id": id,
            "ok": false,
            "error": err,
        }),
    );
}

fn send_json(writer: &SharedWriter, val: &Value) {
    if let Ok(mut guard) = writer.lock() {
        let _ = serde_json::to_writer(&mut *guard, val);
        let _ = guard.write_all(b"\n");
        let _ = guard.flush();
    }
}

fn handle_command(cmd: &str, params: &Value, state: &SharedDaemon) -> Result<Value, String> {
    match cmd {
        "init" => cmd_init(state),
        "list" => cmd_list(params, state),
        "git_status" => cmd_git_status(params),
        "search" => cmd_search(params, state),
        "thumb" => cmd_thumb(params),
        "drives" => Ok(json!({ "drives": list_drives_json() })),
        "mount" => {
            let dev = req_str(params, "block_device")?;
            let mp = mounts::mount_volume(&dev)?;
            Ok(json!({ "mount_point": mp.to_string_lossy(), "drives": list_drives_json() }))
        }
        "unmount" => {
            let mp = PathBuf::from(req_str(params, "mount_point")?);
            let dev = opt_str(params, "block_device");
            let removable = params
                .get("is_removable")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            let msg = mounts::safe_unmount(&mp, dev.as_deref(), removable)?;
            Ok(json!({ "message": msg, "drives": list_drives_json() }))
        }
        "open" => {
            let p = PathBuf::from(req_str(params, "path")?);
            let entry = FileEntry::from_path(p.clone())
                .map_err(|e| format!("Cannot inspect '{}': {e}", p.display()))?;
            if entry.is_broken_symlink {
                return Err(format!("Broken symbolic link: {}", entry.name));
            }
            alis_actions::open_with_default_app(&p)?;
            Ok(json!({ "opened": p.to_string_lossy() }))
        }
        "open_window" => {
            let path = opt_str(params, "path");
            let select_path = opt_str(params, "select_path");
            let exe = std::env::current_exe()
                .map_err(|e| format!("Could not resolve alis-files binary: {e}"))?;
            let mut command = Command::new(exe);
            command.arg("--new");
            if let Some(sel) = select_path {
                command.args(["--select", &sel]);
            } else if let Some(p) = path {
                command.arg(p);
            }
            command
                .spawn()
                .map_err(|e| format!("Failed launching Alis Files window: {e}"))?;
            Ok(json!({ "launched": true }))
        }
        "mkdir" => {
            let dir = PathBuf::from(req_str(params, "dir")?);
            let name = req_str(params, "name")?;
            let created = create_folder(&dir, &name)?;
            if let Ok(mut st) = state.lock() {
                st.undo.push(UndoAction::Created {
                    label: format!("Create folder '{name}'"),
                    paths: vec![created.clone()],
                });
            }
            Ok(json!({ "created": created.to_string_lossy(), "message": format!("Created folder '{name}'") }))
        }
        "mkfile" => {
            let dir = PathBuf::from(req_str(params, "dir")?);
            let name = req_str(params, "name")?;
            let created = create_file(&dir, &name)?;
            if let Ok(mut st) = state.lock() {
                st.undo.push(UndoAction::Created {
                    label: format!("Create file '{name}'"),
                    paths: vec![created.clone()],
                });
            }
            Ok(json!({ "created": created.to_string_lossy(), "message": format!("Created '{name}'") }))
        }
        "create" => {
            let dir = PathBuf::from(req_str(params, "dir")?);
            let name = req_str(params, "name")?;
            let (created, is_dir) = create_entry_yazi(&dir, &name)?;
            let clean = name.trim().trim_end_matches('/');
            let msg = if is_dir {
                format!("Created folder '{clean}'")
            } else {
                format!("Created '{clean}'")
            };
            if let Ok(mut st) = state.lock() {
                st.undo.push(UndoAction::Created {
                    label: msg.clone(),
                    paths: vec![created.clone()],
                });
            }
            Ok(json!({
                "created": created.to_string_lossy(),
                "is_dir": is_dir,
                "message": msg
            }))
        }
        "rename" => {
            let path = PathBuf::from(req_str(params, "path")?);
            let new_name = req_str(params, "new_name")?;
            let old_name = path
                .file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_default();
            let dest = rename_single(&path, &new_name)?;
            if dest != path
                && let Ok(mut st) = state.lock()
            {
                st.undo.push(UndoAction::Moved {
                    label: format!("Rename '{old_name}'"),
                    pairs: vec![(path.clone(), dest.clone())],
                });
            }
            Ok(json!({ "path": dest.to_string_lossy(), "message": format!("Renamed to '{new_name}'") }))
        }
        "copy" | "move" => cmd_transfer(cmd == "move", params, state),
        "trash" => cmd_trash(params, state),
        "restore" => {
            let paths = req_paths(params, "paths")?;
            let mut restored = Vec::new();
            for p in paths {
                if let Ok(target) = restore_from_trash(&p) {
                    restored.push(target.to_string_lossy().to_string());
                }
            }
            Ok(json!({
                "restored": restored,
                "message": format!("Restored {} item(s)", restored.len()),
                "trash_count": count_trash_items(),
            }))
        }
        "delete_permanent" => {
            let paths = req_paths(params, "paths")?;
            let n = paths.len();
            let trash_dir = trash_files_dir();
            remove_permanent_batch(&paths)?;
            for p in &paths {
                if p.starts_with(&trash_dir)
                    && let Some(name) = p.file_name().map(|s| s.to_string_lossy().to_string())
                {
                    let _ = fs::remove_file(
                        crate::model::trash_info_dir().join(format!("{name}.trashinfo")),
                    );
                }
            }
            Ok(json!({
                "deleted": n,
                "message": format!("Permanently deleted {n} item(s)"),
                "trash_count": count_trash_items(),
            }))
        }
        "empty_trash" => {
            let n = empty_trash()?;
            Ok(json!({
                "deleted": n,
                "message": format!("Emptied {n} item(s) from Trash"),
                "trash_count": 0,
            }))
        }
        "undo" => {
            let msg = {
                let mut st = state.lock().map_err(|_| "State lock poisoned".to_string())?;
                st.undo.undo()?
            };
            let (can_undo, can_redo) = undo_flags(state);
            Ok(json!({
                "message": msg.unwrap_or_else(|| "Nothing to undo".into()),
                "can_undo": can_undo,
                "can_redo": can_redo,
                "trash_count": count_trash_items(),
            }))
        }
        "redo" => {
            let msg = {
                let mut st = state.lock().map_err(|_| "State lock poisoned".to_string())?;
                st.undo.redo()?
            };
            let (can_undo, can_redo) = undo_flags(state);
            Ok(json!({
                "message": msg.unwrap_or_else(|| "Nothing to redo".into()),
                "can_undo": can_undo,
                "can_redo": can_redo,
                "trash_count": count_trash_items(),
            }))
        }
        "compress" => {
            let sources = req_paths(params, "paths")?;
            let dest_dir = PathBuf::from(req_str(params, "dest_dir")?);
            let name = req_str(params, "name")?;
            let fmt = match opt_str(params, "format").as_deref() {
                Some("tar.gz") => ArchiveFormat::TarGz,
                Some("tar.zst") => ArchiveFormat::TarZst,
                Some("tar.xz") => ArchiveFormat::TarXz,
                Some("7z") => ArchiveFormat::SevenZ,
                _ => ArchiveFormat::Zip,
            };
            let out = archive::compress(&sources, &dest_dir, &name, fmt)?;
            if let Ok(mut st) = state.lock() {
                st.undo.push(UndoAction::Created {
                    label: "Create archive".into(),
                    paths: vec![out.clone()],
                });
            }
            Ok(json!({ "archive": out.to_string_lossy(), "message": "Archive created" }))
        }
        "extract" => {
            let p = PathBuf::from(req_str(params, "path")?);
            let into_sub = params
                .get("into_subfolder")
                .and_then(|v| v.as_bool())
                .unwrap_or(true);
            let out = archive::extract(&p, into_sub)?;
            if into_sub && let Ok(mut st) = state.lock() {
                st.undo.push(UndoAction::Created {
                    label: "Extract archive".into(),
                    paths: vec![out.clone()],
                });
            }
            Ok(json!({ "target": out.to_string_lossy(), "message": format!("Extracted to {}", out.display()) }))
        }
        "disk_usage" => {
            let p = PathBuf::from(req_str(params, "path")?);
            let cancel = Arc::new(AtomicBool::new(false));
            let report = disk_usage::analyze_directory(&p, &cancel);
            let children: Vec<Value> = report
                .children
                .into_iter()
                .take(80)
                .map(|c| {
                    json!({
                        "name": c.name,
                        "path": c.path.to_string_lossy(),
                        "is_dir": c.is_dir,
                        "bytes": c.bytes,
                        "size_label": format_size(c.bytes),
                        "item_count": c.item_count,
                    })
                })
                .collect();
            Ok(json!({
                "total_bytes": report.total_bytes,
                "total_label": format_size(report.total_bytes),
                "total_items": report.total_items,
                "children": children,
            }))
        }
        "alis_action" => cmd_alis_action(params),
        "sync_config" => cmd_sync_config(state),
        "save_session" => cmd_save_session(params, state),
        "bookmark_add" => {
            let p = PathBuf::from(req_str(params, "path")?);
            let fresh = AppConfig::load_from(&config_path());
            let mut st = state.lock().map_err(|_| "State lock poisoned".to_string())?;
            st.config = fresh;
            let added = st.config.add_bookmark(&p);
            let _ = st.config.save();
            Ok(json!({ "added": added, "bookmarks": bookmarks_json(&st.config) }))
        }
        "bookmark_remove" => {
            let p = req_str(params, "path")?;
            let fresh = AppConfig::load_from(&config_path());
            let mut st = state.lock().map_err(|_| "State lock poisoned".to_string())?;
            st.config = fresh;
            let removed = st.config.remove_bookmark(&p);
            let _ = st.config.save();
            Ok(json!({ "removed": removed, "bookmarks": bookmarks_json(&st.config) }))
        }
        "save_config" => cmd_save_config(params, state),
        "read_text_preview" => cmd_read_text_preview(params),
        "properties" => {
            let p = PathBuf::from(req_str(params, "path")?);
            let git_status = opt_str(params, "git_status");
            let props = properties::inspect_item(&p, git_status)?;
            Ok(json!({ "properties": props }))
        }
        "properties_dir_size" => {
            let p = PathBuf::from(req_str(params, "path")?);
            let cancel = Arc::new(AtomicBool::new(false));
            if let Ok(mut st) = state.lock()
                && let Some(prev) = st.active_props_dir_cancel.replace(cancel.clone())
            {
                prev.store(true, Ordering::Relaxed);
            }
            let (size, size_on_disk, item_count) =
                disk_usage::dir_size_and_disk_recursive(&p, &cancel);
            let cancelled = cancel.load(Ordering::Relaxed);
            Ok(json!({
                "path": p.to_string_lossy(),
                "size": size,
                "size_label": format_size(size),
                "size_on_disk": size_on_disk,
                "size_on_disk_label": format_size(size_on_disk),
                "item_count": item_count,
                "cancelled": cancelled,
            }))
        }
        "checksum" => {
            let p = PathBuf::from(req_str(params, "path")?);
            let algo = req_str(params, "algo")?;
            let digest = properties::compute_checksum(&p, &algo)?;
            Ok(json!({ "path": p.to_string_lossy(), "algo": algo, "digest": digest }))
        }
        "set_permissions" => {
            let p = PathBuf::from(req_str(params, "path")?);
            let mode = params
                .get("mode")
                .and_then(|v| v.as_u64())
                .ok_or_else(|| "Missing numeric parameter 'mode'".to_string())?;
            let props = properties::set_mode(&p, mode as u32)?;
            Ok(json!({
                "properties": props,
                "message": format!("Permissions updated ({})", props.permissions_label),
            }))
        }
        "set_default_app" => {
            let mime = req_str(params, "mime_type")?;
            let app_id = req_str(params, "app_id")?;
            properties::set_default_app(&mime, &app_id)?;
            Ok(json!({
                "mime_type": mime,
                "app_id": app_id,
                "message": "Default application updated",
            }))
        }
        other => Err(format!("Unknown daemon command: {other}")),
    }
}

fn cmd_init(state: &SharedDaemon) -> Result<Value, String> {
    let fresh_cfg = AppConfig::load_from(&config_path());
    let home = home_dir();
    let trash = trash_files_dir();
    let places = build_places_json(&home, &trash);
    let drives = list_drives_json();

    let (cfg_json, bookmarks_val, recent_val, can_undo, can_redo) = {
        let mut st = state.lock().map_err(|_| "State lock poisoned".to_string())?;
        st.config = fresh_cfg;
        let cfg_val = serde_json::to_value(&st.config).unwrap_or_else(|_| json!({}));
        let bm = bookmarks_json(&st.config);
        let rec = json!(st.config.recent_folders);
        (
            cfg_val,
            bm,
            rec,
            st.undo.can_undo(),
            st.undo.can_redo(),
        )
    };

    Ok(json!({
        "home": home.to_string_lossy(),
        "trash": trash.to_string_lossy(),
        "places": places,
        "bookmarks": bookmarks_val,
        "drives": drives,
        "config": cfg_json,
        "recent": recent_val,
        "trash_count": count_trash_items(),
        "can_undo": can_undo,
        "can_redo": can_redo,
    }))
}

fn cmd_list(params: &Value, state: &SharedDaemon) -> Result<Value, String> {
    let raw_path = opt_str(params, "path").unwrap_or_else(|| home_dir().to_string_lossy().to_string());
    let mut dir = expand_path(&raw_path);
    let mut recovered_from: Option<String> = None;

    if is_trash_dir(&dir) {
        let _ = fs::create_dir_all(&dir);
    } else if !dir.is_dir() {
        recovered_from = Some(dir.to_string_lossy().to_string());
        dir = dir
            .ancestors()
            .find(|p| p.is_dir())
            .map(Path::to_path_buf)
            .unwrap_or_else(home_dir);
    }

    let (show_hidden, sort_field, sort_order, dirs_first) = {
        let st = state.lock().map_err(|_| "State lock poisoned".to_string())?;
        let show = params
            .get("show_hidden")
            .and_then(|v| v.as_bool())
            .unwrap_or(st.config.show_hidden);
        let sf = match opt_str(params, "sort_field").as_deref() {
            Some("size") => SortField::Size,
            Some("modified") => SortField::Modified,
            Some("kind") => SortField::Kind,
            Some("name") => SortField::Name,
            _ => st.config.sort_field,
        };
        let so = match opt_str(params, "sort_order").as_deref() {
            Some("desc") => SortOrder::Desc,
            Some("asc") => SortOrder::Asc,
            _ => st.config.sort_order,
        };
        let df = params
            .get("dirs_first")
            .and_then(|v| v.as_bool())
            .unwrap_or(st.config.directories_first);
        (show, sf, so, df)
    };

    let mut items = read_directory(&dir, show_hidden)
        .map_err(|e| format!("Cannot open {}: {e}", dir.display()))?;

    if let Some(filter) = opt_str(params, "filter") {
        let q = filter.trim().to_lowercase();
        if !q.is_empty() {
            items.retain(|e| e.name.to_lowercase().contains(&q));
        }
    }

    sort_entries(&mut items, sort_field, sort_order, dirs_first);

    let (can_undo, can_redo) = {
        let mut st = state.lock().map_err(|_| "State lock poisoned".to_string())?;
        if !is_trash_dir(&dir) {
            st.config.push_recent(&dir);
        }
        (st.undo.can_undo(), st.undo.can_redo())
    };

    let (total_bytes, used_bytes) = mounts::filesystem_space(&dir);
    let free_bytes = total_bytes.saturating_sub(used_bytes);
    let entries_json: Vec<Value> = items.iter().map(entry_to_json).collect();
    let dir_entry = FileEntry::from_path(dir.clone())
        .ok()
        .map(|e| entry_to_json(&e));

    Ok(json!({
        "path": dir.to_string_lossy(),
        "parent": dir.parent().map(|p| p.to_string_lossy().to_string()),
        "is_trash": is_trash_dir(&dir),
        "recovered_from": recovered_from,
        "dir_entry": dir_entry,
        "entries": entries_json,
        "total_bytes": total_bytes,
        "free_bytes": free_bytes,
        "free_label": format_size(free_bytes),
        "trash_count": count_trash_items(),
        "can_undo": can_undo,
        "can_redo": can_redo,
    }))
}

fn cmd_git_status(params: &Value) -> Result<Value, String> {
    let dir = PathBuf::from(req_str(params, "path")?);
    if !dir.is_dir() || is_trash_dir(&dir) {
        return Ok(json!({ "path": dir.to_string_lossy(), "branch": null, "badges": {} }));
    }
    let st = git::inspect_directory(&dir);
    let canon_dir = dir.canonicalize().unwrap_or_else(|_| dir.clone());
    let mut badges_map = serde_json::Map::new();
    for (p, badge) in &st.badges {
        badges_map.insert(
            p.to_string_lossy().to_string(),
            json!({
                "short": badge.short_label(),
                "desc": badge.description(),
                "kind": match badge {
                    git::GitBadge::Modified => "modified",
                    git::GitBadge::Added => "added",
                    git::GitBadge::Untracked => "untracked",
                    git::GitBadge::Deleted => "deleted",
                    git::GitBadge::Conflict => "conflict",
                    git::GitBadge::Ignored => "ignored",
                }
            }),
        );
        if canon_dir != dir
            && let Some(name) = p.file_name()
        {
            badges_map
                .entry(dir.join(name).to_string_lossy().to_string())
                .or_insert_with(|| {
                    json!({
                        "short": badge.short_label(),
                        "desc": badge.description(),
                        "kind": match badge {
                            git::GitBadge::Modified => "modified",
                            git::GitBadge::Added => "added",
                            git::GitBadge::Untracked => "untracked",
                            git::GitBadge::Deleted => "deleted",
                            git::GitBadge::Conflict => "conflict",
                            git::GitBadge::Ignored => "ignored",
                        }
                    })
                });
        }
    }
    Ok(json!({
        "path": dir.to_string_lossy(),
        "branch": st.branch,
        "badges": Value::Object(badges_map),
    }))
}

fn cmd_search(params: &Value, state: &SharedDaemon) -> Result<Value, String> {
    let dir = PathBuf::from(req_str(params, "path")?);
    let query = req_str(params, "query")?;
    let include_hidden = params
        .get("show_hidden")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let max_results = params
        .get("max_results")
        .and_then(|v| v.as_u64())
        .unwrap_or(300) as usize;

    let cancel = Arc::new(AtomicBool::new(false));
    if let Ok(mut st) = state.lock()
        && let Some(prev) = st.active_search_cancel.replace(cancel.clone())
    {
        prev.store(true, Ordering::Relaxed);
    }

    let mut hits = search::recursive_search(&dir, &query, include_hidden, max_results, &cancel);
    let (sf, so, df) = {
        let st = state.lock().map_err(|_| "State lock poisoned".to_string())?;
        (st.config.sort_field, st.config.sort_order, st.config.directories_first)
    };
    sort_entries(&mut hits, sf, so, df);
    let entries_json: Vec<Value> = hits.iter().map(entry_to_json).collect();

    Ok(json!({
        "path": dir.to_string_lossy(),
        "query": query,
        "cancelled": cancel.load(Ordering::Relaxed),
        "entries": entries_json,
    }))
}

fn cmd_thumb(params: &Value) -> Result<Value, String> {
    let path = PathBuf::from(req_str(params, "path")?);
    let kind_str = opt_str(params, "kind").unwrap_or_default();
    let size = params.get("size").and_then(|v| v.as_i64()).unwrap_or(192) as i32;
    let kind = match kind_str.as_str() {
        "Image" => FileKind::Image,
        "Pdf" => FileKind::Pdf,
        "Video" => FileKind::Video,
        _ => {
            let fe = FileEntry::from_path(path.clone())
                .map_err(|e| format!("Cannot inspect '{}': {e}", path.display()))?;
            fe.kind
        }
    };
    let thumb = thumbnails::ensure_thumbnail_file(&path, kind, size.clamp(48, 512));
    Ok(json!({
        "path": path.to_string_lossy(),
        "thumb_path": thumb.map(|p| p.to_string_lossy().to_string()),
    }))
}

fn cmd_transfer(is_move: bool, params: &Value, state: &SharedDaemon) -> Result<Value, String> {
    let sources = req_paths(params, "paths")?;
    let dest_dir = PathBuf::from(req_str(params, "dest_dir")?);
    if !dest_dir.is_dir() {
        return Err("Destination folder does not exist".into());
    }
    let mut pairs = Vec::with_capacity(sources.len());
    for src in sources {
        let Some(name) = src.file_name() else {
            continue;
        };
        let desired = dest_dir.join(name);
        if is_move && desired == src {
            continue;
        }
        let is_src_dir = fs::symlink_metadata(&src)
            .map(|m| m.is_dir())
            .unwrap_or(false);
        if is_src_dir && fs_ops::is_same_or_descendant(&src, &dest_dir) {
            return Err("Cannot move or copy a folder inside itself".into());
        }
        let target = unique_destination_for(&desired, is_src_dir);
        pairs.push((src, target));
    }

    let (created, moved) = transfer_batch(is_move, &pairs)?;
    let n = if is_move { moved.len() } else { created.len() };
    let msg = if is_move {
        if let Ok(mut st) = state.lock() {
            st.undo.push(UndoAction::Moved {
                label: format!("Move {n} item(s)"),
                pairs: moved,
            });
        }
        format!("Moved {n} item(s)")
    } else {
        if let Ok(mut st) = state.lock() {
            st.undo.push(UndoAction::Created {
                label: format!("Copy {n} item(s)"),
                paths: created,
            });
        }
        format!("Copied {n} item(s)")
    };

    let (can_undo, can_redo) = undo_flags(state);
    Ok(json!({
        "count": n,
        "message": msg,
        "can_undo": can_undo,
        "can_redo": can_redo,
    }))
}

fn cmd_trash(params: &Value, state: &SharedDaemon) -> Result<Value, String> {
    let paths = req_paths(params, "paths")?;
    let records = trash_batch(&paths)?;
    let n = records.len();
    if let Ok(mut st) = state.lock() {
        st.undo.push(UndoAction::Trashed {
            label: format!("Trash {n} item(s)"),
            items: records,
        });
    }
    let (can_undo, can_redo) = undo_flags(state);
    Ok(json!({
        "count": n,
        "message": format!("Moved {n} item(s) to Trash"),
        "trash_count": count_trash_items(),
        "can_undo": can_undo,
        "can_redo": can_redo,
    }))
}

fn cmd_alis_action(params: &Value) -> Result<Value, String> {
    let action = req_str(params, "action")?;
    let paths = req_paths(params, "paths")?;
    if paths.is_empty() {
        return Err("No path supplied".into());
    }
    let msg = match action.as_str() {
        "wallpaper" => alis_actions::set_as_alis_wallpaper(&paths[0])?,
        "local_music" => alis_actions::play_in_alis_local_music(&paths)?,
        "terminal" => alis_actions::open_terminal_here(&paths[0])?,
        "nexus" => alis_actions::send_to_nexus(&paths[0])?,
        "companion" => alis_actions::send_to_alis_companion(&paths)?,
        other => return Err(format!("Unknown Alis action: {other}")),
    };
    Ok(json!({ "message": msg }))
}

fn cmd_sync_config(state: &SharedDaemon) -> Result<Value, String> {
    let fresh = AppConfig::load_from(&config_path());
    let mut st = state.lock().map_err(|_| "State lock poisoned".to_string())?;
    st.config = fresh;
    let cfg_val = serde_json::to_value(&st.config).unwrap_or_else(|_| json!({}));
    let bm = bookmarks_json(&st.config);
    let rec = json!(st.config.recent_folders);
    Ok(json!({
        "config": cfg_val,
        "bookmarks": bm,
        "recent": rec,
        "trash_count": count_trash_items(),
    }))
}

fn cmd_save_config(params: &Value, state: &SharedDaemon) -> Result<Value, String> {
    let fresh = AppConfig::load_from(&config_path());
    let mut st = state.lock().map_err(|_| "State lock poisoned".to_string())?;
    st.config = fresh;
    if let Some(v) = params.get("overlay_mode").and_then(|v| v.as_bool()) {
        st.config.overlay_mode = v;
    }
    if let Some(v) = params.get("show_hidden").and_then(|v| v.as_bool()) {
        st.config.show_hidden = v;
    }
    if let Some(v) = params.get("rail_open").and_then(|v| v.as_bool()) {
        st.config.rail_open = v;
    }
    if let Some(v) = params.get("inspector_open_default").and_then(|v| v.as_bool()) {
        st.config.inspector_open_default = v;
    }
    if let Some(v) = params.get("directories_first").and_then(|v| v.as_bool()) {
        st.config.directories_first = v;
    }
    if let Some(v) = params.get("thumbnails_enabled").and_then(|v| v.as_bool()) {
        st.config.thumbnails_enabled = v;
    }
    if let Some(v) = params.get("git_badges").and_then(|v| v.as_bool()) {
        st.config.git_badges = v;
    }
    if let Some(v) = params.get("vim_keybindings").and_then(|v| v.as_bool()) {
        st.config.vim_keybindings = v;
    }
    if let Some(v) = params.get("grid_icon_size").and_then(|v| v.as_i64()) {
        st.config.grid_icon_size = (v as i32).clamp(40, 240);
    }
    if let Some(v) = params.get("list_zoom").and_then(|v| v.as_u64()) {
        st.config.list_zoom = (v as u8).min(2);
    }
    if let Some(v) = params.get("rail_width").and_then(|v| v.as_i64()) {
        st.config.rail_width = (v as i32).clamp(156, 460);
    }
    if let Some(v) = params.get("inspector_width").and_then(|v| v.as_i64()) {
        st.config.inspector_width = (v as i32).clamp(200, 560);
    }
    if let Some(v) = params.get("inspector_preview_ratio_milli").and_then(|v| v.as_u64()) {
        st.config.inspector_preview_ratio_milli = (v as u16).clamp(220, 720);
    }
    if let Some(s) = opt_str(params, "view_mode") {
        st.config.view_mode = match s.as_str() {
            "list" => crate::config::ViewMode::List,
            "gallery" => crate::config::ViewMode::Gallery,
            _ => crate::config::ViewMode::Grid,
        };
    }
    if let Some(s) = opt_str(params, "sort_field") {
        st.config.sort_field = match s.as_str() {
            "size" => SortField::Size,
            "modified" => SortField::Modified,
            "kind" => SortField::Kind,
            _ => SortField::Name,
        };
    }
    if let Some(s) = opt_str(params, "sort_order") {
        st.config.sort_order = match s.as_str() {
            "desc" => SortOrder::Desc,
            _ => SortOrder::Asc,
        };
    }
    if let Some(sess) = params.get("session") {
        apply_session_json(sess, &mut st.config);
    }
    st.config.save().map_err(|e| format!("Save config failed: {e}"))?;
    Ok(json!({
        "config": serde_json::to_value(&st.config).unwrap_or_else(|_| json!({})),
        "bookmarks": bookmarks_json(&st.config),
    }))
}

fn apply_session_json(params: &Value, cfg: &mut AppConfig) {
    if let Some(arr) = params.get("tabs").and_then(|v| v.as_array()) {
        cfg.session.tabs = arr
            .iter()
            .filter_map(|v| v.as_str().map(ToOwned::to_owned))
            .filter(|s| !s.trim().is_empty())
            .take(32)
            .collect();
    }
    if let Some(idx) = params.get("active_tab").and_then(|v| v.as_u64()) {
        cfg.session.active_tab = idx as usize;
    }
    if let Some(v) = params.get("split_open").and_then(|v| v.as_bool()) {
        cfg.session.split_open = v;
    }
    if let Some(v) = params.get("split_ratio_milli").and_then(|v| v.as_u64()) {
        cfg.session.split_ratio_milli = (v as u16).clamp(200, 800);
    }
    if let Some(arr) = params.get("secondary_tabs").and_then(|v| v.as_array()) {
        cfg.session.secondary_tabs = arr
            .iter()
            .filter_map(|v| v.as_str().map(ToOwned::to_owned))
            .filter(|s| !s.trim().is_empty())
            .take(32)
            .collect();
    }
    if let Some(idx) = params.get("secondary_active_tab").and_then(|v| v.as_u64()) {
        cfg.session.secondary_active_tab = idx as usize;
    }
    if let Some(v) = params.get("active_is_secondary").and_then(|v| v.as_bool()) {
        cfg.session.active_is_secondary = v;
    }
    if let Some(arr) = params.get("tab_entries").and_then(|v| v.as_array()) {
        cfg.session.tab_entries = arr
            .iter()
            .filter_map(|item| {
                let path = item
                    .get("path")
                    .and_then(|v| v.as_str())
                    .map(str::trim)
                    .filter(|s| !s.is_empty())?
                    .to_string();
                let split_path = item
                    .get("split_path")
                    .and_then(|v| v.as_str())
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .map(ToOwned::to_owned);
                Some(crate::config::SessionTab { path, split_path })
            })
            .take(32)
            .collect();
    }
}

fn cmd_save_session(params: &Value, state: &SharedDaemon) -> Result<Value, String> {
    let mut fresh = AppConfig::load_from(&config_path());
    apply_session_json(params, &mut fresh);
    fresh.save().map_err(|e| format!("Save session failed: {e}"))?;
    let mut st = state.lock().map_err(|_| "State lock poisoned".to_string())?;
    st.config = fresh;
    Ok(json!({
        "session": st.config.session,
    }))
}

fn cmd_read_text_preview(params: &Value) -> Result<Value, String> {
    let p = PathBuf::from(req_str(params, "path")?);
    let meta = fs::metadata(&p).map_err(|e| format!("Cannot read file: {e}"))?;
    if !meta.is_file() {
        return Ok(json!({
            "path": p.to_string_lossy(),
            "binary": true,
            "text": "Special file — text preview unavailable",
        }));
    }
    const MAX_BYTES: usize = 64 * 1024;
    let mut file = fs::File::open(&p).map_err(|e| format!("Cannot open file: {e}"))?;
    let mut buf = vec![0u8; MAX_BYTES];
    let n = file.read(&mut buf).unwrap_or(0);
    buf.truncate(n);
    if buf.contains(&0) {
        return Ok(json!({
            "path": p.to_string_lossy(),
            "binary": true,
            "text": "Binary file — text preview unavailable",
        }));
    }
    let mut text = String::from_utf8_lossy(&buf).into_owned();
    if n == MAX_BYTES {
        text.push_str("\n\n— Preview truncated at 64 KB —");
    }
    Ok(json!({
        "path": p.to_string_lossy(),
        "binary": false,
        "text": text,
    }))
}

fn entry_to_json(e: &FileEntry) -> Value {
    let mtime_ms = e
        .modified
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    let kind_str = match e.kind {
        FileKind::Directory => "Directory",
        FileKind::Image => "Image",
        FileKind::Audio => "Audio",
        FileKind::Video => "Video",
        FileKind::Pdf => "Pdf",
        FileKind::Archive => "Archive",
        FileKind::Markdown => "Markdown",
        FileKind::Code => "Code",
        FileKind::Document => "Document",
        FileKind::Text => "Text",
        FileKind::Executable => "Executable",
        FileKind::Other => "Other",
    };
    json!({
        "name": e.name,
        "path": e.path.to_string_lossy(),
        "is_dir": e.is_dir,
        "is_symlink": e.is_symlink,
        "is_broken_symlink": e.is_broken_symlink,
        "is_hidden": e.is_hidden,
        "size": e.size,
        "size_label": if e.is_dir { "—".into() } else { format_size(e.size) },
        "modified_ms": mtime_ms,
        "modified_label": format_time(e.modified),
        "permissions": format_permissions(e.mode),
        "kind": kind_str,
        "kind_label": e.kind_label(),
        "supports_wallpaper": e.supports_wallpaper(),
        "supports_local_music": e.supports_local_music(),
        "supports_nexus": e.supports_nexus(),
        "is_extractable": e.is_extractable_archive(),
        "trash_original": e.trash_original_path,
    })
}

fn build_places_json(home: &Path, trash: &Path) -> Vec<Value> {
    let specs = [
        ("Home", "home", home.to_path_buf()),
        ("Desktop", "desktop_windows", home.join("Desktop")),
        ("Documents", "description", home.join("Documents")),
        ("Downloads", "download", home.join("Downloads")),
        ("Pictures", "image", home.join("Pictures")),
        ("Music", "music_note", home.join("Music")),
        ("Videos", "movie", home.join("Videos")),
        ("Trash", "delete", trash.to_path_buf()),
    ];
    let mut out = Vec::new();
    for (label, icon, path) in specs {
        if path != home && !is_trash_dir(&path) && !path.is_dir() {
            continue;
        }
        out.push(json!({
            "label": label,
            "icon": icon,
            "path": path.to_string_lossy(),
            "is_trash": is_trash_dir(&path),
        }));
    }
    out
}

fn bookmarks_json(cfg: &AppConfig) -> Value {
    let arr: Vec<Value> = cfg
        .bookmarks
        .iter()
        .map(|b| {
            json!({
                "name": b.name,
                "path": b.path,
            })
        })
        .collect();
    Value::Array(arr)
}

fn list_drives_json() -> Vec<Value> {
    let mut out = Vec::new();
    let (rtot, rused) = mounts::filesystem_space(Path::new("/"));
    out.push(json!({
        "name": "Computer",
        "mount_point": "/",
        "icon": "computer",
        "can_eject": false,
        "is_removable": false,
        "is_mounted": true,
        "total_bytes": rtot,
        "used_bytes": rused,
        "free_label": format_size(rtot.saturating_sub(rused)),
        "usage_fraction": if rtot > 0 { (rused as f64 / rtot as f64).clamp(0.0, 1.0) } else { 0.0 },
        "block_device": null,
    }));

    let mut seen_paths: HashSet<PathBuf> = HashSet::new();
    let mut seen_devs: HashSet<String> = HashSet::new();
    seen_paths.insert(PathBuf::from("/"));

    for d in mounts::list_drives() {
        if let Some(ref mp) = d.mount_point
            && !seen_paths.insert(mp.clone())
        {
            continue;
        }
        if let Some(ref dev) = d.block_device {
            let canon = mounts::canonical_dev(dev);
            if !seen_devs.insert(canon) {
                continue;
            }
        }
        out.push(json!({
            "name": d.name,
            "mount_point": d.mount_point.as_ref().map(|p| p.to_string_lossy().to_string()),
            "icon": if d.is_removable { "usb" } else { "hard_drive" },
            "can_eject": d.can_eject,
            "is_removable": d.is_removable,
            "is_mounted": d.is_mounted,
            "total_bytes": d.total_bytes,
            "used_bytes": d.used_bytes,
            "free_label": format_size(d.total_bytes.saturating_sub(d.used_bytes)),
            "usage_fraction": d.usage_fraction(),
            "block_device": d.block_device,
        }));
    }
    out
}

fn count_trash_items_in(dir: &Path) -> usize {
    static CACHE: OnceLock<Mutex<Option<(PathBuf, SystemTime, usize)>>> = OnceLock::new();
    let mtime = fs::metadata(dir).ok().and_then(|m| m.modified().ok());
    // Apply the racy-git rule: only trust a cached directory count when the
    // directory's mtime is safely in the past (> 1s) so same-tick mutations
    // can never return a stale count.
    let mtime_settled = mtime
        .and_then(|t| SystemTime::now().duration_since(t).ok())
        .is_some_and(|age| age.as_secs() >= 1);
    let cache = CACHE.get_or_init(|| Mutex::new(None));
    if mtime_settled
        && let Some(cur_mtime) = mtime
        && let Ok(guard) = cache.lock()
        && let Some((ref cached_dir, cached_mtime, count)) = *guard
        && cached_dir == dir
        && cached_mtime == cur_mtime
    {
        return count;
    }
    let count = fs::read_dir(dir)
        .map(|it| it.filter_map(Result::ok).count())
        .unwrap_or(0);
    // Only populate the cache once mtime has settled (> 1s old) so a second
    // write within the same coarse filesystem timestamp tick can never poison
    // the cached count.
    if mtime_settled
        && let Some(cur_mtime) = mtime
        && let Ok(mut guard) = cache.lock()
    {
        *guard = Some((dir.to_path_buf(), cur_mtime, count));
    }
    count
}

fn count_trash_items() -> usize {
    count_trash_items_in(&trash_files_dir())
}

fn undo_flags(state: &SharedDaemon) -> (bool, bool) {
    state
        .lock()
        .map(|s| (s.undo.can_undo(), s.undo.can_redo()))
        .unwrap_or((false, false))
}

fn expand_path(raw: &str) -> PathBuf {
    if raw == "~" {
        return home_dir();
    }
    if let Some(rest) = raw.strip_prefix("~/") {
        return home_dir().join(rest);
    }
    PathBuf::from(raw)
}

fn req_str(params: &Value, key: &str) -> Result<String, String> {
    params
        .get(key)
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .map(ToOwned::to_owned)
        .ok_or_else(|| format!("Missing string parameter '{key}'"))
}

fn opt_str(params: &Value, key: &str) -> Option<String> {
    params
        .get(key)
        .and_then(|v| v.as_str())
        .map(ToOwned::to_owned)
}

fn req_paths(params: &Value, key: &str) -> Result<Vec<PathBuf>, String> {
    let arr = params
        .get(key)
        .and_then(|v| v.as_array())
        .ok_or_else(|| format!("Missing array parameter '{key}'"))?;
    let paths: Vec<PathBuf> = arr
        .iter()
        .filter_map(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .collect();
    if paths.is_empty() {
        return Err(format!("Parameter '{key}' is empty"));
    }
    Ok(paths)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn overlay_daemon_rpc_handles_list_fileops_undo_redo_search_and_preview() {
        let base =
            std::env::temp_dir().join(format!("alis-files-daemon-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        fs::create_dir_all(&base).unwrap();

        let state = Arc::new(Mutex::new(DaemonState {
            config: AppConfig::default(),
            undo: UndoManager::default(),
            active_search_cancel: None,
            active_props_dir_cancel: None,
        }));

        // init
        let init = handle_command("init", &json!({}), &state).unwrap();
        assert!(init["home"].as_str().is_some());
        assert!(init["places"].as_array().is_some());

        // mkdir + mkfile + Yazi create (trailing '/' -> folder, else file) + rename
        handle_command("mkdir", &json!({ "dir": base, "name": "alpha" }), &state).unwrap();
        handle_command("mkfile", &json!({ "dir": base, "name": "notes.md" }), &state).unwrap();
        let yazi_dir =
            handle_command("create", &json!({ "dir": base, "name": "yazi_dir/" }), &state).unwrap();
        assert_eq!(yazi_dir["is_dir"], true);
        assert!(base.join("yazi_dir").is_dir());
        let yazi_file =
            handle_command("create", &json!({ "dir": base, "name": "yazi.txt" }), &state).unwrap();
        assert_eq!(yazi_file["is_dir"], false);
        assert!(base.join("yazi.txt").is_file());
        fs::write(base.join("notes.md"), "Alis Overlay Preview\nLine 2\n").unwrap();

        let list = handle_command("list", &json!({ "path": base }), &state).unwrap();
        let entries = list["entries"].as_array().unwrap();
        assert_eq!(entries.len(), 4);
        assert_eq!(entries[0]["name"], "alpha");
        assert_eq!(entries[0]["is_dir"], true);

        // read_text_preview + binary check
        let prev = handle_command(
            "read_text_preview",
            &json!({ "path": base.join("notes.md") }),
            &state,
        )
        .unwrap();
        assert_eq!(prev["binary"], false);
        assert!(prev["text"].as_str().unwrap().contains("Alis Overlay Preview"));

        let bin_path = base.join("bin.dat");
        fs::write(&bin_path, b"\x00\x01\x02ELF").unwrap();
        let prev_bin =
            handle_command("read_text_preview", &json!({ "path": bin_path }), &state).unwrap();
        assert_eq!(prev_bin["binary"], true);

        // rename + undo + redo
        handle_command(
            "rename",
            &json!({ "path": base.join("notes.md"), "new_name": "renamed.md" }),
            &state,
        )
        .unwrap();
        assert!(base.join("renamed.md").is_file());
        handle_command("undo", &json!({}), &state).unwrap();
        assert!(base.join("notes.md").is_file());
        handle_command("redo", &json!({}), &state).unwrap();
        assert!(base.join("renamed.md").is_file());

        // recursive search
        let srch = handle_command(
            "search",
            &json!({ "path": base, "query": "renamed" }),
            &state,
        )
        .unwrap();
        assert_eq!(srch["entries"].as_array().unwrap().len(), 1);

        // non-existent path recovers cleanly to nearest ancestor
        let missing = handle_command(
            "list",
            &json!({ "path": base.join("does/not/exist") }),
            &state,
        )
        .unwrap();
        assert_eq!(missing["path"], base.to_string_lossy().as_ref());

        // properties + set_permissions + checksum
        let props_res = handle_command(
            "properties",
            &json!({ "path": base.join("renamed.md"), "git_status": "Modified" }),
            &state,
        )
        .unwrap();
        assert_eq!(props_res["properties"]["name"], "renamed.md");
        assert_eq!(props_res["properties"]["git_status"], "Modified");

        let perm_res = handle_command(
            "set_permissions",
            &json!({ "path": base.join("renamed.md"), "mode": 0o755 }),
            &state,
        )
        .unwrap();
        assert_eq!(perm_res["properties"]["mode"].as_u64(), Some(0o755));

        let sum_res = handle_command(
            "checksum",
            &json!({ "path": base.join("renamed.md"), "algo": "sha256" }),
            &state,
        )
        .unwrap();
        assert_eq!(sum_res["digest"].as_str().unwrap().len(), 64);

        // unknown command returns clear error
        assert!(handle_command("not_a_cmd", &json!({}), &state).is_err());

        // mtime-cached trash counter tracks additions and removals accurately
        let trash_dir = base.join("trash_sim");
        fs::create_dir_all(&trash_dir).unwrap();
        assert_eq!(count_trash_items_in(&trash_dir), 0);
        fs::write(trash_dir.join("a.txt"), "1").unwrap();
        assert_eq!(count_trash_items_in(&trash_dir), 1);
        assert_eq!(count_trash_items_in(&trash_dir), 1);
        fs::remove_file(trash_dir.join("a.txt")).unwrap();
        assert_eq!(count_trash_items_in(&trash_dir), 0);

        let _ = fs::remove_dir_all(&base);
    }
}
