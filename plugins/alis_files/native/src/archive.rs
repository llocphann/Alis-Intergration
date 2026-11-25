use std::fs;
use std::path::{Component, Path, PathBuf};
use std::process::{Command, Stdio};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ArchiveFormat {
    Zip,
    TarGz,
    TarZst,
    TarXz,
    SevenZ,
}

impl ArchiveFormat {
    pub fn extension(self) -> &'static str {
        match self {
            Self::Zip => "zip",
            Self::TarGz => "tar.gz",
            Self::TarZst => "tar.zst",
            Self::TarXz => "tar.xz",
            Self::SevenZ => "7z",
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Zip => "ZIP (.zip)",
            Self::TarGz => "Tar Gzip (.tar.gz)",
            Self::TarZst => "Tar Zstandard (.tar.zst)",
            Self::TarXz => "Tar XZ (.tar.xz)",
            Self::SevenZ => "7-Zip (.7z)",
        }
    }

    pub const ALL: [ArchiveFormat; 5] = [
        Self::Zip,
        Self::TarGz,
        Self::TarZst,
        Self::TarXz,
        Self::SevenZ,
    ];
}

pub fn is_supported_archive(path: &Path) -> bool {
    let lower = path
        .file_name()
        .map(|s| s.to_string_lossy().to_lowercase())
        .unwrap_or_default();
    [
        ".zip", ".tar", ".tar.gz", ".tgz", ".tar.xz", ".txz", ".tar.zst", ".tzst", ".tar.bz2",
        ".tbz2", ".7z", ".rar",
    ]
    .iter()
    .any(|ext| lower.ends_with(ext))
}

pub fn archive_stem(path: &Path) -> String {
    let name = path
        .file_name()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| "extracted".into());
    let lower = name.to_lowercase();
    for suffix in [".tar.gz", ".tar.xz", ".tar.zst", ".tar.bz2"] {
        if lower.ends_with(suffix) && name.len() > suffix.len() {
            return name[..name.len() - suffix.len()].to_string();
        }
    }
    let (stem, _) = crate::fs_ops::split_name_ext(&name);
    if stem.is_empty() {
        "extracted".into()
    } else {
        stem
    }
}

fn common_ancestor_dir(paths: &[PathBuf]) -> Option<PathBuf> {
    let parents: Vec<PathBuf> = paths
        .iter()
        .filter_map(|p| p.parent().map(Path::to_path_buf))
        .collect();
    let first = parents.first()?.clone();
    let mut acc = Vec::new();
    for comp in first.components() {
        acc.push(comp);
        let candidate: PathBuf = acc.iter().collect();
        if !parents.iter().all(|p| p.starts_with(&candidate)) {
            acc.pop();
            break;
        }
    }
    if acc.is_empty() {
        Some(PathBuf::from("/"))
    } else {
        Some(acc.iter().collect())
    }
}

pub fn compress(
    sources: &[PathBuf],
    dest_dir: &Path,
    archive_base_name: &str,
    format: ArchiveFormat,
) -> Result<PathBuf, String> {
    if sources.is_empty() {
        return Err("No items selected to compress".into());
    }
    let clean = crate::fs_ops::validate_single_name(archive_base_name)?;
    let ext = format.extension();
    let filename = if clean.ends_with(&format!(".{ext}")) {
        clean.to_string()
    } else {
        format!("{clean}.{ext}")
    };
    let output_path = crate::fs_ops::unique_destination(&dest_dir.join(filename));
    let work_dir = common_ancestor_dir(sources).unwrap_or_else(|| dest_dir.to_path_buf());
    let rel_names: Vec<String> = sources
        .iter()
        .filter_map(|p| {
            p.strip_prefix(&work_dir)
                .ok()
                .map(|r| r.to_string_lossy().to_string())
                .filter(|s| !s.is_empty())
                .or_else(|| p.file_name().map(|n| n.to_string_lossy().to_string()))
        })
        .collect();
    if rel_names.is_empty() {
        return Err("No valid source names to compress".into());
    }

    let status = match format {
        ArchiveFormat::Zip => {
            if command_exists("zip") {
                Command::new("zip")
                    .stdin(Stdio::null())
                    .current_dir(&work_dir)
                    .arg("-rq")
                    .arg(&output_path)
                    .arg("--")
                    .args(&rel_names)
                    .output()
            } else if command_exists("7z") {
                Command::new("7z")
                    .stdin(Stdio::null())
                    .current_dir(&work_dir)
                    .args(["a", "-tzip", "-bso0", "-bsp0", "--"])
                    .arg(&output_path)
                    .args(&rel_names)
                    .output()
            } else {
                return Err("Neither 'zip' nor '7z' is installed".into());
            }
        }
        ArchiveFormat::TarGz => Command::new("tar")
            .stdin(Stdio::null())
            .current_dir(&work_dir)
            .args(["--force-local", "-czf"])
            .arg(&output_path)
            .arg("--")
            .args(&rel_names)
            .output(),
        ArchiveFormat::TarZst => Command::new("tar")
            .stdin(Stdio::null())
            .current_dir(&work_dir)
            .args(["--force-local", "--zstd", "-cf"])
            .arg(&output_path)
            .arg("--")
            .args(&rel_names)
            .output(),
        ArchiveFormat::TarXz => Command::new("tar")
            .stdin(Stdio::null())
            .current_dir(&work_dir)
            .args(["--force-local", "-cJf"])
            .arg(&output_path)
            .arg("--")
            .args(&rel_names)
            .output(),
        ArchiveFormat::SevenZ => {
            if !command_exists("7z") {
                return Err("'7z' is not installed".into());
            }
            Command::new("7z")
                .stdin(Stdio::null())
                .current_dir(&work_dir)
                .args(["a", "-bso0", "-bsp0", "--"])
                .arg(&output_path)
                .args(&rel_names)
                .output()
        }
    }
    .map_err(|e| format!("Archive tool failed to start: {e}"))?;

    if !status.status.success() {
        let stderr = String::from_utf8_lossy(&status.stderr).trim().to_string();
        return Err(if stderr.is_empty() {
            format!("Compression failed with exit status {}", status.status)
        } else {
            stderr
        });
    }
    Ok(output_path)
}

fn check_member_path_safe(member: &str) -> Result<(), String> {
    let trimmed = member.trim();
    if trimmed.is_empty() {
        return Ok(());
    }
    if trimmed.starts_with('/') {
        return Err(format!("Blocked unsafe absolute archive path: {trimmed}"));
    }
    for comp in Path::new(trimmed).components() {
        if matches!(comp, Component::ParentDir | Component::RootDir) {
            return Err(format!("Blocked path traversal entry in archive: {trimmed}"));
        }
    }
    Ok(())
}

fn validate_archive_entries(archive_path: &Path, lower: &str) -> Result<(), String> {
    let listing_out = if lower.ends_with(".7z") || lower.ends_with(".rar") {
        if command_exists("bsdtar") && !lower.ends_with(".7z") {
            Command::new("bsdtar")
                .stdin(Stdio::null())
                .args(["-tf"])
                .arg(archive_path)
                .output()
                .ok()
        } else if command_exists("7z") {
            let out = Command::new("7z")
                .stdin(Stdio::null())
                .args(["l", "-slt", "-p", "--"])
                .arg(archive_path)
                .output()
                .ok();
            if let Some(ref o) = out
                && o.status.success()
            {
                let stdout = String::from_utf8_lossy(&o.stdout);
                for line in stdout.lines() {
                    if let Some(p) = line.strip_prefix("Path = ") {
                        check_member_path_safe(p)?;
                    }
                }
                return Ok(());
            }
            out
        } else {
            None
        }
    } else if lower.ends_with(".zip") && command_exists("bsdtar") {
        Command::new("bsdtar")
            .stdin(Stdio::null())
            .args(["-tf"])
            .arg(archive_path)
            .output()
            .ok()
    } else if lower.ends_with(".tar.zst") || lower.ends_with(".tzst") {
        Command::new("tar")
            .stdin(Stdio::null())
            .args(["--force-local", "--zstd", "-tf"])
            .arg(archive_path)
            .output()
            .ok()
    } else {
        Command::new("tar")
            .stdin(Stdio::null())
            .args(["--force-local", "-tf"])
            .arg(archive_path)
            .output()
            .ok()
    };

    if let Some(o) = listing_out
        && o.status.success()
    {
        for line in String::from_utf8_lossy(&o.stdout).lines() {
            check_member_path_safe(line)?;
        }
    }
    Ok(())
}

/// Extract archive safely into a dedicated folder (or `into_here = true` directly into parent without overwriting).
pub fn extract(archive_path: &Path, into_subfolder: bool) -> Result<PathBuf, String> {
    if !is_supported_archive(archive_path) {
        return Err("Unsupported archive format".into());
    }
    let lower = archive_path
        .file_name()
        .map(|s| s.to_string_lossy().to_lowercase())
        .unwrap_or_default();

    validate_archive_entries(archive_path, &lower)?;

    let parent = archive_path
        .parent()
        .ok_or_else(|| "Invalid archive path".to_string())?;
    let target_dir = if into_subfolder {
        let desired = parent.join(archive_stem(archive_path));
        let unique = crate::fs_ops::unique_destination_for(&desired, true);
        fs::create_dir_all(&unique).map_err(|e| format!("Could not create extract folder: {e}"))?;
        unique
    } else {
        parent.to_path_buf()
    };

    let cleanup_on_err = |created_dir: &Path| {
        if into_subfolder {
            let _ = fs::remove_dir_all(created_dir);
        }
    };

    let output = if lower.ends_with(".zip") {
        if command_exists("bsdtar") {
            let mut cmd = Command::new("bsdtar");
            cmd.stdin(Stdio::null());
            if !into_subfolder {
                cmd.arg("-k");
            }
            cmd.arg("-xf")
                .arg(archive_path)
                .arg("-C")
                .arg(&target_dir)
                .output()
        } else if command_exists("unzip") {
            let flag = if into_subfolder { "-oq" } else { "-nq" };
            Command::new("unzip")
                .stdin(Stdio::null())
                .args([flag, "--"])
                .arg(archive_path)
                .arg("-d")
                .arg(&target_dir)
                .output()
        } else if command_exists("7z") {
            let ow = if into_subfolder { "-aou" } else { "-aos" };
            Command::new("7z")
                .stdin(Stdio::null())
                .args(["x", "-p", ow, "-bso0", "-bsp0"])
                .arg(format!("-o{}", target_dir.display()))
                .arg("--")
                .arg(archive_path)
                .output()
        } else {
            cleanup_on_err(&target_dir);
            return Err("No zip extraction tool (bsdtar/unzip/7z) available".into());
        }
    } else if lower.ends_with(".7z") || lower.ends_with(".rar") {
        if command_exists("7z") && (lower.ends_with(".7z") || !command_exists("bsdtar")) {
            let ow = if into_subfolder { "-aou" } else { "-aos" };
            Command::new("7z")
                .stdin(Stdio::null())
                .args(["x", "-p", ow, "-bso0", "-bsp0"])
                .arg(format!("-o{}", target_dir.display()))
                .arg("--")
                .arg(archive_path)
                .output()
        } else if command_exists("bsdtar") {
            let mut cmd = Command::new("bsdtar");
            cmd.stdin(Stdio::null());
            if !into_subfolder {
                cmd.arg("-k");
            }
            cmd.arg("-xf")
                .arg(archive_path)
                .arg("-C")
                .arg(&target_dir)
                .output()
        } else {
            cleanup_on_err(&target_dir);
            return Err("'7z' or 'bsdtar' is required to extract this archive".into());
        }
    } else if lower.ends_with(".tar.zst") || lower.ends_with(".tzst") {
        let mut cmd = Command::new("tar");
        cmd.stdin(Stdio::null()).args(["--force-local", "--zstd"]);
        if !into_subfolder {
            cmd.arg("--keep-old-files");
        }
        cmd.arg("-xf")
            .arg(archive_path)
            .arg("-C")
            .arg(&target_dir)
            .output()
    } else {
        let mut cmd = Command::new("tar");
        cmd.stdin(Stdio::null()).arg("--force-local");
        if !into_subfolder {
            cmd.arg("--keep-old-files");
        }
        cmd.arg("-xf")
            .arg(archive_path)
            .arg("-C")
            .arg(&target_dir)
            .output()
    }
    .map_err(|e| {
        cleanup_on_err(&target_dir);
        format!("Extraction tool failed to start: {e}")
    })?;

    if !output.status.success() {
        cleanup_on_err(&target_dir);
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        return Err(if stderr.is_empty() {
            format!("Extraction failed with exit status {}", output.status)
        } else {
            stderr
        });
    }
    Ok(target_dir)
}

fn command_exists(bin: &str) -> bool {
    std::env::var_os("PATH")
        .map(|paths| {
            std::env::split_paths(&paths).any(|dir| {
                let p = dir.join(bin);
                p.is_file()
            })
        })
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compress_and_extract_tar_gz_and_zip() {
        let dir = std::env::temp_dir().join(format!("alis-files-arch-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let src = dir.join("hello.txt");
        fs::write(&src, "Alis Files archive test\n").unwrap();

        let tgz = compress(std::slice::from_ref(&src), &dir, "bundle", ArchiveFormat::TarGz).unwrap();
        assert!(tgz.is_file());
        assert!(is_supported_archive(&tgz));
        let out_dir = extract(&tgz, true).unwrap();
        assert_eq!(
            fs::read_to_string(out_dir.join("hello.txt")).unwrap(),
            "Alis Files archive test\n"
        );

        let zip = compress(&[src], &dir, "bundle_zip", ArchiveFormat::Zip).unwrap();
        assert!(zip.is_file());
        let out_zip = extract(&zip, true).unwrap();
        assert_eq!(
            fs::read_to_string(out_zip.join("hello.txt")).unwrap(),
            "Alis Files archive test\n"
        );

        // Edge case: leading-dash filename + colon in archive name (ISO timestamp)
        let dash_file = dir.join("-notes 2026.txt");
        fs::write(&dash_file, "dash ok\n").unwrap();
        let colon_tgz = compress(
            std::slice::from_ref(&dash_file),
            &dir,
            "backup-10:30",
            ArchiveFormat::TarGz,
        )
        .unwrap();
        let colon_out = extract(&colon_tgz, true).unwrap();
        assert_eq!(
            fs::read_to_string(colon_out.join("-notes 2026.txt")).unwrap(),
            "dash ok\n"
        );

        // Corrupt archive should clean up temp subfolder
        let bad = dir.join("corrupt.tar.gz");
        fs::write(&bad, b"not a valid archive").unwrap();
        assert!(extract(&bad, true).is_err());
        assert!(!dir.join("corrupt").exists());

        // Path traversal guard blocks Zip-Slip and absolute paths
        assert!(check_member_path_safe("normal/file.txt").is_ok());
        assert!(check_member_path_safe("../etc/passwd").is_err());
        assert!(check_member_path_safe("/etc/shadow").is_err());

        // Multi-directory compress uses common ancestor cleanly
        fs::create_dir_all(dir.join("a")).unwrap();
        fs::create_dir_all(dir.join("b")).unwrap();
        let f_a = dir.join("a/one.txt");
        let f_b = dir.join("b/two.txt");
        fs::write(&f_a, "1").unwrap();
        fs::write(&f_b, "2").unwrap();
        let multi = compress(&[f_a, f_b], &dir, "multi", ArchiveFormat::TarGz).unwrap();
        let multi_out = extract(&multi, true).unwrap();
        assert!(multi_out.join("a/one.txt").is_file());
        assert!(multi_out.join("b/two.txt").is_file());

        let _ = fs::remove_dir_all(&dir);
    }
}
