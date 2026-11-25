use std::path::{Path, PathBuf};
use std::process::Command;

fn resolve_alis_bin() -> PathBuf {
    if let Some(paths) = std::env::var_os("PATH") {
        for dir in std::env::split_paths(&paths) {
            let cand = dir.join("alis");
            if cand.is_file() {
                return cand;
            }
        }
    }
    let home = crate::config::home_dir();
    for cand in [
        home.join(".local/bin/alis"),
        PathBuf::from("/usr/local/bin/alis"),
        PathBuf::from("/usr/bin/alis"),
    ] {
        if cand.is_file() {
            return cand;
        }
    }
    PathBuf::from("alis")
}

/// Quickshell's `ipc call` CLI parser interprets raw arguments starting with `[` as an
/// argument list rather than a string. Prefixing a leading space matches `alis local-music`
/// and ensures JSON arrays arrive intact as a single `string` argument (trimmed by receiver).
pub(crate) fn encode_ipc_json_arg(paths: &[String]) -> Result<String, String> {
    let payload = serde_json::to_string(paths)
        .map_err(|e| format!("Failed encoding paths: {e}"))?;
    Ok(format!(" {payload}"))
}

fn check_ipc_output(out: &std::process::Output, fallback_err: &str) -> Result<(), String> {
    let stdout = String::from_utf8_lossy(&out.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&out.stderr).trim().to_string();
    let ipc_failed = !out.status.success()
        || stdout.starts_with("Too many arguments")
        || stdout.starts_with("Not enough arguments")
        || stdout.starts_with("Target ")
        || stdout.starts_with("No such ")
        || stdout.starts_with("error:");
    if ipc_failed {
        let msg = if !stderr.is_empty() {
            stderr
        } else if !stdout.is_empty() {
            stdout
        } else {
            fallback_err.to_string()
        };
        Err(msg)
    } else {
        Ok(())
    }
}

/// 1. Set as Alis Wallpaper — uses safe Alis IPC `wallpaperSelector apply <path>`
///    which routes through `Wallpapers.select(path)` (no direct race with `switchwall.sh`).
pub fn set_as_alis_wallpaper(path: &Path) -> Result<String, String> {
    let abs = path.canonicalize().unwrap_or_else(|_| path.to_path_buf());
    let alis = resolve_alis_bin();
    let out = Command::new(&alis)
        .args(["ipc", "wallpaperSelector", "apply"])
        .arg(&abs)
        .output()
        .map_err(|e| format!("Failed invoking Alis wallpaper IPC: {e}"))?;
    check_ipc_output(&out, "Could not apply wallpaper via Alis shell IPC")?;
    Ok(format!(
        "Applied wallpaper: {}",
        abs.file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_default()
    ))
}

/// 2. Play in Alis Local Music — delegates to `alis local-music -- <files...>`.
pub fn play_in_alis_local_music(paths: &[PathBuf]) -> Result<String, String> {
    if paths.is_empty() {
        return Err("No audio files selected".into());
    }
    let alis = resolve_alis_bin();
    let abs_paths: Vec<PathBuf> = paths
        .iter()
        .map(|p| p.canonicalize().unwrap_or_else(|_| p.clone()))
        .collect();
    let out = Command::new(&alis)
        .args(["local-music", "--"])
        .args(&abs_paths)
        .output()
        .map_err(|e| format!("Failed invoking Alis Local Music: {e}"))?;
    check_ipc_output(&out, "Could not play audio in Alis Local Music")?;
    Ok(format!("Playing {} track(s) in Alis Local Music", abs_paths.len()))
}

/// 3. Open Terminal Here — opens a fresh window of Alis's configured default terminal in `dir`.
pub fn open_terminal_here(dir: &Path) -> Result<String, String> {
    let target = if dir.is_dir() {
        dir.to_path_buf()
    } else {
        dir.parent()
            .map(Path::to_path_buf)
            .unwrap_or_else(crate::config::home_dir)
    };
    let alis = resolve_alis_bin();
    Command::new(&alis)
        .args(["terminal", "--cwd"])
        .arg(&target)
        .current_dir(&target)
        .spawn()
        .map_err(|e| format!("Failed launching Alis terminal: {e}"))?;
    Ok(format!("Opened terminal in {}", target.display()))
}

/// 4a. Open / Send to Nexus — calls Alis IPC `nexus openPath <abs_path>`.
pub fn send_to_nexus(path: &Path) -> Result<String, String> {
    let abs = path.canonicalize().unwrap_or_else(|_| path.to_path_buf());
    let alis = resolve_alis_bin();
    let out = Command::new(&alis)
        .args(["ipc", "nexus", "openPath"])
        .arg(&abs)
        .output()
        .map_err(|e| format!("Failed invoking Nexus IPC: {e}"))?;
    check_ipc_output(&out, "Could not send file to Nexus (is Nexus enabled?)")?;
    Ok(format!(
        "Sent to Nexus: {}",
        abs.file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_default()
    ))
}

/// 4b. Send to Alis Companion — calls Alis IPC `alisCompanion sendFiles " [<json_array>]"`.
pub fn send_to_alis_companion(paths: &[PathBuf]) -> Result<String, String> {
    if paths.is_empty() {
        return Err("No files selected".into());
    }
    let abs_list: Vec<String> = paths
        .iter()
        .map(|p| {
            p.canonicalize()
                .unwrap_or_else(|_| p.clone())
                .to_string_lossy()
                .to_string()
        })
        .collect();
    let payload = encode_ipc_json_arg(&abs_list)?;
    let alis = resolve_alis_bin();
    let out = Command::new(&alis)
        .args(["ipc", "alisCompanion", "sendFiles", &payload])
        .output()
        .map_err(|e| format!("Failed invoking Alis Companion IPC: {e}"))?;
    check_ipc_output(&out, "Could not send files to Alis Companion")?;
    Ok(format!("Sent {} file(s) to Alis Companion", abs_list.len()))
}

/// Open a file with the system's default application via `gio open` / `xdg-open`.
pub fn open_with_default_app(path: &Path) -> Result<(), String> {
    if Command::new("gio").arg("open").arg(path).spawn().is_ok() {
        return Ok(());
    }
    Command::new("xdg-open")
        .arg(path)
        .spawn()
        .map_err(|e| format!("Could not open file: {e}"))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ipc_json_arg_prefixes_space_for_quickshell() {
        let encoded = encode_ipc_json_arg(&["/tmp/a #1.md".into(), "/tmp/b.pdf".into()]).unwrap();
        assert!(encoded.starts_with(" ["), "got: {encoded:?}");
        let parsed: Vec<String> = serde_json::from_str(encoded.trim()).unwrap();
        assert_eq!(parsed, vec!["/tmp/a #1.md", "/tmp/b.pdf"]);
    }
}
