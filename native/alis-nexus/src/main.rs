#![recursion_limit = "512"]

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::env;
use std::fs;
use std::io::{Read, Write};
use std::path::{Component, Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

// Compact FIPS 180-4 SHA-256 implementation (zero external crate overhead)
fn sha256_hex(data: &[u8]) -> String {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ];
    let bit_len = (data.len() as u64) * 8;
    let mut msg = data.to_vec();
    msg.push(0x80);
    while (msg.len() % 64) != 56 {
        msg.push(0x00);
    }
    msg.extend_from_slice(&bit_len.to_be_bytes());
    for chunk in msg.chunks_exact(64) {
        let mut w = [0u32; 64];
        for i in 0..16 {
            w[i] = u32::from_be_bytes([chunk[i * 4], chunk[i * 4 + 1], chunk[i * 4 + 2], chunk[i * 4 + 3]]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16].wrapping_add(s0).wrapping_add(w[i - 7]).wrapping_add(s1);
        }
        let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut hh] = h;
        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let temp1 = hh.wrapping_add(s1).wrapping_add(ch).wrapping_add(K[i]).wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = s0.wrapping_add(maj);
            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(temp1);
            d = c;
            c = b;
            b = a;
            a = temp1.wrapping_add(temp2);
        }
        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
        h[5] = h[5].wrapping_add(f);
        h[6] = h[6].wrapping_add(g);
        h[7] = h[7].wrapping_add(hh);
    }
    let mut out = String::with_capacity(64);
    for word in h {
        out.push_str(&format!("{:08x}", word));
    }
    out
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum FileCategory {
    Markdown,
    Code,
    Image,
    External,
}

pub fn classify_extension(ext: &str) -> (FileCategory, &'static str) {
    let lower = ext.trim_start_matches('.').to_ascii_lowercase();
    match lower.as_str() {
        "md" | "markdown" | "mdx" => (FileCategory::Markdown, "markdown"),
        "txt" | "text" => (FileCategory::Code, "plaintext"),
        "json" | "jsonc" | "jsonl" => (FileCategory::Code, "json"),
        "yaml" | "yml" => (FileCategory::Code, "yaml"),
        "toml" => (FileCategory::Code, "toml"),
        "py" | "pyi" => (FileCategory::Code, "python"),
        "rs" => (FileCategory::Code, "rust"),
        "qml" => (FileCategory::Code, "qml"),
        "js" | "mjs" | "cjs" | "jsx" => (FileCategory::Code, "javascript"),
        "ts" | "tsx" => (FileCategory::Code, "typescript"),
        "sh" | "bash" | "zsh" | "fish" => (FileCategory::Code, "shell"),
        "css" | "scss" | "less" => (FileCategory::Code, "css"),
        "html" | "htm" => (FileCategory::Code, "html"),
        "xml" => (FileCategory::Code, "xml"),
        "c" | "h" => (FileCategory::Code, "c"),
        "cpp" | "cc" | "cxx" | "hpp" => (FileCategory::Code, "cpp"),
        "go" => (FileCategory::Code, "go"),
        "lua" => (FileCategory::Code, "lua"),
        "ini" | "conf" | "cfg" | "desktop" | "service" => (FileCategory::Code, "ini"),
        "csv" | "tsv" => (FileCategory::Code, "csv"),
        "log" => (FileCategory::Code, "log"),
        "kdl" => (FileCategory::Code, "kdl"),
        "nix" => (FileCategory::Code, "nix"),
        "sql" => (FileCategory::Code, "sql"),
        "vim" => (FileCategory::Code, "vim"),
        "png" | "jpg" | "jpeg" | "svg" | "webp" | "gif" | "bmp" | "ico" => (FileCategory::Image, "image"),
        _ => (FileCategory::External, "external"),
    }
}

pub fn expand_user_path(raw: &str) -> PathBuf {
    let trimmed = raw.trim();
    if trimmed == "~" {
        if let Ok(home) = env::var("HOME") {
            if !home.is_empty() {
                return PathBuf::from(home);
            }
        }
    } else if let Some(rest) = trimmed.strip_prefix("~/").or_else(|| trimmed.strip_prefix("~\\")) {
        if let Ok(home) = env::var("HOME") {
            if !home.is_empty() {
                return PathBuf::from(home).join(rest);
            }
        }
    }
    PathBuf::from(trimmed)
}

pub fn resolve_vault_root(vault_str: &str) -> Result<PathBuf, String> {
    let trimmed = vault_str.trim();
    if trimmed.is_empty() {
        return Err("Vault path is empty".to_string());
    }
    let expanded = expand_user_path(trimmed);
    let canon = fs::canonicalize(&expanded).map_err(|e| format!("Cannot access vault '{}': {}", trimmed, e))?;
    if !canon.is_dir() {
        return Err(format!("Vault path '{}' is not a directory", trimmed));
    }
    Ok(canon)
}

pub fn sanitize_rel_path(rel_str: &str) -> Result<PathBuf, String> {
    let trimmed = rel_str.trim();
    if trimmed.is_empty() {
        return Err("Relative path is empty".to_string());
    }
    if trimmed.starts_with('/') || trimmed.starts_with('\\') {
        return Err("Absolute path rejected".to_string());
    }
    let cleaned = trimmed.replace('\\', "/");
    let p = Path::new(&cleaned);
    let mut normalized = PathBuf::new();
    for comp in p.components() {
        match comp {
            Component::Normal(seg) => {
                let s = seg.to_string_lossy();
                if s.is_empty() || s == "." || s == ".." {
                    return Err("Invalid path segment".to_string());
                }
                normalized.push(seg);
            }
            _ => return Err("Path traversal or non-relative path rejected".to_string()),
        }
    }
    if normalized.as_os_str().is_empty() {
        return Err("Relative path is empty".to_string());
    }
    Ok(normalized)
}

pub fn resolve_inside_vault(vault_canon: &Path, rel_str: &str, must_exist: bool) -> Result<(PathBuf, String), String> {
    let trimmed = rel_str.trim();
    let candidate_rel: String = if trimmed.starts_with('/') || trimmed.starts_with("~/") || trimmed.starts_with("~\\") {
        let expanded = expand_user_path(trimmed);
        if let Ok(stripped) = expanded.strip_prefix(vault_canon) {
            stripped.to_string_lossy().into_owned()
        } else if let Ok(canon_target) = fs::canonicalize(&expanded) {
            if let Ok(stripped) = canon_target.strip_prefix(vault_canon) {
                stripped.to_string_lossy().into_owned()
            } else {
                trimmed.to_string()
            }
        } else {
            trimmed.to_string()
        }
    } else {
        trimmed.to_string()
    };
    let rel = sanitize_rel_path(&candidate_rel)?;
    let joined = vault_canon.join(&rel);
    if must_exist {
        let target_canon = fs::canonicalize(&joined)
            .map_err(|e| format!("File '{}' not found in vault: {}", rel.display(), e))?;
        if !target_canon.starts_with(vault_canon) {
            return Err("Path escapes vault boundary".to_string());
        }
        let rel_norm = target_canon
            .strip_prefix(vault_canon)
            .map_err(|_| "Path escapes vault boundary".to_string())?
            .to_string_lossy()
            .replace('\\', "/");
        Ok((target_canon, rel_norm))
    } else {
        // Walk existing ancestors to ensure no symlink escapes the vault
        let mut ancestor = joined.as_path();
        while !ancestor.exists() {
            ancestor = ancestor
                .parent()
                .ok_or_else(|| "Cannot resolve parent directory inside vault".to_string())?;
        }
        let ancestor_canon = fs::canonicalize(ancestor)
            .map_err(|e| format!("Cannot canonicalize parent inside vault: {}", e))?;
        if !ancestor_canon.starts_with(vault_canon) {
            return Err("Parent directory escapes vault boundary".to_string());
        }
        let suffix = joined
            .strip_prefix(ancestor)
            .map_err(|_| "Invalid relative suffix".to_string())?;
        let final_path = if suffix.as_os_str().is_empty() {
            ancestor_canon
        } else {
            ancestor_canon.join(suffix)
        };
        if !final_path.starts_with(vault_canon) {
            return Err("Resolved path escapes vault boundary".to_string());
        }
        let rel_norm = final_path
            .strip_prefix(vault_canon)
            .map_err(|_| "Resolved path escapes vault boundary".to_string())?
            .to_string_lossy()
            .replace('\\', "/");
        Ok((final_path, rel_norm))
    }
}

fn should_skip_entry(name: &str) -> bool {
    if name.starts_with('.') {
        return true;
    }
    matches!(
        name,
        "node_modules" | "target" | "__pycache__" | ".git" | ".nexus" | ".trash" | ".stfolder" | "graphify-out" | "venv" | ".venv" | "dist" | "build"
    )
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TreeNode {
    pub name: String,
    pub rel_path: String,
    pub is_dir: bool,
    pub category: String,
    pub ext: String,
    pub mtime_secs: u64,
    pub size_bytes: u64,
    pub note_count: usize,
    #[serde(default)]
    pub prefix_code: String,
    #[serde(default)]
    pub color_hex: String,
    #[serde(default)]
    pub text_color_hex: String,
    #[serde(default)]
    pub icon_name: String,
    pub children: Vec<TreeNode>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FlatFileEntry {
    pub name: String,
    pub stem: String,
    pub rel_path: String,
    pub folder: String,
    pub top_folder: String,
    pub category: String,
    pub language: String,
    pub ext: String,
    pub mtime_secs: u64,
    pub size_bytes: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HeadingItem {
    pub level: usize,
    pub text: String,
    pub line: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BlockItem {
    pub id: usize,
    pub kind: String,
    pub level: usize,
    pub indent: usize,
    pub line_start: usize,
    pub line_end: usize,
    pub fold_end_line: usize,
    pub foldable: bool,
    pub todo_state: String,
    pub callout_type: String,
    pub title: String,
    pub lang: String,
    pub text: String,
    pub raw_text: String,
    pub rich_html: String,
    pub wikilinks: Vec<String>,
    pub tags: Vec<String>,
    pub table_headers: Vec<String>,
    pub table_rows: Vec<Vec<String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FlashcardCandidate {
    pub front: String,
    pub back: String,
    pub line: usize,
    pub kind: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ParsedNoteSummary {
    rel_path: String,
    stem: String,
    title: String,
    folder: String,
    top_folder: String,
    mtime_secs: u64,
    frontmatter: BTreeMap<String, String>,
    tags: Vec<String>,
    aliases: Vec<String>,
    outgoing_links: Vec<(String, usize, String)>, // (target_raw, line_1based, line_snippet)
    open_tasks: usize,
    done_tasks: usize,
    is_journal: bool,
    journal_date: Option<String>, // YYYY-MM-DD if detected
    snippet: String,
    #[serde(default)]
    has_templater_syntax: bool,
    #[serde(default)]
    finance_table_lines: Vec<String>,
    #[serde(skip)]
    lines: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CachedMarkdownEntry {
    mtime_secs: u64,
    mtime_nanos: u32,
    size_bytes: u64,
    summary: ParsedNoteSummary,
}

fn html_escape(input: &str) -> String {
    let mut out = String::with_capacity(input.len() + 16);
    for ch in input.chars() {
        match ch {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            _ => out.push(ch),
        }
    }
    out
}

fn is_image_target(path_str: &str) -> bool {
    let lower = path_str.trim().to_ascii_lowercase();
    [".png", ".jpg", ".jpeg", ".webp", ".gif", ".svg", ".bmp", ".ico"]
        .iter()
        .any(|ext| lower.ends_with(ext))
}

pub fn extract_wikilinks_from_line(line: &str) -> Vec<(String, String)> {
    // Returns Vec<(target_note, display_label)>
    let mut out = Vec::new();
    let bytes = line.as_bytes();
    let mut i = 0;
    while i + 3 < bytes.len() {
        if bytes[i] == b'[' && bytes[i + 1] == b'[' {
            let is_embed = i > 0 && bytes[i - 1] == b'!';
            if let Some(end_offset) = line[i + 2..].find("]]") {
                let inner = &line[i + 2..i + 2 + end_offset];
                if !inner.is_empty()
                    && !inner.contains('\n')
                    && !inner.contains('[')
                    && !inner.contains(']')
                {
                    let (target_part, alias_part) = match inner.split_once('|') {
                        Some((t, a)) => (t.trim(), a.trim()),
                        None => (inner.trim(), inner.trim()),
                    };
                    let base_target = match target_part.split_once('#') {
                        Some((b, _)) => b.trim(),
                        None => target_part,
                    };
                    if !base_target.is_empty() && !(is_embed && is_image_target(base_target)) && !is_image_target(base_target) {
                        let label = if alias_part.is_empty() { base_target } else { alias_part };
                        out.push((base_target.to_string(), label.to_string()));
                    }
                    i += 4 + end_offset;
                    continue;
                }
            }
        }
        i += 1;
    }
    out
}

pub fn extract_tags_from_line(line: &str) -> Vec<String> {
    let mut out = Vec::new();
    // Strip inline code `...`
    let mut cleaned = String::with_capacity(line.len());
    let mut in_code = false;
    for ch in line.chars() {
        if ch == '`' {
            in_code = !in_code;
        } else if !in_code {
            cleaned.push(ch);
        }
    }
    let chars: Vec<char> = cleaned.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        if chars[i] == '#' {
            let prev_ok = i == 0 || chars[i - 1].is_whitespace() || matches!(chars[i - 1], '(' | '[' | ',' | ';');
            if prev_ok && i + 1 < chars.len() {
                let mut j = i + 1;
                while j < chars.len()
                    && (chars[j].is_alphanumeric() || matches!(chars[j], '_' | '-' | '/'))
                {
                    j += 1;
                }
                if j > i + 1 {
                    let candidate: String = chars[i + 1..j].iter().collect();
                    // Reject pure hex/numbers like #123456
                    let has_alpha = candidate.chars().any(|c| c.is_alphabetic());
                    if has_alpha {
                        out.push(candidate);
                    }
                    i = j;
                    continue;
                }
            }
        }
        i += 1;
    }
    out
}

pub fn render_inline_rich_html(line: &str) -> String {
    // Converts [[wikilinks]], [[ ]] empty placeholders, [label](url), ![alt](url), <br>, #tags, **bold**, *italic*, _italic_, `code`, ==highlight==, $math$, and \n into styled HTML
    let mut result = String::with_capacity(line.len() * 2);
    let chars: Vec<char> = line.chars().collect();
    let n = chars.len();
    let mut i = 0;
    while i < n {
        // Check <br>, <br/>, <br />
        if chars[i] == '<' && i + 3 < n {
            let rem: String = chars[i.. (i + 7).min(n)].iter().collect();
            let rem_low = rem.to_ascii_lowercase();
            if rem_low.starts_with("<br>") {
                result.push_str("<br/>");
                i += 4;
                continue;
            } else if rem_low.starts_with("<br/>") {
                result.push_str("<br/>");
                i += 5;
                continue;
            } else if rem_low.starts_with("<br />") {
                result.push_str("<br/>");
                i += 6;
                continue;
            }
        }
        // Check ![[embed]]
        if i + 4 < n && chars[i] == '!' && chars[i + 1] == '[' && chars[i + 2] == '[' {
            let mut j = i + 3;
            while j + 1 < n
                && !(chars[j] == ']' && chars[j + 1] == ']')
                && chars[j] != '['
                && chars[j] != ']'
                && chars[j] != '\n'
            {
                j += 1;
            }
            if j + 1 < n && chars[j] == ']' && chars[j + 1] == ']' {
                let inner: String = chars[i + 3..j].iter().collect();
                let (target_part, alias_part) = match inner.split_once('|') {
                    Some((t, a)) => (t.trim(), a.trim()),
                    None => (inner.trim(), inner.trim()),
                };
                if !target_part.contains("Custom_Views/") {
                    let display = if alias_part.is_empty() || alias_part.chars().all(|c| c.is_ascii_digit()) {
                        target_part.rsplit('/').next().unwrap_or(target_part)
                    } else {
                        alias_part
                    };
                    result.push_str(&format!(
                        "<a href=\"wikilink:{}\" style=\"color:#38bdf8;text-decoration:none;\">🖼 {}</a>",
                        html_escape(target_part),
                        html_escape(display)
                    ));
                }
                i = j + 2;
                continue;
            }
        }
        // Check ![alt](url) external image/media link
        if i + 4 < n && chars[i] == '!' && chars[i + 1] == '[' && chars[i + 2] != '[' {
            let mut j = i + 2;
            while j < n && chars[j] != ']' && chars[j] != '\n' {
                j += 1;
            }
            if j + 2 < n && chars[j] == ']' && chars[j + 1] == '(' {
                let mut k = j + 2;
                while k < n && chars[k] != ')' && chars[k] != '\n' {
                    k += 1;
                }
                if k < n && chars[k] == ')' {
                    let label: String = chars[i + 2..j].iter().collect();
                    let url: String = chars[j + 2..k].iter().collect();
                    let url_t = url.trim();
                    let disp = if label.trim().is_empty() { url_t } else { label.trim() };
                    if !url_t.is_empty() {
                        result.push_str(&format!(
                            "<a href=\"{}\" style=\"color:#7dcfff;text-decoration:underline;\">▶ {}</a>",
                            html_escape(url_t),
                            html_escape(disp)
                        ));
                    }
                    i = k + 1;
                    continue;
                }
            }
        }
        // Check [[wikilink]] or empty [[ ]] placeholder
        if i + 3 < n && chars[i] == '[' && chars[i + 1] == '[' {
            let mut j = i + 2;
            while j + 1 < n
                && !(chars[j] == ']' && chars[j + 1] == ']')
                && chars[j] != '['
                && chars[j] != ']'
                && chars[j] != '\n'
            {
                j += 1;
            }
            if j + 1 < n && chars[j] == ']' && chars[j + 1] == ']' {
                let inner: String = chars[i + 2..j].iter().collect();
                let (target_part, alias_part) = match inner.split_once('|') {
                    Some((t, a)) => (t.trim(), a.trim()),
                    None => (inner.trim(), inner.trim()),
                };
                let base_target = match target_part.split_once('#') {
                    Some((b, _)) => b.trim(),
                    None => target_part,
                };
                let display = if alias_part.is_empty() { base_target } else { alias_part };
                if base_target.is_empty() && display.is_empty() {
                    result.push_str(
                        "<span style=\"background-color:#1e293b;color:#94a3b8;font-style:italic;padding:1px 6px;\">&nbsp;Related note&nbsp;</span>",
                    );
                } else {
                    result.push_str(&format!(
                        "<a href=\"wikilink:{}\" style=\"color:#7dd3fc;text-decoration:none;font-weight:600;\">{}</a>",
                        html_escape(base_target),
                        html_escape(display)
                    ));
                }
                i = j + 2;
                continue;
            }
        }
        // Check standard markdown link [label](url)
        if chars[i] == '[' && (i + 1 < n && chars[i + 1] != '[') {
            let mut j = i + 1;
            while j < n && chars[j] != ']' && chars[j] != '\n' {
                j += 1;
            }
            if j + 2 < n && chars[j] == ']' && chars[j + 1] == '(' {
                let mut k = j + 2;
                while k < n && chars[k] != ')' && chars[k] != '\n' {
                    k += 1;
                }
                if k < n && chars[k] == ')' {
                    let label: String = chars[i + 1..j].iter().collect();
                    let url: String = chars[j + 2..k].iter().collect();
                    let label_t = label.trim();
                    let url_t = url.trim();
                    if url_t.is_empty() {
                        let placeholder = if label_t.is_empty() { "Source" } else { label_t };
                        result.push_str(&format!(
                            "<span style=\"background-color:#1e293b;color:#94a3b8;font-style:italic;padding:1px 6px;\">&nbsp;{}&nbsp;</span>",
                            html_escape(placeholder)
                        ));
                    } else {
                        result.push_str(&format!(
                            "<a href=\"{}\" style=\"color:#7dcfff;text-decoration:underline;\">{}</a>",
                            html_escape(url_t),
                            html_escape(if label_t.is_empty() { url_t } else { label_t })
                        ));
                    }
                    i = k + 1;
                    continue;
                }
            }
        }
        // Check bare URL https:// or http://
        if (chars[i] == 'h' || chars[i] == 'H') && i + 8 < n {
            let prefix: String = chars[i..(i + 8).min(n)].iter().collect();
            let prefix_low = prefix.to_ascii_lowercase();
            if prefix_low.starts_with("https://") || prefix_low.starts_with("http://") {
                let mut j = i;
                while j < n && !chars[j].is_whitespace() && !matches!(chars[j], ')' | ']' | '>' | '"' | '\'') {
                    j += 1;
                }
                let url_str: String = chars[i..j].iter().collect();
                result.push_str(&format!(
                    "<a href=\"{}\" style=\"color:#7dcfff;text-decoration:underline;\">{}</a>",
                    html_escape(&url_str),
                    html_escape(&url_str)
                ));
                i = j;
                continue;
            }
        }
        // Check `inline code`
        if chars[i] == '`' {
            let mut j = i + 1;
            while j < n && chars[j] != '`' {
                j += 1;
            }
            if j < n {
                let code_str: String = chars[i + 1..j].iter().collect();
                let code_trim = code_str.trim();
                if code_trim.starts_with('[')
                    && code_trim.ends_with(')')
                    && (code_trim.contains("](http://") || code_trim.contains("](https://"))
                {
                    result.push_str(&render_inline_rich_html(code_trim));
                } else {
                    result.push_str(&format!(
                        "<span style=\"font-family:monospace;background-color:#1e293b;color:#f8fafc;padding:1px 4px;\">{}</span>",
                        html_escape(&code_str)
                    ));
                }
                i = j + 1;
                continue;
            }
        }
        // Check ==highlight==
        if i + 3 < n && chars[i] == '=' && chars[i + 1] == '=' {
            let mut j = i + 2;
            while j + 1 < n && !(chars[j] == '=' && chars[j + 1] == '=') {
                j += 1;
            }
            if j + 1 < n {
                let hi_str: String = chars[i + 2..j].iter().collect();
                result.push_str(&format!(
                    "<span style=\"background-color:#422006;color:#fde047;padding:0px 3px;\">{}</span>",
                    html_escape(&hi_str)
                ));
                i = j + 2;
                continue;
            }
        }
        // Check **bold**
        if i + 3 < n && chars[i] == '*' && chars[i + 1] == '*' {
            let mut j = i + 2;
            while j + 1 < n && !(chars[j] == '*' && chars[j + 1] == '*') {
                j += 1;
            }
            if j + 1 < n {
                let bold_str: String = chars[i + 2..j].iter().collect();
                result.push_str(&format!("<b>{}</b>", render_inline_rich_html(&bold_str)));
                i = j + 2;
                continue;
            }
        }
        // Check *italic*
        if chars[i] == '*' && i + 1 < n && chars[i + 1] != '*' && !chars[i + 1].is_whitespace() {
            let mut j = i + 1;
            while j < n && chars[j] != '*' && chars[j] != '\n' {
                j += 1;
            }
            if j < n && j > i + 1 && !chars[j - 1].is_whitespace() {
                let it_str: String = chars[i + 1..j].iter().collect();
                result.push_str(&format!("<i>{}</i>", render_inline_rich_html(&it_str)));
                i = j + 1;
                continue;
            }
        }
        // Check _italic_ (only at word/punctuation boundaries so snake_case and URLs are untouched)
        if chars[i] == '_'
            && i + 1 < n
            && chars[i + 1] != '_'
            && !chars[i + 1].is_whitespace()
            && (i == 0
                || chars[i - 1].is_whitespace()
                || matches!(chars[i - 1], '(' | '[' | '>' | '"' | '\'' | '-' | '–' | '—'))
        {
            let mut j = i + 1;
            while j < n && chars[j] != '_' && chars[j] != '\n' {
                j += 1;
            }
            if j < n
                && j > i + 1
                && !chars[j - 1].is_whitespace()
                && (j + 1 == n
                    || chars[j + 1].is_whitespace()
                    || matches!(chars[j + 1], '.' | ',' | ';' | ':' | '!' | '?' | ')' | ']' | '<' | '"' | '\'' | '-' | '–' | '—'))
            {
                let it_str: String = chars[i + 1..j].iter().collect();
                result.push_str(&format!("<i>{}</i>", render_inline_rich_html(&it_str)));
                i = j + 1;
                continue;
            }
        }
        // Check $math$
        if chars[i] == '$' && i + 1 < n && chars[i + 1] != ' ' {
            let mut j = i + 1;
            while j < n && chars[j] != '$' {
                j += 1;
            }
            if j < n && j > i + 1 {
                let math_str: String = chars[i + 1..j].iter().collect();
                result.push_str(&format!(
                    "<span style=\"font-family:serif;font-style:italic;color:#c084fc;\">∑ {}</span>",
                    html_escape(&math_str)
                ));
                i = j + 1;
                continue;
            }
        }
        // Check #tag
        if chars[i] == '#' {
            let prev_ok = i == 0 || chars[i - 1].is_whitespace();
            if prev_ok && i + 1 < n {
                let mut j = i + 1;
                while j < n && (chars[j].is_alphanumeric() || matches!(chars[j], '_' | '-' | '/')) {
                    j += 1;
                }
                if j > i + 1 {
                    let candidate: String = chars[i + 1..j].iter().collect();
                    if candidate.chars().any(|c| c.is_alphabetic()) {
                        result.push_str(&format!(
                            "<a href=\"tag:{}\" style=\"color:#38bdf8;text-decoration:none;\">#{}</a>",
                            html_escape(&candidate),
                            html_escape(&candidate)
                        ));
                        i = j;
                        continue;
                    }
                }
            }
        }
        match chars[i] {
            '\n' => result.push_str("<br/>"),
            '\r' => {}
            '&' => result.push_str("&amp;"),
            '<' => result.push_str("&lt;"),
            '>' => result.push_str("&gt;"),
            '"' => result.push_str("&quot;"),
            '\'' => result.push_str("&#39;"),
            ch => result.push(ch),
        }
        i += 1;
    }
    result
}

pub fn render_markdown_block_rich_html(raw: &str) -> String {
    let trimmed_all = raw.trim();
    if trimmed_all.is_empty() {
        return String::new();
    }
    let mut out = String::with_capacity(trimmed_all.len() * 2);
    let mut prev_blank = true;
    let raw_lines: Vec<&str> = trimmed_all.lines().collect();
    let mut idx = 0;
    while idx < raw_lines.len() {
        let raw_line = raw_lines[idx];
        let indent_spaces = raw_line
            .chars()
            .take_while(|c| *c == ' ' || *c == '\t')
            .fold(0usize, |acc, c| acc + if c == '\t' { 4 } else { 1 });
        let indent_html = "&nbsp;&nbsp;".repeat((indent_spaces / 2).min(6));
        let t = raw_line.trim();
        if t.is_empty() {
            if !prev_blank {
                out.push_str("<div style=\"margin-top:4px;margin-bottom:4px;\">&nbsp;</div>");
                prev_blank = true;
            }
            idx += 1;
            continue;
        }
        if t.starts_with("![[") && t.contains("Custom_Views/") {
            idx += 1;
            continue;
        }
        prev_blank = false;

        // Markdown table block (| col1 | col2 |)
        if t.starts_with('|') && t.ends_with('|') && t.len() > 2 {
            let mut table_rows: Vec<&str> = Vec::new();
            while idx < raw_lines.len() {
                let row_t = raw_lines[idx].trim();
                if row_t.starts_with('|') && row_t.ends_with('|') && row_t.len() > 2 {
                    table_rows.push(row_t);
                    idx += 1;
                } else {
                    break;
                }
            }
            if !table_rows.is_empty() {
                out.push_str("<table width=\"100%\" cellspacing=\"0\" cellpadding=\"6\" style=\"border-collapse:collapse;margin-top:6px;margin-bottom:6px;border:1px solid #334155;\">");
                let mut is_header = true;
                for row in table_rows {
                    let inner = &row[1..row.len() - 1];
                    let cells: Vec<&str> = inner.split('|').map(|c| c.trim()).collect();
                    let is_sep = cells.iter().all(|c| {
                        !c.is_empty() && c.chars().all(|ch| ch == '-' || ch == ':' || ch == ' ')
                    });
                    if is_sep {
                        is_header = false;
                        continue;
                    }
                    out.push_str("<tr>");
                    for cell in cells {
                        if is_header {
                            out.push_str(&format!(
                                "<th align=\"left\" style=\"background-color:#1e293b;color:#7dcfff;font-weight:700;padding:6px 8px;border:1px solid #334155;\">{}</th>",
                                render_inline_rich_html(cell)
                            ));
                        } else {
                            out.push_str(&format!(
                                "<td style=\"color:#e2e8f0;padding:5px 8px;border:1px solid #1e293b;\">{}</td>",
                                render_inline_rich_html(cell)
                            ));
                        }
                    }
                    out.push_str("</tr>");
                    is_header = false;
                }
                out.push_str("</table>");
                continue;
            }
        }

        // Horizontal rule (Qt RichText ignores CSS color on <hr/>; emit a 1px themed rule table
        // whose #334155 sentinel is re-themed dynamically by Nexus themeRichHtml)
        if t == "---" || t == "***" || t == "___" {
            out.push_str("<table width=\"100%\" cellspacing=\"0\" cellpadding=\"0\" style=\"margin-top:8px;margin-bottom:8px;\"><tr><td height=\"1\" style=\"background-color:#334155;font-size:1px;line-height:1px;\"></td></tr></table>");
            idx += 1;
            continue;
        }

        // Heading (# .. ######)
        let hashes = t.chars().take_while(|c| *c == '#').count();
        if (1..=6).contains(&hashes) && (t.len() == hashes || t[hashes..].starts_with(' ')) {
            let h_title = t[hashes..].trim();
            if !h_title.is_empty() {
                let (pt_size, top_m) = match hashes {
                    1 => ("14pt", "8px"),
                    2 => ("12pt", "6px"),
                    3 => ("11pt", "5px"),
                    _ => ("10pt", "4px"),
                };
                out.push_str(&format!(
                    "<div style=\"margin-top:{};margin-bottom:3px;\"><span style=\"color:#38bdf8;font-weight:700;font-size:{};\">{}</span ></div>",
                    top_m,
                    pt_size,
                    render_inline_rich_html(h_title)
                ));
            }
            idx += 1;
            continue;
        }

        // Blockquote / Callout line (> ...)
        if let Some(after_gt) = t.strip_prefix('>') {
            let q_trim = after_gt.trim();
            if q_trim.starts_with("[!multi-column") || q_trim.starts_with("[!blank") {
                idx += 1;
                continue;
            }
            if let Some(close_idx) = q_trim.strip_prefix("[!").and_then(|s| s.find(']')) {
                let rest_title = q_trim[2 + close_idx + 1..].trim();
                if !rest_title.is_empty() {
                    out.push_str(&format!(
                        "<div style=\"margin-top:4px;margin-bottom:2px;\"><span style=\"color:#38bdf8;font-weight:700;\">▎ {}</span></div>",
                        render_inline_rich_html(rest_title)
                    ));
                }
                idx += 1;
                continue;
            }
            if !q_trim.is_empty() {
                out.push_str(&format!(
                    "<div style=\"margin-top:2px;margin-bottom:2px;margin-left:6px;\"><span style=\"color:#38bdf8;font-weight:700;\">▎</span>&nbsp;{}</div>",
                    render_inline_rich_html(q_trim)
                ));
            }
            idx += 1;
            continue;
        }

        // Task list item (- [ ] / - [x])
        if let Some(task_body) = t
            .strip_prefix("- [ ] ")
            .or_else(|| t.strip_prefix("* [ ] "))
            .or_else(|| (t == "- [ ]" || t == "* [ ]").then_some(""))
        {
            out.push_str(&format!(
                "<div style=\"margin-top:2px;margin-bottom:2px;\">{}<span style=\"color:#38bdf8;font-family:monospace;font-weight:700;\">☐</span>&nbsp;&nbsp;{}</div>",
                indent_html,
                render_inline_rich_html(task_body.trim())
            ));
            idx += 1;
            continue;
        }
        if let Some(done_body) = t
            .strip_prefix("- [x] ")
            .or_else(|| t.strip_prefix("- [X] "))
            .or_else(|| t.strip_prefix("* [x] "))
            .or_else(|| t.strip_prefix("* [X] "))
            .or_else(|| (t == "- [x]" || t == "- [X]").then_some(""))
        {
            out.push_str(&format!(
                "<div style=\"margin-top:2px;margin-bottom:2px;\">{}<span style=\"color:#a6e3a1;font-family:monospace;font-weight:700;\">☑</span>&nbsp;&nbsp;<span style=\"color:#94a3b8;text-decoration:line-through;\">{}</span></div>",
                indent_html,
                render_inline_rich_html(done_body.trim())
            ));
            idx += 1;
            continue;
        }

        // Bullet list item (- / * / +) including bare "-" template bullets
        if let Some(bullet_body) = t
            .strip_prefix("- ")
            .or_else(|| t.strip_prefix("* "))
            .or_else(|| t.strip_prefix("+ "))
            .or_else(|| (t == "-" || t == "*" || t == "+").then_some(""))
        {
            out.push_str(&format!(
                "<div style=\"margin-top:2px;margin-bottom:2px;\">{}<span style=\"color:#38bdf8;font-weight:700;\">•</span>&nbsp;&nbsp;{}</div>",
                indent_html,
                render_inline_rich_html(bullet_body.trim())
            ));
            idx += 1;
            continue;
        }

        // Numbered list item (1. / 1))
        let digit_len = t.chars().take_while(|c| c.is_ascii_digit()).count();
        if digit_len > 0 && (t[digit_len..].starts_with(". ") || t[digit_len..].starts_with(") ")) {
            let num_prefix = &t[..digit_len + 1];
            let num_body = t[digit_len + 2..].trim();
            out.push_str(&format!(
                "<div style=\"margin-top:2px;margin-bottom:2px;\">{}<span style=\"color:#38bdf8;font-family:monospace;font-weight:700;\">{}</span>&nbsp;&nbsp;{}</div>",
                indent_html,
                html_escape(num_prefix),
                render_inline_rich_html(num_body)
            ));
            idx += 1;
            continue;
        }

        // Standard paragraph line
        out.push_str(&format!(
            "<div style=\"margin-top:2px;margin-bottom:2px;\">{}{}</div>",
            indent_html,
            render_inline_rich_html(t)
        ));
        idx += 1;
    }
    out
}

pub fn parse_frontmatter(lines: &[String]) -> (BTreeMap<String, String>, Vec<String>, Vec<String>, usize) {
    let mut props = BTreeMap::new();
    let mut tags = Vec::new();
    let mut aliases = Vec::new();
    if lines.is_empty() || lines[0].trim() != "---" {
        return (props, tags, aliases, 0);
    }
    let mut end_idx = None;
    for (idx, line) in lines.iter().enumerate().skip(1) {
        let trimmed = line.trim();
        if trimmed == "---" || trimmed == "..." {
            end_idx = Some(idx);
            break;
        }
    }
    let Some(end) = end_idx else {
        return (props, tags, aliases, 0);
    };
    let mut current_list_key = String::new();
    for line in &lines[1..end] {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        if let Some(rest) = trimmed.strip_prefix("- ").or_else(|| (trimmed == "-").then_some("")) {
            let item = rest.trim().trim_matches('"').trim_matches('\'').to_string();
            if !item.is_empty() && !current_list_key.is_empty() {
                let existing = props.entry(current_list_key.clone()).or_default();
                if existing.is_empty() {
                    *existing = item.clone();
                } else {
                    existing.push_str(", ");
                    existing.push_str(&item);
                }
                if current_list_key == "tags" || current_list_key == "tag" {
                    let clean_tag = item.trim_start_matches('#').to_string();
                    if !clean_tag.is_empty() && !tags.contains(&clean_tag) {
                        tags.push(clean_tag);
                    }
                } else if current_list_key == "aliases" || current_list_key == "alias" {
                    if !aliases.contains(&item) {
                        aliases.push(item);
                    }
                }
            }
            continue;
        }
        if let Some((k, v)) = trimmed.split_once(':') {
            let key = k.trim().to_ascii_lowercase();
            let val = v.trim();
            current_list_key = key.clone();
            if val.starts_with('[') && val.ends_with(']') {
                let inner = &val[1..val.len() - 1];
                let items: Vec<String> = inner
                    .split(',')
                    .map(|s| s.trim().trim_matches('"').trim_matches('\'').to_string())
                    .filter(|s| !s.is_empty())
                    .collect();
                props.insert(key.clone(), items.join(", "));
                if key == "tags" || key == "tag" {
                    for it in items {
                        let clean = it.trim_start_matches('#').to_string();
                        if !clean.is_empty() && !tags.contains(&clean) {
                            tags.push(clean);
                        }
                    }
                } else if key == "aliases" || key == "alias" {
                    for it in items {
                        if !aliases.contains(&it) {
                            aliases.push(it);
                        }
                    }
                }
            } else if !val.is_empty() {
                let clean_val = val.trim_matches('"').trim_matches('\'').to_string();
                props.insert(key.clone(), clean_val.clone());
                if key == "tags" || key == "tag" {
                    for part in clean_val.split(|c: char| c == ',' || c.is_whitespace()) {
                        let clean = part.trim().trim_start_matches('#').to_string();
                        if !clean.is_empty() && !tags.contains(&clean) {
                            tags.push(clean);
                        }
                    }
                } else if key == "aliases" || key == "alias" {
                    if !aliases.contains(&clean_val) {
                        aliases.push(clean_val);
                    }
                }
            }
        }
    }
    (props, tags, aliases, end + 1)
}

fn parse_list_or_task_line(line: &str) -> Option<(usize, String, String)> {
    // Returns Some((indent_spaces, todo_state, text_body))
    let indent_spaces = line.chars().take_while(|c| *c == ' ' || *c == '\t').fold(0usize, |acc, c| {
        acc + if c == '\t' { 4 } else { 1 }
    });
    let trimmed = line.trim_start();
    let bullet_rest = trimmed
        .strip_prefix("- ")
        .or_else(|| trimmed.strip_prefix("* "))
        .or_else(|| trimmed.strip_prefix("+ "))
        .or_else(|| {
            let digits = trimmed.chars().take_while(|c| c.is_ascii_digit()).count();
            if digits > 0 && trimmed[digits..].starts_with(". ") {
                Some(&trimmed[digits + 2..])
            } else {
                None
            }
        });
    if let Some(rest) = bullet_rest {
        if let Some(after) = rest.strip_prefix("[ ] ") {
            return Some((indent_spaces / 2, "TODO".to_string(), after.to_string()));
        }
        if let Some(after) = rest.strip_prefix("[x] ").or_else(|| rest.strip_prefix("[X] ")) {
            return Some((indent_spaces / 2, "DONE".to_string(), after.to_string()));
        }
        if let Some(after) = rest.strip_prefix("[-] ").or_else(|| rest.strip_prefix("[/] ")) {
            return Some((indent_spaces / 2, "DOING".to_string(), after.to_string()));
        }
        for kw in ["TODO ", "DONE ", "DOING ", "LATER ", "NOW "] {
            if let Some(after) = rest.strip_prefix(kw) {
                return Some((indent_spaces / 2, kw.trim().to_string(), after.to_string()));
            }
        }
        return Some((indent_spaces / 2, String::new(), rest.to_string()));
    }
    // Logseq top-level TODO / DONE without bullet
    for kw in ["TODO ", "DONE ", "DOING ", "LATER ", "NOW "] {
        if let Some(after) = trimmed.strip_prefix(kw) {
            return Some((indent_spaces / 2, kw.trim().to_string(), after.to_string()));
        }
    }
    None
}

pub fn parse_blocks(
    lines: &[String],
    body_start: usize,
) -> (Vec<BlockItem>, Vec<HeadingItem>, Vec<FlashcardCandidate>, usize, usize) {
    let mut blocks: Vec<BlockItem> = Vec::new();
    let mut outline: Vec<HeadingItem> = Vec::new();
    let mut flashcards: Vec<FlashcardCandidate> = Vec::new();
    let mut open_tasks = 0usize;
    let mut done_tasks = 0usize;

    let mut i = body_start;
    let n = lines.len();
    while i < n {
        let line = &lines[i];
        let trimmed = line.trim();
        let line_1based = i + 1;

        if trimmed.is_empty() {
            i += 1;
            continue;
        }

        // Check flashcard inline pattern: `front :: back`
        if let Some((left, right)) = trimmed.split_once(" :: ") {
            let front = left.trim_start_matches("- ").trim().to_string();
            let back = right.trim().to_string();
            if !front.is_empty() && !back.is_empty() {
                flashcards.push(FlashcardCandidate {
                    front,
                    back,
                    line: line_1based,
                    kind: "basic".to_string(),
                });
            }
        } else if trimmed.contains("{{c1::") {
            flashcards.push(FlashcardCandidate {
                front: trimmed.trim_start_matches("- ").to_string(),
                back: String::new(),
                line: line_1based,
                kind: "cloze".to_string(),
            });
        }

        // 1. Code fence ```
        if let Some(fence_lang) = trimmed.strip_prefix("```") {
            let lang = fence_lang.trim().to_string();
            let mut j = i + 1;
            let mut code_lines = Vec::new();
            while j < n && !lines[j].trim().starts_with("```") {
                code_lines.push(lines[j].clone());
                j += 1;
            }
            let end_line = if j < n { j + 1 } else { n };
            let body = code_lines.join("\n");
            let is_dataview_widget = (lang.eq_ignore_ascii_case("dataviewjs") || lang.eq_ignore_ascii_case("dataview"))
                && (body.contains("dv.view(")
                    || body.contains("dv.current()")
                    || body.contains("obsidian-HTML-Widgets"));
            if !is_dataview_widget {
                let id = blocks.len();
                blocks.push(BlockItem {
                    id,
                    kind: "code".to_string(),
                    level: 0,
                    indent: 0,
                    line_start: line_1based,
                    line_end: end_line,
                    fold_end_line: end_line,
                    foldable: code_lines.len() > 1,
                    todo_state: String::new(),
                    callout_type: String::new(),
                    title: if lang.is_empty() { "code".to_string() } else { lang.clone() },
                    lang,
                    text: body.clone(),
                    raw_text: lines[i..end_line].join("\n"),
                    rich_html: html_escape(&body),
                    wikilinks: Vec::new(),
                    tags: Vec::new(),
                    table_headers: Vec::new(),
                    table_rows: Vec::new(),
                });
            }
            i = if j < n { j + 1 } else { n };
            continue;
        }

        // 2. Math block $$
        if trimmed.starts_with("$$") {
            let mut j = i;
            let mut math_lines = Vec::new();
            if trimmed.len() >= 4 && trimmed.ends_with("$$") {
                let inner = trimmed[2..trimmed.len() - 2].trim().to_string();
                math_lines.push(inner);
            } else {
                if trimmed.len() > 2 {
                    math_lines.push(trimmed[2..].to_string());
                }
                j += 1;
                while j < n && !lines[j].trim().ends_with("$$") {
                    math_lines.push(lines[j].clone());
                    j += 1;
                }
                if j < n {
                    let last = lines[j].trim().trim_end_matches("$$").trim();
                    if !last.is_empty() {
                        math_lines.push(last.to_string());
                    }
                }
            }
            let end_line = (j + 1).min(n);
            let body = math_lines.join("\n");
            let id = blocks.len();
            blocks.push(BlockItem {
                id,
                kind: "math".to_string(),
                level: 0,
                indent: 0,
                line_start: line_1based,
                line_end: end_line,
                fold_end_line: end_line,
                foldable: false,
                todo_state: String::new(),
                callout_type: String::new(),
                title: "LaTeX".to_string(),
                lang: "latex".to_string(),
                text: body.clone(),
                raw_text: lines[i..end_line].join("\n"),
                rich_html: html_escape(&body),
                wikilinks: Vec::new(),
                tags: Vec::new(),
                table_headers: Vec::new(),
                table_rows: Vec::new(),
            });
            i = end_line;
            continue;
        }

        // 3. Callout > [!TYPE] Title
        if trimmed.starts_with("> [!") {
            if let Some(close_bracket) = trimmed.find(']') {
                if close_bracket >= 4 {
                    let ctype = trimmed[4..close_bracket]
                        .trim()
                        .trim_end_matches('+')
                        .trim_end_matches('-')
                        .to_ascii_uppercase();
                    let mut ctitle = trimmed[close_bracket + 1..].trim().to_string();
                    let mut j = i + 1;
                    let mut body_lines = Vec::new();
                    let mut in_nested_fence = false;
                    while j < n && lines[j].trim().starts_with('>') {
                        let stripped = lines[j]
                            .trim()
                            .trim_start_matches('>')
                            .trim()
                            .to_string();
                        j += 1;
                        if stripped.starts_with("```") {
                            in_nested_fence = !in_nested_fence;
                            continue;
                        }
                        if in_nested_fence {
                            continue;
                        }
                        if stripped.starts_with("[!blank") || stripped.starts_with("[!multi-column") {
                            continue;
                        }
                        if let Some(h3) = stripped.strip_prefix("### ") {
                            if ctitle.is_empty() {
                                ctitle = h3.trim().to_string();
                                continue;
                            }
                        }
                        if !stripped.is_empty() {
                            body_lines.push(stripped);
                        }
                    }
                    let end_line = j;
                    let body = body_lines.join("\n");
                    if ctype == "MULTI-COLUMN" && body.trim().is_empty() {
                        i = j;
                        continue;
                    }
                    let wlinks: Vec<String> = lines[i..end_line]
                        .iter()
                        .flat_map(|l| extract_wikilinks_from_line(l).into_iter().map(|(t, _)| t))
                        .collect();
                    let btags: Vec<String> = lines[i..end_line]
                        .iter()
                        .flat_map(|l| extract_tags_from_line(l))
                        .collect();
                    let id = blocks.len();
                    blocks.push(BlockItem {
                        id,
                        kind: "callout".to_string(),
                        level: 0,
                        indent: 0,
                        line_start: line_1based,
                        line_end: end_line,
                        fold_end_line: end_line,
                        foldable: true,
                        todo_state: String::new(),
                        callout_type: ctype.clone(),
                        title: if ctitle.is_empty() {
                            if ctype == "MULTI-COLUMN" { "Overview".to_string() } else { ctype }
                        } else {
                            ctitle
                        },
                        lang: String::new(),
                        text: body.clone(),
                        raw_text: lines[i..end_line].join("\n"),
                        rich_html: render_inline_rich_html(&body),
                        wikilinks: wlinks,
                        tags: btags,
                        table_headers: Vec::new(),
                        table_rows: Vec::new(),
                    });
                    i = j;
                    continue;
                }
            }
        }

        // 4. Table | col1 | col2 |
        if trimmed.starts_with('|') && trimmed.ends_with('|') && trimmed.len() > 2 {
            let mut j = i;
            let mut raw_rows = Vec::new();
            while j < n {
                let r = lines[j].trim();
                if r.starts_with('|') && r.ends_with('|') {
                    raw_rows.push(r.to_string());
                    j += 1;
                } else {
                    break;
                }
            }
            let parse_cells = |row_str: &str| -> Vec<String> {
                row_str[1..row_str.len() - 1]
                    .split('|')
                    .map(|c| c.trim().to_string())
                    .collect()
            };
            let headers = if !raw_rows.is_empty() {
                parse_cells(&raw_rows[0])
            } else {
                Vec::new()
            };
            let mut data_rows = Vec::new();
            for (r_idx, r_str) in raw_rows.iter().enumerate().skip(1) {
                let cells = parse_cells(r_str);
                // Skip separator row |---|---|
                let is_sep = cells
                    .iter()
                    .all(|c| !c.is_empty() && c.chars().all(|ch| matches!(ch, '-' | ':' | ' ')));
                if r_idx == 1 && is_sep {
                    continue;
                }
                data_rows.push(cells);
            }
            let end_line = j;
            let id = blocks.len();
            blocks.push(BlockItem {
                id,
                kind: "table".to_string(),
                level: 0,
                indent: 0,
                line_start: line_1based,
                line_end: end_line,
                fold_end_line: end_line,
                foldable: data_rows.len() > 2,
                todo_state: String::new(),
                callout_type: String::new(),
                title: format!("Table ({} rows)", data_rows.len()),
                lang: String::new(),
                text: raw_rows.join("\n"),
                raw_text: raw_rows.join("\n"),
                rich_html: String::new(),
                wikilinks: Vec::new(),
                tags: Vec::new(),
                table_headers: headers,
                table_rows: data_rows,
            });
            i = j;
            continue;
        }

        // 5. Heading # .. ######
        let hashes = trimmed.chars().take_while(|c| *c == '#').count();
        if (1..=6).contains(&hashes) && trimmed[hashes..].starts_with(' ') {
            let h_text = trimmed[hashes..].trim().to_string();
            outline.push(HeadingItem {
                level: hashes,
                text: h_text.clone(),
                line: line_1based,
            });
            let wlinks = extract_wikilinks_from_line(&h_text)
                .into_iter()
                .map(|(t, _)| t)
                .collect();
            let btags = extract_tags_from_line(&h_text);
            let h_trim = h_text.trim();
            let cornell_marker = if hashes == 3 {
                if h_trim == "?" || h_trim.starts_with("? ") {
                    "CORNELL_QUESTION"
                } else if h_trim == "!" || h_trim.starts_with("! ") {
                    "CORNELL_IMPORTANT"
                } else if h_trim == "." || h_trim.starts_with(". ") {
                    "CORNELL_KEY"
                } else if h_trim.eq_ignore_ascii_case("E-")
                    || h_trim.get(..3).map_or(false, |p| p.eq_ignore_ascii_case("E- "))
                {
                    "CORNELL_EXAMPLE"
                } else if h_trim.eq_ignore_ascii_case("V-")
                    || h_trim.get(..3).map_or(false, |p| p.eq_ignore_ascii_case("V- "))
                {
                    "CORNELL_VOCAB"
                } else if h_trim.eq_ignore_ascii_case("X-")
                    || h_trim.get(..3).map_or(false, |p| p.eq_ignore_ascii_case("X- "))
                {
                    "CORNELL_REF"
                } else if h_trim.eq_ignore_ascii_case("R-")
                    || h_trim.get(..3).map_or(false, |p| p.eq_ignore_ascii_case("R- "))
                {
                    "CORNELL_RESEARCH"
                } else if h_trim == "*" || h_trim.starts_with("* ") {
                    "CORNELL_GENERAL"
                } else if h_trim.eq_ignore_ascii_case("Summary") {
                    "CORNELL_SUMMARY"
                } else {
                    ""
                }
            } else {
                ""
            };
            let id = blocks.len();
            blocks.push(BlockItem {
                id,
                kind: "heading".to_string(),
                level: hashes,
                indent: 0,
                line_start: line_1based,
                line_end: line_1based,
                fold_end_line: line_1based,
                foldable: true,
                todo_state: String::new(),
                callout_type: cornell_marker.to_string(),
                title: h_text.clone(),
                lang: String::new(),
                text: h_text.clone(),
                raw_text: line.clone(),
                rich_html: render_inline_rich_html(&h_text),
                wikilinks: wlinks,
                tags: btags,
                table_headers: Vec::new(),
                table_rows: Vec::new(),
            });
            i += 1;
            continue;
        }

        // 6. Horizontal rule --- or ***
        if (trimmed == "---" || trimmed == "***" || trimmed == "___") && i > body_start {
            let id = blocks.len();
            blocks.push(BlockItem {
                id,
                kind: "divider".to_string(),
                level: 0,
                indent: 0,
                line_start: line_1based,
                line_end: line_1based,
                fold_end_line: line_1based,
                foldable: false,
                todo_state: String::new(),
                callout_type: String::new(),
                title: String::new(),
                lang: String::new(),
                text: "---".to_string(),
                raw_text: line.clone(),
                rich_html: String::new(),
                wikilinks: Vec::new(),
                tags: Vec::new(),
                table_headers: Vec::new(),
                table_rows: Vec::new(),
            });
            i += 1;
            continue;
        }

        // 7. Standalone image embed ![[image.png|width]]
        if trimmed.starts_with("![[") && trimmed.ends_with("]]") && trimmed.len() > 5 {
            let inner = &trimmed[3..trimmed.len() - 2];
            let (target_part, size_or_alt) = match inner.split_once('|') {
                Some((t, a)) => (t.trim(), a.trim()),
                None => (inner.trim(), ""),
            };
            if is_image_target(target_part) {
                let id = blocks.len();
                blocks.push(BlockItem {
                    id,
                    kind: "image".to_string(),
                    level: 0,
                    indent: 0,
                    line_start: line_1based,
                    line_end: line_1based,
                    fold_end_line: line_1based,
                    foldable: false,
                    todo_state: String::new(),
                    callout_type: size_or_alt.to_string(),
                    title: target_part.rsplit('/').next().unwrap_or(target_part).to_string(),
                    lang: String::new(),
                    text: target_part.to_string(),
                    raw_text: line.clone(),
                    rich_html: render_inline_rich_html(trimmed),
                    wikilinks: Vec::new(),
                    tags: Vec::new(),
                    table_headers: Vec::new(),
                    table_rows: Vec::new(),
                });
                i += 1;
                continue;
            }
        }

        // 8. Outliner Bullet / Task item
        if let Some((indent, todo_state, item_text)) = parse_list_or_task_line(line) {
            if !todo_state.is_empty() {
                if todo_state == "DONE" {
                    done_tasks += 1;
                } else {
                    open_tasks += 1;
                }
            }
            let wlinks = extract_wikilinks_from_line(&item_text)
                .into_iter()
                .map(|(t, _)| t)
                .collect();
            let btags = extract_tags_from_line(&item_text);
            let id = blocks.len();
            blocks.push(BlockItem {
                id,
                kind: if todo_state.is_empty() {
                    "bullet".to_string()
                } else {
                    "todo".to_string()
                },
                level: 0,
                indent,
                line_start: line_1based,
                line_end: line_1based,
                fold_end_line: line_1based,
                foldable: false,
                todo_state,
                callout_type: String::new(),
                title: String::new(),
                lang: String::new(),
                text: item_text.clone(),
                raw_text: line.clone(),
                rich_html: render_inline_rich_html(&item_text),
                wikilinks: wlinks,
                tags: btags,
                table_headers: Vec::new(),
                table_rows: Vec::new(),
            });
            i += 1;
            continue;
        }

        // 9. Quote > ...
        if let Some(q_rest) = trimmed.strip_prefix("> ").or_else(|| trimmed.strip_prefix('>')) {
            let q_text = q_rest.trim().to_string();
            let wlinks = extract_wikilinks_from_line(&q_text)
                .into_iter()
                .map(|(t, _)| t)
                .collect();
            let btags = extract_tags_from_line(&q_text);
            let id = blocks.len();
            blocks.push(BlockItem {
                id,
                kind: "quote".to_string(),
                level: 0,
                indent: 0,
                line_start: line_1based,
                line_end: line_1based,
                fold_end_line: line_1based,
                foldable: false,
                todo_state: String::new(),
                callout_type: String::new(),
                title: String::new(),
                lang: String::new(),
                text: q_text.clone(),
                raw_text: line.clone(),
                rich_html: render_inline_rich_html(&q_text),
                wikilinks: wlinks,
                tags: btags,
                table_headers: Vec::new(),
                table_rows: Vec::new(),
            });
            i += 1;
            continue;
        }

        // 10. Paragraph line
        let wlinks = extract_wikilinks_from_line(trimmed)
            .into_iter()
            .map(|(t, _)| t)
            .collect();
        let btags = extract_tags_from_line(trimmed);
        let id = blocks.len();
        blocks.push(BlockItem {
            id,
            kind: "paragraph".to_string(),
            level: 0,
            indent: 0,
            line_start: line_1based,
            line_end: line_1based,
            fold_end_line: line_1based,
            foldable: false,
            todo_state: String::new(),
            callout_type: String::new(),
            title: String::new(),
            lang: String::new(),
            text: trimmed.to_string(),
            raw_text: line.clone(),
            rich_html: render_inline_rich_html(trimmed),
            wikilinks: wlinks,
            tags: btags,
            table_headers: Vec::new(),
            table_rows: Vec::new(),
        });
        i += 1;
    }

    // Compute hierarchical fold ranges for headings and indented outliner blocks
    let block_count = blocks.len();
    for idx in 0..block_count {
        if blocks[idx].kind == "heading" {
            let h_level = blocks[idx].level;
            let mut fold_end = blocks[idx].line_end;
            for next in (idx + 1)..block_count {
                if blocks[next].kind == "heading" && blocks[next].level <= h_level {
                    break;
                }
                fold_end = blocks[next].line_end;
            }
            blocks[idx].fold_end_line = fold_end;
            blocks[idx].foldable = fold_end > blocks[idx].line_end;
        } else if blocks[idx].kind == "bullet" || blocks[idx].kind == "todo" {
            let base_indent = blocks[idx].indent;
            let mut fold_end = blocks[idx].line_end;
            for next in (idx + 1)..block_count {
                if (blocks[next].kind == "bullet" || blocks[next].kind == "todo")
                    && blocks[next].indent > base_indent
                {
                    fold_end = blocks[next].line_end;
                } else {
                    break;
                }
            }
            blocks[idx].fold_end_line = fold_end;
            blocks[idx].foldable = fold_end > blocks[idx].line_end;
        }
    }

    (blocks, outline, flashcards, open_tasks, done_tasks)
}

// Civil calendar utilities
pub fn is_leap_year(year: i32) -> bool {
    (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
}

pub fn days_in_month(year: i32, month: u32) -> u32 {
    match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 => {
            if is_leap_year(year) {
                29
            } else {
                28
            }
        }
        _ => 30,
    }
}

// Howard Hinnant's civil_from_days / days_from_civil algorithm
pub fn days_from_civil(y: i32, m: u32, d: u32) -> i64 {
    let y = y - if m <= 2 { 1 } else { 0 };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = (y - era * 400) as u32;
    let m_adj = if m > 2 { m - 3 } else { m + 9 };
    let doy = (153 * m_adj + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    (era as i64) * 146097 + (doe as i64) - 719468
}

pub fn civil_from_days(z: i64) -> (i32, u32, u32) {
    let z = z + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = (z - (era * 146097)) as u32;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = (yoe as i32) + (era as i32) * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = y + if m <= 2 { 1 } else { 0 };
    (year, m, d)
}

pub fn weekday_monday_zero(year: i32, month: u32, day: u32) -> u32 {
    // 1970-01-01 was Thursday (3 in Mon=0..Sun=6)
    let days = days_from_civil(year, month, day);
    ((days + 3).rem_euclid(7)) as u32
}

pub fn month_name(month: u32) -> &'static str {
    match month {
        1 => "January",
        2 => "February",
        3 => "March",
        4 => "April",
        5 => "May",
        6 => "June",
        7 => "July",
        8 => "August",
        9 => "September",
        10 => "October",
        11 => "November",
        12 => "December",
        _ => "January",
    }
}

pub fn month_short_name(month: u32) -> &'static str {
    match month {
        1 => "Jan",
        2 => "Feb",
        3 => "Mar",
        4 => "Apr",
        5 => "May",
        6 => "Jun",
        7 => "Jul",
        8 => "Aug",
        9 => "Sep",
        10 => "Oct",
        11 => "Nov",
        12 => "Dec",
        _ => "Jan",
    }
}

pub fn weekday_name(weekday_mon0: u32) -> &'static str {
    match weekday_mon0 {
        0 => "Monday",
        1 => "Tuesday",
        2 => "Wednesday",
        3 => "Thursday",
        4 => "Friday",
        5 => "Saturday",
        _ => "Sunday",
    }
}

pub fn detect_journal_date_from_path(rel_path: &str, stem: &str) -> Option<String> {
    // Recognizes:
    // 1. YYYY-MM-DD or YYYY_MM_DD anywhere in stem
    // 2. DD-MM-YYYY anywhere in stem (e.g. 07-11-2026-Saturday)
    let chars: Vec<char> = stem.chars().collect();
    if chars.len() >= 10 {
        for i in 0..=(chars.len() - 10) {
            let window = &chars[i..i + 10];
            if !window.iter().all(|c| c.is_ascii()) {
                continue;
            }
            let s: String = window.iter().collect();
            let b = s.as_bytes();
            // YYYY-MM-DD or YYYY_MM_DD
            if (b[4] == b'-' || b[4] == b'_') && (b[7] == b'-' || b[7] == b'_') {
                if let (Ok(y), Ok(m), Ok(d)) = (
                    s[0..4].parse::<i32>(),
                    s[5..7].parse::<u32>(),
                    s[8..10].parse::<u32>(),
                ) {
                    if (1970..=2100).contains(&y) && (1..=12).contains(&m) && (1..=31).contains(&d) {
                        return Some(format!("{:04}-{:02}-{:02}", y, m, d));
                    }
                }
            }
            // DD-MM-YYYY or DD_MM_YYYY
            if (b[2] == b'-' || b[2] == b'_') && (b[5] == b'-' || b[5] == b'_') {
                if let (Ok(d), Ok(m), Ok(y)) = (
                    s[0..2].parse::<u32>(),
                    s[3..5].parse::<u32>(),
                    s[6..10].parse::<i32>(),
                ) {
                    if (1970..=2100).contains(&y) && (1..=12).contains(&m) && (1..=31).contains(&d) {
                        return Some(format!("{:04}-{:02}-{:02}", y, m, d));
                    }
                }
            }
        }
    }
    let lower = rel_path.to_ascii_lowercase();
    if lower.contains("journal") || lower.contains("daily") {
        // Check if stem is YYYYMMDD
        if stem.len() == 8 && stem.chars().all(|c| c.is_ascii_digit()) {
            if let (Ok(y), Ok(m), Ok(d)) = (
                stem[0..4].parse::<i32>(),
                stem[4..6].parse::<u32>(),
                stem[6..8].parse::<u32>(),
            ) {
                if (1970..=2100).contains(&y) && (1..=12).contains(&m) && (1..=31).contains(&d) {
                    return Some(format!("{:04}-{:02}-{:02}", y, m, d));
                }
            }
        }
    }
    None
}

pub fn format_daily_note_rel_path(folder: &str, format_pattern: &str, year: i32, month: u32, day: u32) -> String {
    let wd = weekday_monday_zero(year, month, day);
    let mut rendered = if format_pattern.trim().is_empty() {
        "YYYY/MMMM/DD-MM-YYYY-dddd".to_string()
    } else {
        format_pattern.trim().trim_end_matches(".md").to_string()
    };
    // Replace tokens longest-first so YYYY/MMMM/dddd are replaced before YY/MM/dd
    rendered = rendered.replace("YYYY", &format!("{:04}", year));
    rendered = rendered.replace("MMMM", month_name(month));
    rendered = rendered.replace("MMM", month_short_name(month));
    rendered = rendered.replace("dddd", weekday_name(wd));
    rendered = rendered.replace("MM", &format!("{:02}", month));
    rendered = rendered.replace("DD", &format!("{:02}", day));
    let clean_folder = folder.trim().trim_matches('/');
    if clean_folder.is_empty() {
        format!("{}.md", rendered.trim_matches('/'))
    } else {
        format!("{}/{}.md", clean_folder, rendered.trim_matches('/'))
    }
}

#[inline]
fn contains_ascii_case_insensitive(haystack: &str, needle_lower: &str) -> bool {
    let hb = haystack.as_bytes();
    let nb = needle_lower.as_bytes();
    if nb.is_empty() {
        return true;
    }
    if hb.len() < nb.len() {
        return false;
    }
    let first = nb[0];
    let first_upper = first.to_ascii_uppercase();
    let limit = hb.len() - nb.len();
    let mut i = 0usize;
    while i <= limit {
        let c = hb[i];
        if c == first || c == first_upper {
            let mut matched = true;
            for j in 1..nb.len() {
                if hb[i + j].to_ascii_lowercase() != nb[j] {
                    matched = false;
                    break;
                }
            }
            if matched {
                return true;
            }
        }
        i += 1;
    }
    false
}

#[inline]
fn starts_with_ascii_case_insensitive(haystack: &str, prefix_lower: &str) -> bool {
    let hb = haystack.as_bytes();
    let pb = prefix_lower.as_bytes();
    if hb.len() < pb.len() {
        return false;
    }
    for i in 0..pb.len() {
        if hb[i].to_ascii_lowercase() != pb[i] {
            return false;
        }
    }
    true
}

struct UncachedMarkdownJob {
    slot_idx: usize,
    full_path: PathBuf,
    rel_path: String,
    stem: String,
    folder: String,
    top_folder: String,
    mtime_secs: u64,
    mtime_nanos: u32,
    size_bytes: u64,
}

fn parse_markdown_note_file(
    full_path: &Path,
    rel_path: &str,
    stem: &str,
    folder: &str,
    top_folder: &str,
    mtime_secs: u64,
    retain_lines: bool,
) -> Option<ParsedNoteSummary> {
    let content = fs::read_to_string(full_path).ok()?;
    let lines: Vec<String> = content.lines().map(|s| s.to_string()).collect();
    let has_templater_syntax = lines
        .iter()
        .take(25)
        .any(|l| l.contains("<%") && l.contains("%>"));
    let (props, mut fm_tags, aliases, body_start) = parse_frontmatter(&lines);
    let is_fin_ledger = !contains_ascii_case_insensitive(rel_path, "22_finance/records/")
        && (contains_ascii_case_insensitive(rel_path, "finance")
            || props
                .get("categories")
                .map(|c| contains_ascii_case_insensitive(c, "finance"))
                .unwrap_or(false));
    let finance_table_lines: Vec<String> = if is_fin_ledger {
        lines
            .iter()
            .filter(|l| {
                let t = l.trim();
                t.starts_with("##") || (t.starts_with('|') && t.ends_with('|'))
            })
            .cloned()
            .collect()
    } else {
        Vec::new()
    };
    let mut outgoing = Vec::new();
    let mut open_tasks = 0usize;
    let mut done_tasks = 0usize;
    let mut first_heading = String::new();
    let mut snippet = String::new();
    let mut in_fence = false;

    for line in lines.iter().take(body_start) {
        let t = line.trim();
        if t.contains("[[") {
            for (target, _) in extract_wikilinks_from_line(t) {
                outgoing.push((target, 1, t.chars().take(160).collect()));
            }
        }
    }

    for (idx, line) in lines.iter().enumerate().skip(body_start) {
        let t = line.trim();
        if t.starts_with("```") {
            in_fence = !in_fence;
            continue;
        }
        if in_fence || t.is_empty() {
            continue;
        }
        if first_heading.is_empty() && t.starts_with("# ") {
            let candidate = t[2..].trim();
            if !candidate.is_empty()
                && !matches!(candidate, "Day Planner" | "Daily Schedule" | "Daily Log")
                && !candidate.contains("<%")
                && !candidate.ends_with('-')
            {
                first_heading = candidate.to_string();
            }
        } else if snippet.is_empty()
            && !t.starts_with('#')
            && !t.starts_with("---")
            && !t.starts_with("> [!")
            && !t.starts_with(">> [!")
        {
            snippet = t.trim_start_matches('>').trim().chars().take(140).collect();
        }
        if t.contains("[[") {
            for (target, _) in extract_wikilinks_from_line(t) {
                outgoing.push((target, idx + 1, t.chars().take(160).collect()));
            }
        }
        if t.contains('#') {
            for tag in extract_tags_from_line(t) {
                if !fm_tags.contains(&tag) {
                    fm_tags.push(tag);
                }
            }
        }
        let lb = t.as_bytes();
        if matches!(lb.first(), Some(b'-' | b'*' | b'+' | b'T' | b'D')) {
            if let Some((_, todo_st, _)) = parse_list_or_task_line(line) {
                if !todo_st.is_empty() {
                    if todo_st == "DONE" {
                        done_tasks += 1;
                    } else {
                        open_tasks += 1;
                    }
                }
            }
        }
    }
    if snippet.is_empty() {
        if let Some(plot) = props.get("plot").or_else(|| props.get("description")) {
            snippet = plot.chars().take(140).collect();
        }
    }
    let title = props
        .get("title")
        .or_else(|| props.get("name"))
        .cloned()
        .filter(|s| !s.is_empty() && !s.contains("<%"))
        .or_else(|| (!first_heading.is_empty()).then_some(first_heading))
        .unwrap_or_else(|| stem.to_string());
    let journal_date = detect_journal_date_from_path(rel_path, stem);
    let is_journal = journal_date.is_some()
        || contains_ascii_case_insensitive(rel_path, "journal")
        || props.get("type").map(|v| v.eq_ignore_ascii_case("journal")).unwrap_or(false);

    Some(ParsedNoteSummary {
        rel_path: rel_path.to_string(),
        stem: stem.to_string(),
        title,
        folder: folder.to_string(),
        top_folder: top_folder.to_string(),
        mtime_secs,
        frontmatter: props,
        tags: fm_tags,
        aliases,
        outgoing_links: outgoing,
        open_tasks,
        done_tasks,
        is_journal,
        journal_date,
        snippet,
        has_templater_syntax,
        finance_table_lines,
        lines: if retain_lines { lines } else { Vec::new() },
    })
}

fn scan_directory_recursive(
    vault_canon: &Path,
    dir: &Path,
    flat_files: &mut Vec<FlatFileEntry>,
    notes: &mut Vec<ParsedNoteSummary>,
) -> TreeNode {
    let mut stats = (0usize, 0usize);
    scan_directory_recursive_with_cache(
        vault_canon,
        dir,
        flat_files,
        notes,
        None,
        None,
        &mut stats,
        true,
    )
}

fn walk_directory_collect_jobs(
    vault_canon: &Path,
    dir: &Path,
    flat_files: &mut Vec<FlatFileEntry>,
    note_slots: &mut Vec<Option<ParsedNoteSummary>>,
    uncached_jobs: &mut Vec<UncachedMarkdownJob>,
    prev_cache: Option<&HashMap<String, CachedMarkdownEntry>>,
    mut next_cache: Option<&mut BTreeMap<String, CachedMarkdownEntry>>,
    cache_stats: &mut (usize, usize),
    retain_lines: bool,
) -> TreeNode {
    let rel_dir = dir
        .strip_prefix(vault_canon)
        .map(|p| p.to_string_lossy().replace('\\', "/"))
        .unwrap_or_default();
    let dir_name = if rel_dir.is_empty() {
        vault_canon
            .file_name()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_else(|| "Vault".to_string())
    } else {
        dir.file_name()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_default()
    };

    let mut subdirs = Vec::new();
    let mut files = Vec::new();
    if let Ok(entries) = fs::read_dir(dir) {
        let mut collected: Vec<_> = entries.flatten().collect();
        collected.sort_by_key(|e| e.file_name());
        for entry in collected {
            let fname = entry.file_name().to_string_lossy().to_string();
            if should_skip_entry(&fname) {
                continue;
            }
            let Ok(ft) = entry.file_type() else { continue };
            if ft.is_symlink() {
                continue;
            }
            let full_path = entry.path();
            if ft.is_dir() {
                if full_path != vault_canon && full_path.join(".git").exists() {
                    continue;
                }
                let child_node = walk_directory_collect_jobs(
                    vault_canon,
                    &full_path,
                    flat_files,
                    note_slots,
                    uncached_jobs,
                    prev_cache,
                    next_cache.as_deref_mut(),
                    cache_stats,
                    retain_lines,
                );
                subdirs.push(child_node);
            } else if ft.is_file() {
                let Ok(meta) = entry.metadata() else { continue };
                let (mtime_secs, mtime_nanos) = meta
                    .modified()
                    .ok()
                    .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
                    .map(|d| (d.as_secs(), d.subsec_nanos()))
                    .unwrap_or((0, 0));
                let size_bytes = meta.len();
                let rel_path = full_path
                    .strip_prefix(vault_canon)
                    .map(|p| p.to_string_lossy().replace('\\', "/"))
                    .unwrap_or_default();
                let ext = full_path
                    .extension()
                    .map(|s| s.to_string_lossy().to_string())
                    .unwrap_or_default();
                let stem = full_path
                    .file_stem()
                    .map(|s| s.to_string_lossy().to_string())
                    .unwrap_or_else(|| fname.clone());
                let (cat_enum, lang) = classify_extension(&ext);
                let cat_str = match cat_enum {
                    FileCategory::Markdown => "markdown",
                    FileCategory::Code => "code",
                    FileCategory::Image => "image",
                    FileCategory::External => "external",
                };
                let folder = Path::new(&rel_path)
                    .parent()
                    .map(|p| p.to_string_lossy().replace('\\', "/"))
                    .unwrap_or_default();
                let top_folder = rel_path
                    .split('/')
                    .next()
                    .filter(|_| rel_path.contains('/'))
                    .unwrap_or("")
                    .to_string();

                flat_files.push(FlatFileEntry {
                    name: fname.clone(),
                    stem: stem.clone(),
                    rel_path: rel_path.clone(),
                    folder: folder.clone(),
                    top_folder: top_folder.clone(),
                    category: cat_str.to_string(),
                    language: lang.to_string(),
                    ext: ext.clone(),
                    mtime_secs,
                    size_bytes,
                });

                if cat_enum == FileCategory::Markdown && size_bytes <= 4 * 1024 * 1024 {
                    if !retain_lines {
                        if let Some(cached) = prev_cache.and_then(|m| m.get(&rel_path)) {
                            if cached.mtime_secs == mtime_secs
                                && cached.mtime_nanos == mtime_nanos
                                && cached.size_bytes == size_bytes
                            {
                                cache_stats.0 += 1;
                                let mut reused = cached.summary.clone();
                                reused.rel_path = rel_path.clone();
                                reused.mtime_secs = mtime_secs;
                                if let Some(nc) = next_cache.as_deref_mut() {
                                    nc.insert(
                                        rel_path.clone(),
                                        CachedMarkdownEntry {
                                            mtime_secs,
                                            mtime_nanos,
                                            size_bytes,
                                            summary: reused.clone(),
                                        },
                                    );
                                }
                                note_slots.push(Some(reused));
                                files.push(TreeNode {
                                    name: fname,
                                    rel_path,
                                    is_dir: false,
                                    category: cat_str.to_string(),
                                    ext,
                                    mtime_secs,
                                    size_bytes,
                                    note_count: 1,
                                    prefix_code: String::new(),
                                    color_hex: String::new(),
                                    text_color_hex: String::new(),
                                    icon_name: String::new(),
                                    children: Vec::new(),
                                });
                                continue;
                            }
                        }
                    }

                    let slot_idx = note_slots.len();
                    note_slots.push(None);
                    uncached_jobs.push(UncachedMarkdownJob {
                        slot_idx,
                        full_path,
                        rel_path: rel_path.clone(),
                        stem,
                        folder,
                        top_folder,
                        mtime_secs,
                        mtime_nanos,
                        size_bytes,
                    });
                }

                files.push(TreeNode {
                    name: fname,
                    rel_path,
                    is_dir: false,
                    category: cat_str.to_string(),
                    ext,
                    mtime_secs,
                    size_bytes,
                    note_count: usize::from(cat_enum == FileCategory::Markdown),
                    prefix_code: String::new(),
                    color_hex: String::new(),
                    text_color_hex: String::new(),
                    icon_name: String::new(),
                    children: Vec::new(),
                });
            }
        }
    }

    let mut children = subdirs;
    children.extend(files);
    let note_count: usize = children.iter().map(|c| c.note_count).sum();
    let (prefix_code, color_hex, text_color_hex, default_icon) = folder_prefix_style(&rel_dir, &dir_name);

    TreeNode {
        name: dir_name,
        rel_path: rel_dir,
        is_dir: true,
        category: "folder".to_string(),
        ext: String::new(),
        mtime_secs: 0,
        size_bytes: 0,
        note_count,
        prefix_code,
        color_hex,
        text_color_hex,
        icon_name: default_icon,
        children,
    }
}

fn scan_directory_recursive_with_cache(
    vault_canon: &Path,
    dir: &Path,
    flat_files: &mut Vec<FlatFileEntry>,
    notes: &mut Vec<ParsedNoteSummary>,
    prev_cache: Option<&HashMap<String, CachedMarkdownEntry>>,
    mut next_cache: Option<&mut BTreeMap<String, CachedMarkdownEntry>>,
    cache_stats: &mut (usize, usize),
    retain_lines: bool,
) -> TreeNode {
    let mut note_slots: Vec<Option<ParsedNoteSummary>> = Vec::new();
    let mut uncached_jobs: Vec<UncachedMarkdownJob> = Vec::new();
    let tree = walk_directory_collect_jobs(
        vault_canon,
        dir,
        flat_files,
        &mut note_slots,
        &mut uncached_jobs,
        prev_cache,
        next_cache.as_deref_mut(),
        cache_stats,
        retain_lines,
    );

    if !uncached_jobs.is_empty() {
        let worker_count = std::thread::available_parallelism()
            .map(|n| n.get().clamp(1, 8))
            .unwrap_or(4);
        let parsed_results: Vec<Option<ParsedNoteSummary>> = if uncached_jobs.len() < 8 || worker_count <= 1 {
            uncached_jobs
                .iter()
                .map(|job| {
                    parse_markdown_note_file(
                        &job.full_path,
                        &job.rel_path,
                        &job.stem,
                        &job.folder,
                        &job.top_folder,
                        job.mtime_secs,
                        retain_lines,
                    )
                })
                .collect()
        } else {
            let chunk_size = uncached_jobs.len().div_ceil(worker_count);
            std::thread::scope(|s| {
                let handles: Vec<_> = uncached_jobs
                    .chunks(chunk_size)
                    .map(|chunk| {
                        s.spawn(move || {
                            chunk
                                .iter()
                                .map(|job| {
                                    parse_markdown_note_file(
                                        &job.full_path,
                                        &job.rel_path,
                                        &job.stem,
                                        &job.folder,
                                        &job.top_folder,
                                        job.mtime_secs,
                                        retain_lines,
                                    )
                                })
                                .collect::<Vec<_>>()
                        })
                    })
                    .collect();
                let mut merged = Vec::with_capacity(uncached_jobs.len());
                for h in handles {
                    if let Ok(part) = h.join() {
                        merged.extend(part);
                    }
                }
                merged
            })
        };

        for (job, parsed_opt) in uncached_jobs.into_iter().zip(parsed_results.into_iter()) {
            if let Some(summary) = parsed_opt {
                cache_stats.1 += 1;
                if let Some(nc) = next_cache.as_deref_mut() {
                    let mut cached_summary = summary.clone();
                    cached_summary.lines.clear();
                    nc.insert(
                        job.rel_path,
                        CachedMarkdownEntry {
                            mtime_secs: job.mtime_secs,
                            mtime_nanos: job.mtime_nanos,
                            size_bytes: job.size_bytes,
                            summary: cached_summary,
                        },
                    );
                }
                note_slots[job.slot_idx] = Some(summary);
            }
        }
    }

    notes.reserve(note_slots.len());
    for slot in note_slots.into_iter().flatten() {
        notes.push(slot);
    }
    tree
}

pub fn folder_prefix_style(rel_path: &str, name: &str) -> (String, String, String, String) {
    // Inherit the 2-digit prefix from the top-level folder segment (e.g. "00_Capture/01_Journal" -> "00", "20_Personal_Life/23_Places" -> "20")
    let top_seg = rel_path.split('/').next().unwrap_or(name);
    let prefix = if top_seg.len() >= 2 && top_seg.as_bytes()[0].is_ascii_digit() && top_seg.as_bytes()[1].is_ascii_digit() {
        &top_seg[..2]
    } else if name.len() >= 2 && name.as_bytes()[0].is_ascii_digit() && name.as_bytes()[1].is_ascii_digit() {
        &name[..2]
    } else {
        ""
    };
    // Carbon Cyan palette from .obsidian/snippets/01_Core.css & 99_Alis_Theme.css
    let (bg, fg, def_icon) = match prefix {
        "00" => ("#82c2cf", "#081114", "edit_note"),
        "01" | "02" | "03" | "04" | "05" | "06" | "07" | "08" | "09" => ("#82c2cf", "#081114", "folder"),
        "10" | "11" | "12" | "13" | "14" | "15" | "16" | "17" | "18" | "19" => ("#7bb5c1", "#081114", "database"),
        "20" | "21" | "22" | "23" | "24" | "25" | "26" | "27" | "28" | "29" => ("#73a7b3", "#0b1417", "menu_book"),
        "30" | "31" | "32" | "33" | "34" | "35" | "36" | "37" | "38" | "39" => ("#6c9da8", "#0b1417", "folder"),
        "40" | "41" | "42" | "43" | "44" | "45" | "46" | "47" | "48" | "49" => ("#638d97", "#0d171a", "auto_stories"),
        "50" | "51" | "52" | "53" | "54" | "55" | "56" | "57" | "58" | "59" => ("#577980", "#e1e2e8", "folder"),
        "60" | "61" | "62" | "63" | "64" | "65" | "66" | "67" | "68" | "69" => ("#516f75", "#e1e2e8", "local_library"),
        "70" | "71" | "72" | "73" | "74" | "75" | "76" | "77" | "78" | "79" => ("#43595e", "#e1e2e8", "architecture"),
        "80" | "81" | "82" | "83" | "84" | "85" | "86" | "87" | "88" | "89" => ("#344145", "#e1e2e8", "folder"),
        "90" | "91" | "92" | "93" | "94" | "95" | "96" | "97" | "98" => ("#3d484b", "#e1e2e8", "settings"),
        "99" => ("#353d3f", "#e1e2e8", "inventory_2"),
        _ => ("", "#d6dce2", "folder"),
    };
    (prefix.to_string(), bg.to_string(), fg.to_string(), def_icon.to_string())
}

fn map_lucide_icon_to_material(lucide_id: &str) -> &'static str {
    match lucide_id.trim() {
        "LiNotebookPen" | "LiFilePen" => "edit_note",
        "LiInbox" => "inbox",
        "LiHeart" => "favorite",
        "LiDatabase" => "database",
        "LiNotebookText" => "menu_book",
        "LiBookText" | "LiBookOpen" | "LiBook" => "auto_stories",
        "LiLibraryBig" | "LiLibrary" => "local_library",
        "LiPencilRuler" | "LiCompass" => "architecture",
        "LiSettings" | "LiSliders" | "LiWrench" => "settings",
        "LiArchive" | "LiPackage" => "inventory_2",
        "LiCalendar" | "LiCalendarDays" | "LiCalendarCheck" => "calendar_month",
        "LiBrain" | "LiNetwork" | "LiWorkflow" => "hub",
        "LiScissors" | "LiBookmark" | "LiPaperclip" => "bookmark",
        "LiHeartPulse" | "LiActivity" | "LiDumbbell" => "fitness_center",
        "LiWallet" | "LiCoins" | "LiDollarSign" | "LiCreditCard" | "LiReceipt" => "account_balance_wallet",
        "LiMapPin" | "LiGlobe" | "LiMap" | "LiPlane" => "place",
        "LiFilm" | "LiClapperboard" | "LiTv" | "LiVideo" => "movie",
        "LiGamepad2" | "LiGamepad" | "LiJoystick" | "LiTrophy" => "sports_esports",
        "LiUtensils" | "LiCoffee" | "LiChefHat" | "LiWine" => "restaurant",
        "LiGraduationCap" | "LiSchool" => "school",
        "LiCode" | "LiTerminal" | "LiFileCode" => "terminal",
        "LiShield" | "LiLock" => "security",
        "LiHome" | "LiLayoutDashboard" => "home",
        "LiImage" | "LiImages" => "image",
        _ => "folder",
    }
}

fn apply_vault_folder_icons_recursive(node: &mut TreeNode, icon_map: &HashMap<String, String>) {
    if node.is_dir && !node.rel_path.is_empty() {
        if let Some(lucide) = icon_map.get(&node.rel_path) {
            let mapped = map_lucide_icon_to_material(lucide);
            if mapped != "folder" || node.icon_name.is_empty() {
                node.icon_name = mapped.to_string();
            }
        }
    }
    for child in &mut node.children {
        if child.is_dir {
            apply_vault_folder_icons_recursive(child, icon_map);
        }
    }
}

fn read_vault_folder_icons(vault_canon: &Path) -> HashMap<String, String> {
    let mut out = HashMap::new();
    let path = vault_canon.join(".obsidian/plugins/obsidian-icon-folder/data.json");
    let Ok(raw) = fs::read_to_string(&path) else {
        return out;
    };
    let Ok(val) = serde_json::from_str::<Value>(&raw) else {
        return out;
    };
    if let Some(obj) = val.as_object() {
        for (k, v) in obj {
            if k == "settings" {
                continue;
            }
            if let Some(icon_str) = v.as_str() {
                out.insert(k.trim_matches('/').to_string(), icon_str.to_string());
            } else if let Some(icon_str) = v.get("iconName").and_then(|x| x.as_str()) {
                out.insert(k.trim_matches('/').to_string(), icon_str.to_string());
            }
        }
    }
    out
}

fn build_note_lookup(notes: &[ParsedNoteSummary]) -> HashMap<String, usize> {
    let mut map = HashMap::new();
    for (idx, note) in notes.iter().enumerate() {
        map.insert(note.rel_path.to_ascii_lowercase(), idx);
        let without_ext = note.rel_path.trim_end_matches(".md").to_ascii_lowercase();
        map.insert(without_ext, idx);
        map.entry(note.stem.to_ascii_lowercase()).or_insert(idx);
        map.entry(note.title.to_ascii_lowercase()).or_insert(idx);
        for alias in &note.aliases {
            map.entry(alias.to_ascii_lowercase()).or_insert(idx);
        }
    }
    map
}

fn strip_wikilink_brackets(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    let chars: Vec<char> = raw.chars().collect();
    let n = chars.len();
    let mut i = 0;
    while i < n {
        if i + 3 < n && chars[i] == '[' && chars[i + 1] == '[' {
            let mut j = i + 2;
            while j + 1 < n && !(chars[j] == ']' && chars[j + 1] == ']') {
                j += 1;
            }
            if j + 1 < n {
                let inner: String = chars[i + 2..j].iter().collect();
                let label = match inner.split_once('|') {
                    Some((_, a)) if !a.trim().is_empty() => a.trim(),
                    _ => inner.trim(),
                };
                out.push_str(label);
                i = j + 2;
                continue;
            }
        }
        out.push(chars[i]);
        i += 1;
    }
    out
}

struct AssetLookupIndex {
    by_rel_lower: HashMap<String, (usize, String)>,
    by_name_lower: HashMap<String, (usize, String)>,
    by_stem_lower: HashMap<String, (usize, String)>,
}

impl AssetLookupIndex {
    fn from_flat_files(flat_files: &[FlatFileEntry]) -> Self {
        let cap = flat_files.len();
        let mut by_rel_lower = HashMap::with_capacity(cap);
        let mut by_name_lower = HashMap::with_capacity(cap);
        let mut by_stem_lower = HashMap::with_capacity(cap);
        for (idx, entry) in flat_files.iter().enumerate() {
            by_rel_lower
                .entry(entry.rel_path.to_ascii_lowercase())
                .or_insert_with(|| (idx, entry.rel_path.clone()));
            by_name_lower
                .entry(entry.name.to_ascii_lowercase())
                .or_insert_with(|| (idx, entry.rel_path.clone()));
            by_stem_lower
                .entry(entry.stem.to_ascii_lowercase())
                .or_insert_with(|| (idx, entry.rel_path.clone()));
        }
        Self {
            by_rel_lower,
            by_name_lower,
            by_stem_lower,
        }
    }
}

fn resolve_vault_asset_url_with_index(
    vault_canon: &Path,
    raw_val: &str,
    asset_index: &AssetLookupIndex,
) -> String {
    let trimmed = raw_val
        .trim()
        .trim_matches('"')
        .trim_matches('\'')
        .trim();
    if trimmed.is_empty() {
        return String::new();
    }
    if trimmed.starts_with("http://") || trimmed.starts_with("https://") || trimmed.starts_with("file://") {
        return trimmed.to_string();
    }
    let no_bang = trimmed.strip_prefix('!').unwrap_or(trimmed).trim();
    let inner = no_bang
        .strip_prefix("[[")
        .and_then(|s| s.strip_suffix("]]"))
        .unwrap_or(no_bang)
        .trim();
    let base_target = match inner.split_once('|') {
        Some((t, _)) => t.trim(),
        None => inner,
    };
    if base_target.is_empty() {
        return String::new();
    }
    if base_target.starts_with("http://") || base_target.starts_with("https://") || base_target.starts_with("file://") {
        return base_target.to_string();
    }
    let clean_rel = base_target.trim_start_matches('/');
    let direct_candidate = vault_canon.join(clean_rel);
    if direct_candidate.is_file() {
        return format!("file://{}", direct_candidate.to_string_lossy());
    }
    let attach_candidate = vault_canon.join("90_System/95_Attachments").join(clean_rel);
    if attach_candidate.is_file() {
        return format!("file://{}", attach_candidate.to_string_lossy());
    }
    let target_lower = clean_rel.to_ascii_lowercase();
    let target_fname = clean_rel.rsplit('/').next().unwrap_or(clean_rel).to_ascii_lowercase();
    let mut best: Option<&(usize, String)> = None;
    for cand in [
        asset_index.by_rel_lower.get(&target_lower),
        asset_index.by_name_lower.get(&target_fname),
        asset_index.by_stem_lower.get(&target_fname),
    ]
    .into_iter()
    .flatten()
    {
        if best.is_none_or(|prev| cand.0 < prev.0) {
            best = Some(cand);
        }
    }
    if let Some((_, rel_path)) = best {
        let resolved = vault_canon.join(rel_path);
        if resolved.is_file() {
            return format!("file://{}", resolved.to_string_lossy());
        }
    }
    String::new()
}

fn onion_category_name(code: &str) -> &'static str {
    match code.trim().to_ascii_uppercase().as_str() {
        "SRCH" => "Search Engines",
        "FOR" | "FORUMS" => "Forums & Communities",
        "SERV" => "Onion Services",
        "NEWS" => "News & Media",
        "MEDIA" => "Media & Libraries",
        "MAIL" => "Email & Messaging",
        "MKT" | "SHOP" => "Markets & Directories",
        "CRYPTO" => "Cryptocurrency",
        "OSINT" => "OSINT & Intelligence",
        "SEC" => "Security & Privacy",
        "LIB" => "Libraries & Archives",
        "TECH" => "Tech & Software",
        "UPLOAD" => "File Sharing",
        "OTH" | "MISC" => "Miscellaneous",
        _ => "Onion Directory",
    }
}

fn classify_note_kind(
    rel_path: &str,
    stem: &str,
    title: &str,
    frontmatter: &BTreeMap<String, String>,
    tags: &[String],
) -> &'static str {
    let lower_path = rel_path.to_ascii_lowercase();
    let cats_raw = frontmatter.get("categories").map(|s| s.as_str()).unwrap_or("");
    let type_raw = frontmatter.get("type").cloned().unwrap_or_default().to_ascii_lowercase();
    let record_type_raw = frontmatter
        .get("recordtype")
        .or_else(|| frontmatter.get("record_type"))
        .cloned()
        .unwrap_or_default()
        .to_ascii_lowercase();
    let css_raw = frontmatter
        .get("cssclasses")
        .or_else(|| frontmatter.get("cssclass"))
        .cloned()
        .unwrap_or_default()
        .to_ascii_lowercase();
    let has_tag = |name: &str| tags.iter().any(|t| t.eq_ignore_ascii_case(name));
    let is_zettel_stem = stem.len() >= 14
        && stem.as_bytes()[..12].iter().all(|b| b.is_ascii_digit())
        && stem[12..].contains(" - ");
    let is_zettel_type = type_raw
        .split(',')
        .map(|s| s.trim())
        .any(|s| matches!(s, "permanent" | "literature" | "fleeting"));

    if lower_path.contains("91_templates")
        || lower_path.contains("/templates/")
        || title.contains("<%")
    {
        "template"
    } else if lower_path.ends_with("homepage.md") || stem.eq_ignore_ascii_case("Homepage") {
        "homepage"
    } else if lower_path == "90_system/93_configuration/settings.md"
        || lower_path.ends_with("/93_configuration/settings.md")
    {
        "settings"
    } else if lower_path.contains("25_media_tracker/movies")
        || lower_path.contains("/movies/")
        || cats_raw.contains("Movies")
        || type_raw == "movie"
        || has_tag("movie")
        || has_tag("movies")
    {
        "movie"
    } else if lower_path.contains("25_media_tracker/tv_series")
        || lower_path.contains("/tv_series/")
        || lower_path.contains("/tv-series/")
        || cats_raw.contains("TV Series")
        || type_raw == "tv"
        || type_raw == "series"
        || has_tag("tv-series")
    {
        "tvseries"
    } else if lower_path.contains("27_game_tracker/games")
        || lower_path.contains("/games/")
        || has_tag("Game")
        || has_tag("games")
        || cats_raw.contains("Games")
        || type_raw == "game"
    {
        "game"
    } else if lower_path.contains("24_book_tracker")
        || lower_path.contains("/books/")
        || cats_raw.contains("Books")
        || has_tag("book")
        || has_tag("books")
        || type_raw == "book"
    {
        "book"
    } else if lower_path.contains("26_food_&_drinks/recipes")
        || lower_path.contains("/recipes/")
        || cats_raw.contains("Recipes")
        || has_tag("recipe")
        || has_tag("recipes")
        || type_raw == "recipe"
    {
        "recipe"
    } else if lower_path.contains("23_places")
        || lower_path.contains("26_food_&_drinks/restaurants")
        || lower_path.contains("26_food_&_drinks/cafes")
        || lower_path.contains("26_food_&_drinks/bars")
        || has_tag("place")
        || type_raw == "place"
        || frontmatter.contains_key("place_type")
    {
        "place"
    } else if lower_path.contains("22_finance/reports")
        || cats_raw.contains("Finance Report")
        || record_type_raw.starts_with("finance")
        || has_tag("finance-report")
    {
        "finance"
    } else if lower_path.contains("33_bodybuilding/gym_n_calisthenics_exercises")
        || lower_path.contains("21_health_&_fitness/exercise_library")
        || lower_path.contains("/exercise_library/")
        || cats_raw.contains("Exercises")
        || frontmatter.contains_key("primarymuscles")
        || has_tag("exercise")
    {
        "exercise"
    } else if lower_path.contains("09_clippings")
        || lower_path.contains("04_clippings")
        || lower_path.contains("/clippings/")
        || cats_raw.contains("Clippings")
        || has_tag("clipping")
        || has_tag("clippings")
    {
        "clipping"
    } else if lower_path.contains("78_onion_sites")
        || lower_path.contains("onion")
        || has_tag("OnionSite")
        || type_raw == "website"
    {
        "website"
    } else if lower_path.contains("02_cornell")
        || lower_path.contains("cornell")
        || type_raw.eq_ignore_ascii_case("cornell-note")
        || has_tag("cornell-notes")
        || has_tag("cornell")
        || css_raw.contains("cornell")
    {
        "cornell"
    } else if lower_path.contains("29_contact")
        || has_tag("contact")
        || frontmatter.contains_key("full name")
    {
        "contact"
    } else if (frontmatter.contains_key("session")
        && (frontmatter.contains_key("course") || frontmatter.contains_key("topic")))
        || has_tag("teaching-session")
    {
        "teaching"
    } else if has_tag("flashcards/english/vocabulary")
        || has_tag("review/english/vocabulary")
        || (frontmatter.contains_key("unit")
            && (frontmatter.contains_key("source") || type_raw.eq_ignore_ascii_case("literature")))
    {
        "vocabulary"
    } else if lower_path.contains("03_zettelkasten")
        || lower_path.contains("zettelkasten")
        || lower_path.contains("zettlekasten")
        || has_tag("zettelkasten")
        || is_zettel_stem
        || (is_zettel_type && !lower_path.contains("24_book_tracker"))
    {
        "zettelkasten"
    } else if detect_journal_date_from_path(rel_path, stem).is_some()
        || lower_path.contains("01_journal")
        || frontmatter
            .get("journal")
            .map(|s| s.eq_ignore_ascii_case("Daily Notes"))
            .unwrap_or(false)
        || has_tag("daily-notes")
    {
        "journal"
    } else {
        "standard"
    }
}

fn build_note_dossier_with_index(
    vault_canon: &Path,
    note_kind: &str,
    rel_path: &str,
    title: &str,
    frontmatter: &BTreeMap<String, String>,
    snippet: &str,
    asset_index: &AssetLookupIndex,
) -> Value {
    let lower_path = rel_path.to_ascii_lowercase();
    let get_clean = |k: &str| -> String {
        frontmatter
            .get(k)
            .map(|v| strip_wikilink_brackets(v).trim().to_string())
            .unwrap_or_default()
    };
    let get_first_non_empty = |keys: &[&str]| -> String {
        for &k in keys {
            let v = get_clean(k);
            if !v.is_empty() {
                return v;
            }
        }
        String::new()
    };

    let poster_raw = frontmatter
        .get("poster")
        .or_else(|| frontmatter.get("cover"))
        .or_else(|| frontmatter.get("preview"))
        .or_else(|| frontmatter.get("image"))
        .or_else(|| frontmatter.get("thumbnail"))
        .map(|s| s.as_str())
        .unwrap_or("");
    let backdrop_raw = frontmatter
        .get("backdrop")
        .or_else(|| frontmatter.get("banner"))
        .map(|s| s.as_str())
        .unwrap_or("");
    let barcode_raw = frontmatter.get("barcode").map(|s| s.as_str()).unwrap_or("");
    let featured_raw = frontmatter
        .get("featured_image")
        .or_else(|| frontmatter.get("animation"))
        .or_else(|| frontmatter.get("images"))
        .or_else(|| frontmatter.get("photo"))
        .or_else(|| frontmatter.get("gif"))
        .map(|s| s.as_str())
        .unwrap_or("");

    let poster_url = resolve_vault_asset_url_with_index(vault_canon, poster_raw, asset_index);
    let backdrop_url = resolve_vault_asset_url_with_index(vault_canon, backdrop_raw, asset_index);
    let barcode_url = resolve_vault_asset_url_with_index(vault_canon, barcode_raw, asset_index);
    let featured_url = resolve_vault_asset_url_with_index(vault_canon, featured_raw, asset_index);

    let parent_code = Path::new(rel_path)
        .parent()
        .and_then(|p| p.file_name())
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default();
    let place_type_val = {
        let pt = get_clean("place_type");
        if !pt.is_empty() {
            pt
        } else if lower_path.contains("restaurants") {
            "restaurant".to_string()
        } else if lower_path.contains("cafes") {
            "cafe".to_string()
        } else if lower_path.contains("bars") {
            "bar".to_string()
        } else if note_kind == "place" {
            "tourist".to_string()
        } else {
            String::new()
        }
    };
    let cat_code = if note_kind == "website" {
        let fm_cat = get_clean("category");
        if !fm_cat.is_empty() {
            fm_cat.to_ascii_uppercase()
        } else {
            parent_code.to_ascii_uppercase()
        }
    } else if !place_type_val.is_empty() {
        place_type_val.clone()
    } else {
        get_first_non_empty(&["recipe_category", "category", "place_type", "type"])
    };
    let cat_name = if note_kind == "website" {
        onion_category_name(&cat_code).to_string()
    } else {
        get_first_non_empty(&["recipe_category", "categories", "place_type", "category"])
    };

    let coords_str = get_clean("coordinates");
    let mut lat = 0.0f64;
    let mut lon = 0.0f64;
    let mut has_coords = false;
    if let Some((la_s, lo_s)) = coords_str.split_once(',') {
        if let (Ok(la), Ok(lo)) = (la_s.trim().parse::<f64>(), lo_s.trim().parse::<f64>()) {
            lat = la;
            lon = lo;
            has_coords = true;
        }
    } else {
        let la_s = get_first_non_empty(&["latitude", "lat"]);
        let lo_s = get_first_non_empty(&["longitude", "lon", "lng"]);
        if let (Ok(la), Ok(lo)) = (la_s.parse::<f64>(), lo_s.parse::<f64>()) {
            lat = la;
            lon = lo;
            has_coords = true;
        }
    }

    let watched_bool = frontmatter
        .get("watched")
        .map(|v| v.eq_ignore_ascii_case("true") || v == "1")
        .unwrap_or(false);
    let fav_bool = frontmatter
        .get("favorite")
        .map(|v| v.eq_ignore_ascii_case("true") || v == "1")
        .unwrap_or(false);
    let visited_bool = frontmatter
        .get("visited")
        .map(|v| v.eq_ignore_ascii_case("true") || v == "1")
        .unwrap_or(false);
    let want_to_visit_bool = frontmatter
        .get("want_to_visit")
        .map(|v| v.eq_ignore_ascii_case("true") || v == "1")
        .unwrap_or(false);
    let bookmarked_bool = frontmatter
        .get("bookmarked")
        .map(|v| v.eq_ignore_ascii_case("true") || v == "1")
        .unwrap_or(false);

    let raw_rating = get_clean("rating");
    let normalized_rating = if raw_rating.contains('⭐') || raw_rating.contains('★') {
        let star_count = raw_rating.chars().filter(|&c| c == '⭐' || c == '★').count();
        format!("{}", star_count * 2)
    } else {
        raw_rating.clone()
    };

    let score_val = {
        let mut s = get_first_non_empty(&["scoreimdb", "onlinerating", "rating", "metacritic"]);
        if s.contains('⭐') || s.contains('★') {
            s = normalized_rating.clone();
        }
        if s == "0" {
            s.clear();
        }
        s
    };
    let cast_val = get_first_non_empty(&["cast", "actors"]);
    let year_val = {
        let y = get_first_non_empty(&["year", "release_year", "publish_year"]);
        if !y.is_empty() {
            y
        } else {
            let d = get_first_non_empty(&["releasedate", "published", "publish_date", "created"]);
            if d.len() >= 4 && d.as_bytes()[..4].iter().all(|b| b.is_ascii_digit()) {
                d[..4].to_string()
            } else {
                String::new()
            }
        }
    };
    let location_val = get_first_non_empty(&["location", "address", "city", "region", "country"]);
    let plot_val = {
        let p = get_first_non_empty(&["plot", "description", "summary", "excerpt"]);
        if !p.is_empty() {
            p
        } else if !snippet.is_empty() {
            snippet.to_string()
        } else {
            location_val.clone()
        }
    };

    let mut ingredients_val: Vec<String> = frontmatter
        .get("ingredients")
        .map(|raw| {
            raw.split(|c| c == ',' || c == '\n')
                .map(|s| strip_wikilink_brackets(s).trim().trim_start_matches('-').trim().to_string())
                .filter(|s| !s.is_empty())
                .collect()
        })
        .unwrap_or_default();

    let zettel_id_val = {
        let fm_id = get_clean("id");
        if !fm_id.is_empty() {
            fm_id
        } else {
            let stem_only = Path::new(rel_path)
                .file_stem()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or_default();
            let digits: String = stem_only.chars().take_while(|c| c.is_ascii_digit()).collect();
            if digits.len() >= 8 { digits } else { String::new() }
        }
    };
    let zettel_type_val = {
        let raw_t = get_first_non_empty(&["type", "zettel_type", "note_type"]);
        let first_t = raw_t.split(',').next().unwrap_or("").trim().to_string();
        if !first_t.is_empty() { first_t } else { "Atomic".to_string() }
    };
    let fin_amount_val = get_first_non_empty(&["baseamount", "amount", "openingbalance", "balance"])
        .replace(',', "")
        .parse::<f64>()
        .unwrap_or(0.0);
    let fin_tx_type = get_first_non_empty(&["transactiontype", "type"]);
    let fin_record_kind = if lower_path.contains("/transactions/") {
        "transaction"
    } else if lower_path.contains("/accounts/") {
        "account"
    } else if lower_path.contains("/subscription/") {
        "subscription"
    } else {
        "report"
    };
    if ingredients_val.is_empty() && note_kind == "recipe" {
        if let Ok(raw_md) = fs::read_to_string(vault_canon.join(rel_path)) {
            let mut in_ing = false;
            for line in raw_md.lines() {
                let t = line.trim();
                if t.starts_with('#') {
                    let h = t.trim_start_matches('#').trim().to_ascii_lowercase();
                    in_ing = h.contains("ingredient") || h.contains("nguyên liệu");
                    continue;
                }
                if in_ing {
                    if let Some(rest) = t.strip_prefix("- [ ] ").or_else(|| t.strip_prefix("- [x] ")).or_else(|| t.strip_prefix("- [X] ")).or_else(|| t.strip_prefix("- ")).or_else(|| t.strip_prefix("* ")) {
                        let cleaned = strip_wikilink_brackets(rest).trim().to_string();
                        if !cleaned.is_empty() {
                            ingredients_val.push(cleaned);
                            if ingredients_val.len() >= 18 {
                                break;
                            }
                        }
                    }
                }
            }
        }
    }

    let dossier = json!({
        "kind": note_kind,
        "title": title,
        "relPath": rel_path,
        "posterUrl": poster_url,
        "backdropUrl": backdrop_url,
        "barcodeUrl": barcode_url,
        "featuredImageUrl": featured_url,
        "imdbId": get_first_non_empty(&["imdbid", "imdb_id", "imdb"]),
        "tmdbId": get_first_non_empty(&["tmdbid", "tmdb_id", "tmdb"]),
        "year": year_val,
        "releaseDate": get_first_non_empty(&["releasedate", "release_date", "published"]),
        "ended": get_first_non_empty(&["ended", "last_aired"]),
        "airingStatus": get_first_non_empty(&["airing_status", "status"]),
        "score": score_val,
        "rating": normalized_rating,
        "ratingRaw": raw_rating,
        "onlineRating": get_first_non_empty(&["onlinerating", "scoreimdb"]),
        "metacritic": get_clean("metacritic"),
        "runtime": get_clean("runtime"),
        "status": get_first_non_empty(&["status", "airing_status", "read_status"]),
        "watched": watched_bool,
        "favorite": fav_bool,
        "visited": visited_bool,
        "wantToVisit": want_to_visit_bool,
        "bookmarked": bookmarked_bool,
        "plot": plot_val,
        "description": get_first_non_empty(&["recipe_description", "description", "summary", "plot"]),
        "director": get_first_non_empty(&["director", "directors"]),
        "cast": cast_val,
        "actors": cast_val,
        "writer": get_first_non_empty(&["writer", "writers"]),
        "creator": get_first_non_empty(&["creator", "creators"]),
        "networks": get_first_non_empty(&["networks", "network"]),
        "seasons": get_first_non_empty(&["total_seasons", "seasons"]),
        "episodes": get_first_non_empty(&["total_episodes", "episodes"]),
        "genre": get_first_non_empty(&["genre", "genres"]),
        "developer": get_first_non_empty(&["developer", "developers"]),
        "publisher": get_first_non_empty(&["publisher", "publishers"]),
        "hoursPlayed": get_first_non_empty(&["hours_played", "playtimehours", "playtime"]),
        "completion": get_first_non_empty(&["completion", "progress", "achievement_pct"]),
        "achievementsEarned": get_first_non_empty(&["achievements_earned", "achievementsunlocked", "achievements"]),
        "achievementsTotal": get_first_non_empty(&["achievements_total", "achievementstotal", "total_achievements"]),
        "platform": get_first_non_empty(&["platforms", "platform"]),
        "store": get_first_non_empty(&["store", "source", "recipe_provider"]),
        "steamId": get_first_non_empty(&["steamappid", "steam_id", "steamid", "appid"]),
        "rawgId": get_first_non_empty(&["rawgid", "rawg_id"]),
        "gogId": get_first_non_empty(&["gogid", "gog_id"]),
        "storeUrl": get_first_non_empty(&["storeurl", "store_url"]),
        "websiteUrl": get_first_non_empty(&["website", "website_url"]),
        "sourceUrl": get_first_non_empty(&["sourceurl", "source_url"]),
        "url": get_first_non_empty(&["url", "url_onion", "url_mirror", "website", "storeurl", "source_url", "source", "link"]),
        "language": get_clean("language"),
        "category": if !cat_name.is_empty() { cat_name.clone() } else { cat_code.clone() },
        "categoryCode": cat_code,
        "categoryName": cat_name,
        "placeType": place_type_val,
        "address": get_clean("address"),
        "city": get_clean("city"),
        "region": get_clean("region"),
        "country": get_clean("country"),
        "phone": get_clean("phone"),
        "fullName": get_first_non_empty(&["full name", "fullname", "name"]),
        "birthday": get_clean("birthday"),
        "company": get_clean("company"),
        "email": get_clean("email"),
        "openingHours": get_clean("opening_hours"),
        "lastVisited": get_clean("last_visited"),
        "priceRange": get_first_non_empty(&["price_level", "price_range", "price"]),
        "cuisine": get_clean("cuisine"),
        "tagline": get_clean("tagline"),
        "specialty": get_first_non_empty(&["specialty", "must_try", "signature_dish"]),
        "author": get_first_non_empty(&["author", "authors", "by"]),
        "pages": get_first_non_empty(&["totalpages", "pages", "total_pages"]),
        "currentPage": get_first_non_empty(&["currentpage", "current_page", "page_progress"]),
        "isbn": get_clean("isbn"),
        "startDate": get_first_non_empty(&["datestarted", "start_date", "started"]),
        "finishDate": get_first_non_empty(&["datefinished", "finish_date", "finished", "completed_date"]),
        "prepTime": get_first_non_empty(&["prep_time", "preptime"]),
        "cookTime": get_first_non_empty(&["cook_time", "cooktime"]),
        "totalTime": get_first_non_empty(&["total_time", "totaltime", "time"]),
        "servings": get_first_non_empty(&["servings", "yield"]),
        "calories": get_clean("calories"),
        "difficulty": get_clean("difficulty"),
        "ingredients": ingredients_val,
        "level": get_clean("level"),
        "force": get_clean("force"),
        "mechanic": get_clean("mechanic"),
        "muscleGroup": get_first_non_empty(&["primarymuscles", "muscle_group", "target_muscle", "primary_muscle", "muscle"]),
        "secondaryMuscles": get_first_non_empty(&["secondarymuscles", "secondary_muscles"]),
        "equipment": get_clean("equipment"),
        "exerciseType": get_first_non_empty(&["exercise_type", "mechanic", "force", "category"]),
        "domain": get_first_non_empty(&["domain", "site"]),
        "course": get_clean("course"),
        "session": get_clean("session"),
        "topic": get_clean("topic"),
        "time": get_clean("time"),
        "materials": get_clean("materials"),
        "prerequisites": get_clean("prerequisites"),
        "assignments": get_clean("assignments"),
        "unit": get_clean("unit"),
        "source": get_clean("source"),
        "zettelId": zettel_id_val,
        "zettelType": zettel_type_val,
        "amount": fin_amount_val,
        "currency": get_clean("currency"),
        "txType": fin_tx_type,
        "account": get_first_non_empty(&["account", "fromaccount"]),
        "merchant": get_clean("merchant"),
        "billingCycle": get_clean("billingcycle"),
        "recordKind": fin_record_kind,
        "date": get_first_non_empty(&["date", "created", "datecreated", "date_discovered", "published"]),
        "location": location_val,
        "coordinates": coords_str,
        "hasCoordinates": has_coords,
        "lat": lat,
        "lon": lon,
    });

    dossier
}

fn is_template_note_summary(note: &ParsedNoteSummary) -> bool {
    let lower = note.rel_path.to_ascii_lowercase();
    lower.contains("/91_templates/")
        || lower.starts_with("91_templates/")
        || lower.contains("/01_templates/")
        || lower.starts_with("01_templates/")
        || lower.contains("/templates/")
        || lower.starts_with("templates/")
        || lower.contains("/template_scripts/")
        || note.title.contains("<%")
        || note.stem.contains("<%")
        || note.has_templater_syntax
        || note.lines.iter().take(25).any(|l| l.contains("<%") && l.contains("%>"))
}

fn compute_vault_graph(notes: &[ParsedNoteSummary], _lookup: &HashMap<String, usize>) -> Value {
    struct GraphNodeSpec {
        id: String,
        title: String,
        rel_path: String,
        folder: String,
        top_folder: String,
        is_journal: bool,
        is_tag_node: bool,
        is_virtual: bool,
        tag_name: String,
        tags: Vec<String>,
    }

    let graph_notes: Vec<&ParsedNoteSummary> = notes
        .iter()
        .filter(|n| !is_template_note_summary(n))
        .collect();
    let real_n = graph_notes.len();

    let mut nodes: Vec<GraphNodeSpec> = Vec::with_capacity(real_n + 64);
    let mut graph_lookup: HashMap<String, usize> = HashMap::with_capacity(real_n * 3);
    for (idx, note) in graph_notes.iter().enumerate() {
        let rel_key = note.rel_path.trim().trim_end_matches(".md").to_ascii_lowercase();
        let stem_key = note.stem.trim().to_ascii_lowercase();
        let title_key = note.title.trim().to_ascii_lowercase();
        graph_lookup.insert(rel_key, idx);
        graph_lookup.entry(stem_key).or_insert(idx);
        if !title_key.is_empty() {
            graph_lookup.entry(title_key).or_insert(idx);
        }
        for alias in &note.aliases {
            let ak = alias.trim().to_ascii_lowercase();
            if !ak.is_empty() {
                graph_lookup.entry(ak).or_insert(idx);
            }
        }
        nodes.push(GraphNodeSpec {
            id: note.rel_path.clone(),
            title: note.title.clone(),
            rel_path: note.rel_path.clone(),
            folder: note.folder.clone(),
            top_folder: note.top_folder.clone(),
            is_journal: note.is_journal,
            is_tag_node: false,
            is_virtual: false,
            tag_name: String::new(),
            tags: note.tags.clone(),
        });
    }

    let mut edges_set: BTreeSet<(usize, usize)> = BTreeSet::new();
    let mut undirected_seen: HashSet<(usize, usize)> = HashSet::new();
    let mut in_deg = vec![0usize; real_n];
    let mut out_deg = vec![0usize; real_n];

    // 1. Direct [[wikilink]] connections between existing non-template notes
    let mut unresolved_targets: BTreeMap<String, (String, Vec<usize>)> = BTreeMap::new();
    for (src_idx, note) in graph_notes.iter().enumerate() {
        for (target_raw, _, _) in &note.outgoing_links {
            let trimmed_raw = target_raw.trim().trim_end_matches(".md");
            let key = trimmed_raw.to_ascii_lowercase();
            if key.is_empty() || key.contains("<%") {
                continue;
            }
            let resolved_idx = graph_lookup.get(&key).copied().or_else(|| {
                key.rsplit('/')
                    .next()
                    .and_then(|short| graph_lookup.get(short).copied())
            });
            if let Some(dst_idx) = resolved_idx {
                if src_idx != dst_idx && edges_set.insert((src_idx, dst_idx)) {
                    let pair = if src_idx < dst_idx { (src_idx, dst_idx) } else { (dst_idx, src_idx) };
                    undirected_seen.insert(pair);
                    out_deg[src_idx] += 1;
                    in_deg[dst_idx] += 1;
                }
            } else {
                let short_display = trimmed_raw.rsplit('/').next().unwrap_or(trimmed_raw).trim();
                let short_key = short_display.to_ascii_lowercase();
                if !short_key.is_empty() {
                    let entry = unresolved_targets
                        .entry(short_key)
                        .or_insert_with(|| (short_display.to_string(), Vec::new()));
                    if entry.1.last().copied() != Some(src_idx) && !entry.1.contains(&src_idx) {
                        entry.1.push(src_idx);
                    }
                }
            }
        }
    }

    // 2. Virtual Tag Hub Nodes (Obsidian `showTags: true` parity):
    // When >= 2 notes share a tag (e.g. `Books`), create a virtual tag hub node
    // (`#Books`) as the true cluster center instead of elevating an arbitrary member note.
    let mut tag_members: BTreeMap<String, (String, Vec<usize>)> = BTreeMap::new();
    for (idx, note) in graph_notes.iter().enumerate() {
        let mut seen_for_note: HashSet<String> = HashSet::new();
        for tag in &note.tags {
            let trimmed = tag.trim().trim_start_matches('#');
            let clean_key = trimmed.to_ascii_lowercase();
            if clean_key.is_empty() || clean_key.contains("<%") || !seen_for_note.insert(clean_key.clone()) {
                continue;
            }
            let entry = tag_members
                .entry(clean_key)
                .or_insert_with(|| (trimmed.to_string(), Vec::new()));
            entry.1.push(idx);
        }
    }

    // Assign each tagged note to its strongest shared tag hub (keeping clusters clean like Obsidian)
    let mut virtual_hub_index_by_key: HashMap<String, usize> = HashMap::new();
    let mut has_tag_hub = vec![false; real_n];
    for (idx, note) in graph_notes.iter().enumerate() {
        let mut best_key: Option<String> = None;
        let mut best_len = 1usize;
        for tag in &note.tags {
            let clean_key = tag.trim().trim_start_matches('#').to_ascii_lowercase();
            if let Some((_, members)) = tag_members.get(&clean_key) {
                if members.len() > best_len {
                    best_len = members.len();
                    best_key = Some(clean_key);
                }
            }
        }
        if let Some(chosen_key) = best_key {
            has_tag_hub[idx] = true;
            let hub_idx = if let Some(&existing) = graph_lookup.get(&chosen_key) {
                existing
            } else if let Some(&existing_v) = virtual_hub_index_by_key.get(&chosen_key) {
                existing_v
            } else {
                let (display_tag, members) = &tag_members[&chosen_key];
                // Derive top_folder from majority folder of its members
                let mut f_counts: HashMap<&str, usize> = HashMap::new();
                for &m in members {
                    *f_counts.entry(graph_notes[m].top_folder.as_str()).or_insert(0) += 1;
                }
                let dom_folder = f_counts
                    .into_iter()
                    .max_by_key(|&(_, c)| c)
                    .map(|(f, _)| f.to_string())
                    .unwrap_or_default();
                let new_idx = nodes.len();
                nodes.push(GraphNodeSpec {
                    id: format!("tag:{}", chosen_key),
                    title: format!("#{}", display_tag),
                    rel_path: String::new(),
                    folder: String::new(),
                    top_folder: dom_folder,
                    is_journal: false,
                    is_tag_node: true,
                    is_virtual: true,
                    tag_name: display_tag.clone(),
                    tags: vec![display_tag.clone()],
                });
                in_deg.push(0);
                out_deg.push(0);
                virtual_hub_index_by_key.insert(chosen_key.clone(), new_idx);
                new_idx
            };

            if hub_idx != idx {
                let pair = if hub_idx < idx { (hub_idx, idx) } else { (idx, hub_idx) };
                if undirected_seen.insert(pair) && edges_set.insert((hub_idx, idx)) {
                    out_deg[hub_idx] += 1;
                    in_deg[idx] += 1;
                }
            }
        }
    }

    // 3. Virtual Unresolved Link/Category Hub Nodes for untagged notes sharing >= 2 unresolved links
    // (e.g. `[[Movies]]`, `[[Books]]`, `[[Recipes]]` in frontmatter `categories:`)
    let mut best_unres_for_node: HashMap<usize, String> = HashMap::new();
    for (target_key, (_, members)) in &unresolved_targets {
        if members.len() < 2 {
            continue;
        }
        for &idx in members {
            if has_tag_hub[idx] {
                continue;
            }
            let replace = match best_unres_for_node.get(&idx) {
                None => true,
                Some(prev_key) => {
                    let prev_len = unresolved_targets.get(prev_key).map(|v| v.1.len()).unwrap_or(0);
                    members.len() > prev_len
                }
            };
            if replace {
                best_unres_for_node.insert(idx, target_key.clone());
            }
        }
    }
    let mut filtered_unres_groups: BTreeMap<String, Vec<usize>> = BTreeMap::new();
    for (idx, key) in best_unres_for_node {
        filtered_unres_groups.entry(key).or_default().push(idx);
    }
    for (target_key, members) in filtered_unres_groups {
        if members.len() < 2 {
            continue;
        }
        let hub_idx = if let Some(&existing_v) = virtual_hub_index_by_key.get(&target_key) {
            existing_v
        } else {
            let display = unresolved_targets
                .get(&target_key)
                .map(|(d, _)| d.clone())
                .unwrap_or_else(|| target_key.clone());
            let mut f_counts: HashMap<&str, usize> = HashMap::new();
            for &m in &members {
                *f_counts.entry(graph_notes[m].top_folder.as_str()).or_insert(0) += 1;
            }
            let dom_folder = f_counts
                .into_iter()
                .max_by_key(|&(_, c)| c)
                .map(|(f, _)| f.to_string())
                .unwrap_or_default();
            let new_idx = nodes.len();
            nodes.push(GraphNodeSpec {
                id: format!("virtual:{}", target_key),
                title: display.clone(),
                rel_path: String::new(),
                folder: String::new(),
                top_folder: dom_folder,
                is_journal: false,
                is_tag_node: true,
                is_virtual: true,
                tag_name: display,
                tags: Vec::new(),
            });
            in_deg.push(0);
            out_deg.push(0);
            virtual_hub_index_by_key.insert(target_key.clone(), new_idx);
            new_idx
        };
        for &m in &members {
            if m != hub_idx {
                let pair = if hub_idx < m { (hub_idx, m) } else { (m, hub_idx) };
                if undirected_seen.insert(pair) && edges_set.insert((hub_idx, m)) {
                    out_deg[hub_idx] += 1;
                    in_deg[m] += 1;
                }
            }
        }
    }

    let n = nodes.len();

    // Group notes by top_folder for metadata compatibility
    let mut groups: Vec<String> = nodes
        .iter()
        .map(|item| {
            if item.top_folder.is_empty() {
                "root".to_string()
            } else {
                item.top_folder.clone()
            }
        })
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect();
    if groups.is_empty() {
        groups.push("root".to_string());
    }

    // Build undirected adjacency list for connected-component layout & cluster coloring
    let mut adj: Vec<Vec<usize>> = vec![Vec::new(); n];
    for &(u, v) in &undirected_seen {
        adj[u].push(v);
        adj[v].push(u);
    }

    // Discover true connected components via BFS
    let mut visited = vec![false; n];
    let mut connected_comps: Vec<Vec<usize>> = Vec::new();
    let mut orphans: Vec<usize> = Vec::new();
    for start in 0..n {
        if visited[start] {
            continue;
        }
        let mut comp = Vec::new();
        let mut queue = std::collections::VecDeque::new();
        visited[start] = true;
        queue.push_back(start);
        while let Some(curr) = queue.pop_front() {
            comp.push(curr);
            for &nxt in &adj[curr] {
                if !visited[nxt] {
                    visited[nxt] = true;
                    queue.push_back(nxt);
                }
            }
        }
        if comp.len() >= 2 {
            connected_comps.push(comp);
        } else {
            orphans.push(start);
        }
    }
    connected_comps.sort_by(|a, b| b.len().cmp(&a.len()).then_with(|| a[0].cmp(&b[0])));

    let mut cluster_id_of = vec![-1i32; n];
    let mut is_orphan_of = vec![true; n];
    for (c_idx, comp) in connected_comps.iter().enumerate() {
        for &u in comp {
            cluster_id_of[u] = c_idx as i32;
            is_orphan_of[u] = false;
        }
    }

    let mut pos_x = vec![0.5f64; n];
    let mut pos_y = vec![0.5f64; n];
    let mut pos_z = vec![0.5f64; n];
    let golden = 2.39996322972865332f64;

    if n > 0 && n <= 12 {
        // Small vault layout: clean ring + gentle 3D helix
        for i in 0..n {
            if n == 1 {
                pos_x[i] = 0.5;
                pos_y[i] = 0.5;
                pos_z[i] = 0.5;
            } else {
                let angle = (i as f64 / n as f64) * std::f64::consts::TAU - std::f64::consts::FRAC_PI_2;
                pos_x[i] = 0.5 + 0.30 * angle.cos();
                pos_y[i] = 0.5 + 0.30 * angle.sin();
                pos_z[i] = 0.5 + 0.22 * (angle * 1.5).sin();
            }
        }
    } else if n > 12 {
        let mut layout_comps: Vec<Vec<usize>> = connected_comps.clone();
        // Arrange orphans into tidy outer peripheral mini-groups without creating false edges
        if !orphans.is_empty() {
            let mut orphan_buckets: BTreeMap<String, Vec<usize>> = BTreeMap::new();
            for idx in &orphans {
                orphan_buckets
                    .entry(nodes[*idx].top_folder.clone())
                    .or_default()
                    .push(*idx);
            }
            for (_, grp) in orphan_buckets {
                layout_comps.push(grp);
            }
        }

        let num_clusters = layout_comps.len();
        let mut cluster_radii = vec![0.02f64; num_clusters];
        let mut cluster_cx = vec![0.0f64; num_clusters];
        let mut cluster_cy = vec![0.0f64; num_clusters];
        let mut cluster_cz = vec![0.0f64; num_clusters];

        let preset_anchors: [(f64, f64, f64); 8] = [
            (0.02, 0.20, 0.08),
            (0.28, -0.18, -0.16),
            (-0.28, -0.14, 0.18),
            (-0.04, -0.34, -0.12),
            (-0.35, 0.15, -0.20),
            (0.41, 0.08, 0.22),
            (-0.22, 0.36, 0.14),
            (0.35, 0.32, -0.18),
        ];

        for (c_idx, comp) in layout_comps.iter().enumerate() {
            let m = comp.len() as f64;
            cluster_radii[c_idx] = if comp.len() == 1 {
                0.014
            } else {
                0.020 + 0.0074 * m.sqrt()
            };
            if c_idx < preset_anchors.len() {
                cluster_cx[c_idx] = preset_anchors[c_idx].0;
                cluster_cy[c_idx] = preset_anchors[c_idx].1;
                cluster_cz[c_idx] = preset_anchors[c_idx].2;
            } else {
                let k = (c_idx - preset_anchors.len()) as f64;
                let angle = k * golden - 0.8;
                let dist = 0.46 + ((c_idx % 3) as f64) * 0.045;
                cluster_cx[c_idx] = dist * angle.cos();
                cluster_cy[c_idx] = dist * angle.sin();
                cluster_cz[c_idx] = 0.26 * ((k * 1.13).sin());
            }
        }

        // Circle-packing relaxation between cluster centers
        for _iter in 0..56 {
            for a in 0..num_clusters {
                for b in (a + 1)..num_clusters {
                    let vx = cluster_cx[a] - cluster_cx[b];
                    let vy = cluster_cy[a] - cluster_cy[b];
                    let dist = (vx * vx + vy * vy).sqrt().max(0.0001);
                    let min_dist = cluster_radii[a] + cluster_radii[b] + 0.068;
                    if dist < min_dist {
                        let push = (min_dist - dist) * 0.55;
                        let nx = vx / dist;
                        let ny = vy / dist;
                        let wa = if a == 0 { 0.12 } else if a <= 2 { 0.30 } else { 0.75 };
                        let wb = 1.0 - wa;
                        cluster_cx[a] += nx * push * wa;
                        cluster_cy[a] += ny * push * wa;
                        cluster_cx[b] -= nx * push * wb;
                        cluster_cy[b] -= ny * push * wb;
                    }
                }
            }
            for c in 1..num_clusters {
                cluster_cx[c] *= 0.992;
                cluster_cy[c] *= 0.992;
            }
        }

        // Radial dandelion + 3D Fibonacci spherical distribution inside each cluster
        let mut local_x = vec![0.0f64; n];
        let mut local_y = vec![0.0f64; n];
        let mut local_z = vec![0.0f64; n];

        for (c_idx, comp) in layout_comps.iter().enumerate() {
            let radius = cluster_radii[c_idx];
            if comp.len() == 1 {
                local_x[comp[0]] = 0.0;
                local_y[comp[0]] = 0.0;
                local_z[comp[0]] = 0.0;
                continue;
            }
            // Prefer virtual tag hub node (or highest-degree node) as exact cluster center!
            let hub = *comp
                .iter()
                .max_by_key(|&&idx| {
                    let tag_bonus = if nodes[idx].is_tag_node { 10000 } else { 0 };
                    tag_bonus + adj[idx].len()
                })
                .unwrap_or(&comp[0]);
            local_x[hub] = 0.0;
            local_y[hub] = 0.0;
            local_z[hub] = 0.0;

            let mut satellites: Vec<usize> = comp.iter().copied().filter(|&idx| idx != hub).collect();
            satellites.sort_by(|&a, &b| {
                adj[b]
                    .len()
                    .cmp(&adj[a].len())
                    .then_with(|| nodes[a].folder.cmp(&nodes[b].folder))
                    .then_with(|| a.cmp(&b))
            });

            let sat_count = satellites.len().max(1) as f64;
            let r_min = (radius * 0.16).max(0.012);
            for (rank, &u) in satellites.iter().enumerate() {
                let k = rank as f64;
                let theta = k * golden + (c_idx as f64) * 0.61 + 0.065 * ((k * 1.37).cos());
                let u_norm = ((k + 0.65) / sat_count).sqrt();
                let jitter = 1.0 + 0.055 * ((k * 1.618).sin()) + 0.035 * ((k * 2.718).cos());
                let r = if adj[u].len() >= 4 {
                    radius * (0.26 + 0.36 * u_norm) * jitter
                } else {
                    (r_min + u_norm * (radius - r_min)) * jitter
                };
                local_x[u] = r * theta.cos();
                local_y[u] = r * theta.sin();
                // Fibonacci sphere z elevation for rich 3D constellation volume
                let z_norm = 1.0 - 2.0 * ((k + 0.5) / sat_count);
                local_z[u] = radius * 1.15 * z_norm * (0.55 + 0.45 * u_norm);
            }

            let has_sub_hubs = satellites.iter().any(|&u| adj[u].len() >= 3);
            if has_sub_hubs && comp.len() >= 6 {
                for _step in 0..6 {
                    for &u in &satellites {
                        if adj[u].len() <= 3 {
                            let mut sx = 0.0f64;
                            let mut sy = 0.0f64;
                            let mut sz = 0.0f64;
                            let mut sc = 0usize;
                            for &nb in &adj[u] {
                                if nb != hub && adj[nb].len() >= 3 {
                                    sx += local_x[nb];
                                    sy += local_y[nb];
                                    sz += local_z[nb];
                                    sc += 1;
                                }
                            }
                            if sc > 0 {
                                local_x[u] = local_x[u] * 0.86 + (sx / sc as f64) * 0.14;
                                local_y[u] = local_y[u] * 0.86 + (sy / sc as f64) * 0.14;
                                local_z[u] = local_z[u] * 0.86 + (sz / sc as f64) * 0.14;
                            }
                        }
                    }
                }
            }
        }

        for (c_idx, comp) in layout_comps.iter().enumerate() {
            let cx = cluster_cx[c_idx];
            let cy = cluster_cy[c_idx];
            let cz = cluster_cz[c_idx];
            for &u in comp {
                pos_x[u] = cx + local_x[u];
                pos_y[u] = cy + local_y[u];
                pos_z[u] = cz + local_z[u];
            }
        }

        let mut min_x = f64::INFINITY;
        let mut max_x = f64::NEG_INFINITY;
        let mut min_y = f64::INFINITY;
        let mut max_y = f64::NEG_INFINITY;
        let mut min_z = f64::INFINITY;
        let mut max_z = f64::NEG_INFINITY;
        for i in 0..n {
            min_x = min_x.min(pos_x[i]);
            max_x = max_x.max(pos_x[i]);
            min_y = min_y.min(pos_y[i]);
            max_y = max_y.max(pos_y[i]);
            min_z = min_z.min(pos_z[i]);
            max_z = max_z.max(pos_z[i]);
        }
        let center_x = (min_x + max_x) * 0.5;
        let center_y = (min_y + max_y) * 0.5;
        let center_z = (min_z + max_z) * 0.5;
        let span_x = (max_x - min_x).max(0.01);
        let span_y = (max_y - min_y).max(0.01);
        let span_z = (max_z - min_z).max(0.01);
        let span_max = span_x.max(span_y);
        let eff_span_x = span_x * 0.72 + span_max * 0.28;
        let eff_span_y = span_y * 0.72 + span_max * 0.28;
        let eff_span_z = span_z.max(span_max * 0.45);
        for i in 0..n {
            pos_x[i] = 0.5 + ((pos_x[i] - center_x) / eff_span_x) * 0.88;
            pos_y[i] = 0.5 + ((pos_y[i] - center_y) / eff_span_y) * 0.88;
            pos_z[i] = 0.5 + ((pos_z[i] - center_z) / eff_span_z) * 0.80;
        }
    }

    let graph_group_color = |top_folder: &str, is_journal: bool| -> &'static str {
        let prefix = if top_folder.len() >= 2 && top_folder.as_bytes()[0].is_ascii_digit() && top_folder.as_bytes()[1].is_ascii_digit() {
            &top_folder[..2]
        } else {
            ""
        };
        match prefix {
            "00" => "#8dc9d6",
            "10" => "#87c2d0",
            "20" => "#81be99",
            "30" => "#7ac1e2",
            "40" => "#6cc0e4",
            "50" => "#5fa1c6",
            "60" => "#4a93ba",
            "70" => "#3c81a3",
            "80" => "#344145",
            "90" => "#3d484b",
            "99" => "#353d3f",
            _ if is_journal => "#8dc9d6",
            _ => "#7bb5c1",
        }
    };

    let group_index_map: HashMap<&str, usize> = groups
        .iter()
        .enumerate()
        .map(|(i, g)| (g.as_str(), i))
        .collect();

    let nodes_json: Vec<Value> = nodes
        .iter()
        .enumerate()
        .map(|(idx, node)| {
            let g_name = if node.top_folder.is_empty() {
                "root"
            } else {
                node.top_folder.as_str()
            };
            let g_idx = group_index_map.get(g_name).copied().unwrap_or(0);
            let deg = in_deg[idx] + out_deg[idx];
            let color_hex = graph_group_color(g_name, node.is_journal);
            json!({
                "id": node.id,
                "title": node.title,
                "relPath": node.rel_path,
                "folder": node.folder,
                "group": g_name,
                "groupIndex": g_idx,
                "clusterId": cluster_id_of[idx],
                "isOrphan": is_orphan_of[idx],
                "isTagNode": node.is_tag_node,
                "isVirtual": node.is_virtual,
                "tagName": node.tag_name,
                "colorHex": color_hex,
                "degree": deg,
                "isHub": node.is_tag_node || deg >= 6,
                "inDegree": in_deg[idx],
                "outDegree": out_deg[idx],
                "isJournal": node.is_journal,
                "tags": node.tags,
                "x": (pos_x[idx] * 10000.0).round() / 10000.0,
                "y": (pos_y[idx] * 10000.0).round() / 10000.0,
                "z": (pos_z[idx] * 10000.0).round() / 10000.0,
            })
        })
        .collect();

    let edges_json: Vec<Value> = edges_set
        .iter()
        .map(|&(u, v)| {
            json!({
                "source": nodes[u].id,
                "target": nodes[v].id,
                "sourceIndex": u,
                "targetIndex": v,
                "clusterId": cluster_id_of[u],
            })
        })
        .collect();

    json!({
        "nodes": nodes_json,
        "edges": edges_json,
        "groups": groups,
        "clusterCount": connected_comps.len(),
        "orphanCount": orphans.len(),
    })
}

fn compute_activity_heatmap_days(notes: &[ParsedNoteSummary], now_secs: u64, num_days: i64) -> Vec<Value> {
    let today_days = (now_secs / 86400) as i64;
    let mut counts_by_day: HashMap<i64, usize> = HashMap::new();
    for note in notes {
        if note.mtime_secs > 0 {
            let d = (note.mtime_secs / 86400) as i64;
            *counts_by_day.entry(d).or_insert(0) += 1;
        }
    }
    let span = num_days.max(7);
    let start_day = today_days - (span - 1);
    let mut cells = Vec::with_capacity(span as usize);
    for day_idx in start_day..=today_days {
        let (y, m, d) = civil_from_days(day_idx);
        let c = *counts_by_day.get(&day_idx).unwrap_or(&0);
        let level = match c {
            0 => 0,
            1 => 1,
            2..=3 => 2,
            4..=6 => 3,
            _ => 4,
        };
        cells.push(json!({
            "date": format!("{:04}-{:02}-{:02}", y, m, d),
            "count": c,
            "level": level,
        }));
    }
    cells
}

fn compute_activity_heatmap(notes: &[ParsedNoteSummary], now_secs: u64) -> Vec<Value> {
    // 17 weeks = 119 days, matching "activity latest note edits · 17 weeks" in the reference image
    compute_activity_heatmap_days(notes, now_secs, 119)
}

fn normalize_obsidian_hotkey_entry(entry: &Value) -> Option<String> {
    let key_raw = entry.get("key")?.as_str()?.trim();
    if key_raw.is_empty() {
        return None;
    }
    let mut has_ctrl = false;
    let mut has_alt = false;
    let mut has_shift = false;
    let mut has_meta = false;
    if let Some(mods) = entry.get("modifiers").and_then(|v| v.as_array()) {
        for m in mods {
            if let Some(ms) = m.as_str() {
                match ms {
                    "Mod" | "Ctrl" | "Control" => has_ctrl = true,
                    "Alt" | "Option" => has_alt = true,
                    "Shift" => has_shift = true,
                    "Meta" | "Cmd" | "Super" => has_meta = true,
                    _ => {}
                }
            }
        }
    }
    let norm_key = match key_raw {
        " " | "Space" => "Space".to_string(),
        "ArrowLeft" | "Left" => "Left".to_string(),
        "ArrowRight" | "Right" => "Right".to_string(),
        "ArrowUp" | "Up" => "Up".to_string(),
        "ArrowDown" | "Down" => "Down".to_string(),
        "Escape" | "Esc" => "Escape".to_string(),
        "Enter" | "Return" => "Enter".to_string(),
        k if k.len() == 1 => k.to_ascii_uppercase(),
        other => other.to_string(),
    };
    let mut parts = Vec::new();
    if has_ctrl {
        parts.push("Ctrl".to_string());
    }
    if has_alt {
        parts.push("Alt".to_string());
    }
    if has_shift {
        parts.push("Shift".to_string());
    }
    if has_meta {
        parts.push("Meta".to_string());
    }
    parts.push(norm_key);
    Some(parts.join("+"))
}

pub fn read_vault_obsidian_hotkeys(vault_canon: &Path) -> Value {
    let hotkeys_path = vault_canon.join(".obsidian/hotkeys.json");
    let Ok(raw) = fs::read_to_string(&hotkeys_path) else {
        return json!({});
    };
    let Ok(parsed) = serde_json::from_str::<Value>(&raw) else {
        return json!({});
    };
    let Some(obj) = parsed.as_object() else {
        return json!({});
    };
    let mut normalized = serde_json::Map::new();
    for (cmd_id, bindings_val) in obj {
        if let Some(arr) = bindings_val.as_array() {
            let combos: Vec<String> = arr
                .iter()
                .filter_map(normalize_obsidian_hotkey_entry)
                .collect();
            if let Some(first) = combos.first() {
                normalized.insert(
                    cmd_id.clone(),
                    json!({
                        "primary": first,
                        "all": combos,
                    }),
                );
            }
        }
    }
    Value::Object(normalized)
}

fn extract_frontmatter_yaml_list(lines: &[String], target_key: &str) -> Vec<String> {
    if lines.first().map(|s| s.trim()) != Some("---") {
        return Vec::new();
    }
    let mut items = Vec::new();
    let mut in_key = false;
    for line in lines.iter().skip(1) {
        let trimmed = line.trim();
        if trimmed == "---" || trimmed == "..." {
            break;
        }
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        if let Some(rest) = trimmed.strip_prefix("- ") {
            if in_key {
                let item = rest.trim().trim_matches('"').trim_matches('\'').to_string();
                if !item.is_empty() {
                    items.push(item);
                }
            }
            continue;
        }
        if let Some((k, v)) = trimmed.split_once(':') {
            let key_clean = k.trim();
            if key_clean.eq_ignore_ascii_case(target_key) {
                in_key = true;
                let val_clean = v.trim();
                if val_clean.starts_with('[') && val_clean.ends_with(']') {
                    let inner = &val_clean[1..val_clean.len() - 1];
                    for part in inner.split(',') {
                        let p = part.trim().trim_matches('"').trim_matches('\'');
                        if !p.is_empty() {
                            items.push(p.to_string());
                        }
                    }
                    in_key = false;
                }
            } else {
                in_key = false;
            }
        }
    }
    items
}

fn parse_vault_daily_schedule_for_weekday(
    vault_canon: &Path,
    callout_path: &str,
    schedule_heading: &str,
    exercise_heading: &str,
    cardio_heading: &str,
    wd: u32,
) -> Value {
    let wd_name = weekday_name(wd);
    let filename = format!("{:02}_{}.md", wd + 1, wd_name);
    let clean_callout = callout_path.trim().trim_matches('/');
    let rel_path = if clean_callout.is_empty() {
        filename.clone()
    } else {
        format!("{}/{}", clean_callout, filename)
    };
    let full_path = vault_canon.join(&rel_path);
    let Ok(content) = fs::read_to_string(&full_path) else {
        return json!({
            "available": false,
            "weekday": wd_name,
            "weekdayIndex": wd,
            "relPath": rel_path,
            "scheduleRows": [],
            "exerciseRows": [],
            "cardioRows": [],
            "sections": [],
        });
    };
    let lines: Vec<String> = content.lines().map(|s| s.to_string()).collect();
    let (_, _, _, body_start) = parse_frontmatter(&lines);
    let (blocks, _, _, _, _) = parse_blocks(&lines, body_start);

    let clean_heading = |s: &str| -> String {
        s.trim()
            .trim_matches(|c: char| c == '*' || c == '_' || c == '`' || c.is_whitespace())
            .to_string()
    };
    let clean_cell = |s: &str| -> String {
        let step1 = s
            .replace("<br/>", " · ")
            .replace("<br />", " · ")
            .replace("<br>", " · ")
            .replace("**", "")
            .replace("__", "");
        step1.split_whitespace().collect::<Vec<_>>().join(" ")
    };

    let extract_section = |section_id: &str, heading_title: &str| -> Value {
        let target_heading = clean_heading(heading_title);
        let mut in_sec = false;
        let mut sec_level = 1usize;
        let mut headers: Vec<String> = Vec::new();
        let mut rows: Vec<Vec<String>> = Vec::new();
        let mut text_lines: Vec<String> = Vec::new();

        for b in &blocks {
            if b.kind == "heading" {
                if clean_heading(&b.title).eq_ignore_ascii_case(&target_heading) {
                    in_sec = true;
                    sec_level = b.level;
                    continue;
                } else if in_sec && b.level <= sec_level {
                    break;
                }
            }
            if in_sec {
                if b.kind == "table" && headers.is_empty() {
                    headers = b.table_headers.iter().map(|h| clean_cell(h)).collect();
                    rows = b
                        .table_rows
                        .iter()
                        .map(|r| r.iter().map(|c| clean_cell(c)).collect())
                        .collect();
                } else if b.kind == "paragraph" || b.kind == "bullet" {
                    let cleaned = clean_cell(&b.text);
                    if !cleaned.is_empty() {
                        text_lines.push(cleaned);
                    }
                }
            }
        }
        json!({
            "id": section_id,
            "title": heading_title,
            "headers": headers,
            "rows": rows,
            "text": text_lines.join(" "),
        })
    };

    let sched_sec = extract_section("schedule", schedule_heading);
    let ex_sec = extract_section("exercise", exercise_heading);
    let cardio_sec = extract_section("cardio", cardio_heading);

    let schedule_rows: Vec<Value> = sched_sec["rows"]
        .as_array()
        .map(|arr| {
            arr.iter()
                .map(|r| {
                    let cols = r.as_array();
                    json!({
                        "time": cols.and_then(|c| c.first()).and_then(|v| v.as_str()).unwrap_or(""),
                        "activity": cols.and_then(|c| c.get(1)).and_then(|v| v.as_str()).unwrap_or(""),
                    })
                })
                .collect()
        })
        .unwrap_or_default();

    let exercise_rows: Vec<Value> = ex_sec["rows"]
        .as_array()
        .map(|arr| {
            arr.iter()
                .map(|r| {
                    let cols = r.as_array();
                    let len = cols.map(|c| c.len()).unwrap_or(0);
                    if len >= 4 {
                        json!({
                            "exercise": cols.and_then(|c| c.first()).and_then(|v| v.as_str()).unwrap_or(""),
                            "equipment": cols.and_then(|c| c.get(1)).and_then(|v| v.as_str()).unwrap_or(""),
                            "reps": cols.and_then(|c| c.get(2)).and_then(|v| v.as_str()).unwrap_or(""),
                            "sets": cols.and_then(|c| c.get(3)).and_then(|v| v.as_str()).unwrap_or(""),
                        })
                    } else {
                        json!({
                            "exercise": cols.and_then(|c| c.first()).and_then(|v| v.as_str()).unwrap_or(""),
                            "equipment": "",
                            "reps": cols.and_then(|c| c.get(1)).and_then(|v| v.as_str()).unwrap_or(""),
                            "sets": cols.and_then(|c| c.get(2)).and_then(|v| v.as_str()).unwrap_or(""),
                        })
                    }
                })
                .collect()
        })
        .unwrap_or_default();

    let cardio_rows: Vec<Value> = cardio_sec["rows"]
        .as_array()
        .map(|arr| {
            arr.iter()
                .map(|r| {
                    let cols = r.as_array();
                    let len = cols.map(|c| c.len()).unwrap_or(0);
                    if len >= 4 {
                        json!({
                            "exercise": cols.and_then(|c| c.first()).and_then(|v| v.as_str()).unwrap_or(""),
                            "equipment": cols.and_then(|c| c.get(1)).and_then(|v| v.as_str()).unwrap_or(""),
                            "duration": cols.and_then(|c| c.get(2)).and_then(|v| v.as_str()).unwrap_or(""),
                            "intensity": cols.and_then(|c| c.get(3)).and_then(|v| v.as_str()).unwrap_or(""),
                        })
                    } else {
                        json!({
                            "exercise": cols.and_then(|c| c.first()).and_then(|v| v.as_str()).unwrap_or(""),
                            "equipment": "",
                            "duration": cols.and_then(|c| c.get(1)).and_then(|v| v.as_str()).unwrap_or(""),
                            "intensity": cols.and_then(|c| c.get(2)).and_then(|v| v.as_str()).unwrap_or(""),
                        })
                    }
                })
                .collect()
        })
        .unwrap_or_default();

    let sections = vec![sched_sec, ex_sec, cardio_sec];

    json!({
        "available": true,
        "weekday": wd_name,
        "weekdayIndex": wd,
        "relPath": rel_path,
        "scheduleHeading": schedule_heading,
        "exerciseHeading": exercise_heading,
        "cardioHeading": cardio_heading,
        "scheduleRows": schedule_rows,
        "exerciseRows": exercise_rows,
        "cardioRows": cardio_rows,
        "sections": sections,
    })
}

fn parse_vault_daily_schedule(
    vault_canon: &Path,
    callout_path: &str,
    schedule_heading: &str,
    exercise_heading: &str,
    cardio_heading: &str,
    now_secs: u64,
) -> Value {
    let (today_y, today_m, today_d) = civil_from_days((now_secs / 86400) as i64);
    let wd = weekday_monday_zero(today_y, today_m, today_d);
    parse_vault_daily_schedule_for_weekday(
        vault_canon,
        callout_path,
        schedule_heading,
        exercise_heading,
        cardio_heading,
        wd,
    )
}

fn pick_vault_quote_for_seed(vault_canon: &Path, seed: usize) -> (String, String) {
    let candidates = [
        vault_canon.join("90_System/93_Configuration/Custom_Views/Journal/quotes.js"),
        vault_canon.join("90_System/92_Scripts/quotes.js"),
    ];
    for quotes_path in &candidates {
        if let Ok(raw) = fs::read_to_string(quotes_path) {
            let mut pairs: Vec<(String, String)> = Vec::new();
            for line in raw.lines() {
                if let (Some(t_pos), Some(a_pos)) = (line.find("text:"), line.find("author:")) {
                    let t_part = &line[t_pos + 5..a_pos];
                    let a_part = &line[a_pos + 7..];
                    let text = t_part
                        .trim()
                        .trim_end_matches(',')
                        .trim()
                        .trim_matches('"')
                        .trim_matches('\'')
                        .replace("\\\"", "\"");
                    let author = a_part
                        .trim()
                        .trim_end_matches(';')
                        .trim_end_matches(']')
                        .trim_end_matches('}')
                        .trim_end_matches(',')
                        .trim_end_matches('}')
                        .trim()
                        .trim_matches('"')
                        .trim_matches('\'');
                    if !text.is_empty() {
                        pairs.push((text, author.to_string()));
                    }
                }
            }
            if !pairs.is_empty() {
                let idx = seed % pairs.len();
                return pairs.swap_remove(idx);
            }
        }
    }
    let fallback = [
        ("We suffer more often in imagination than in reality.", "Seneca"),
        ("Waste no more time arguing about what a good man should be. Be one.", "Marcus Aurelius"),
        ("He who has a why to live can bear almost any how.", "Friedrich Nietzsche"),
        ("Simplicity is the ultimate sophistication.", "Leonardo da Vinci"),
        ("Discipline equals freedom.", "Jocko Willink"),
    ];
    let (q, a) = fallback[seed % fallback.len()];
    (q.to_string(), a.to_string())
}

fn compute_vault_finance_summary(notes: &[ParsedNoteSummary]) -> Value {
    let mut transactions = Vec::new();
    let mut accounts = Vec::new();
    let mut subscriptions = Vec::new();
    let mut total_income = 0.0f64;
    let mut total_expense = 0.0f64;
    let mut category_totals: BTreeMap<String, f64> = BTreeMap::new();

    for note in notes {
        let lower = note.rel_path.to_ascii_lowercase();
        let get_fm = |k: &str| -> String {
            note.frontmatter
                .get(k)
                .map(|s| strip_wikilink_brackets(s).trim().to_string())
                .unwrap_or_default()
        };
        if !lower.contains("22_finance/records/") {
            // Also support markdown table ledgers in Finance Report notes (## Income / ## Spending)
            let is_fin_ledger = lower.contains("finance")
                || get_fm("categories").to_ascii_lowercase().contains("finance");
            if is_fin_ledger {
                let mut mode = "";
                let ledger_lines = if !note.lines.is_empty() {
                    &note.lines
                } else {
                    &note.finance_table_lines
                };
                for line in ledger_lines {
                    let trimmed = line.trim();
                    if trimmed.starts_with("##") {
                        let h = trimmed.trim_start_matches('#').trim().to_ascii_lowercase();
                        if h.contains("income") {
                            mode = "income";
                        } else if h.contains("spend") || h.contains("expense") {
                            mode = "expense";
                        } else {
                            mode = "";
                        }
                        continue;
                    }
                    if !mode.is_empty() && trimmed.starts_with('|') && trimmed.ends_with('|') {
                        let cols: Vec<&str> = trimmed[1..trimmed.len() - 1]
                            .split('|')
                            .map(|c| c.trim())
                            .collect();
                        if cols.len() >= 4 && !cols[0].contains("---") && !cols[0].eq_ignore_ascii_case("date") {
                            if let Ok(amt) = cols[3].replace(',', "").parse::<f64>() {
                                if mode == "income" {
                                    total_income += amt;
                                } else {
                                    total_expense += amt;
                                    *category_totals.entry(cols[2].to_string()).or_insert(0.0) += amt;
                                }
                                transactions.push(json!({
                                    "relPath": note.rel_path,
                                    "title": cols[1],
                                    "date": cols[0],
                                    "type": mode,
                                    "amount": amt,
                                    "currency": "VND",
                                    "category": cols[2],
                                    "account": "Cash",
                                    "merchant": cols[1],
                                    "status": "cleared",
                                }));
                            }
                        }
                    }
                }
            }
            continue;
        }
        if lower.contains("/transactions/") {
            let amount = get_fm("baseamount")
                .or_else_empty(|| get_fm("amount"))
                .replace(',', "")
                .parse::<f64>()
                .unwrap_or(0.0);
            let tx_type = {
                let t = get_fm("transactiontype");
                if !t.is_empty() {
                    t
                } else {
                    get_fm("type")
                }
            };
            let cat = {
                let c = get_fm("category");
                if !c.is_empty() {
                    c
                } else {
                    "General".to_string()
                }
            };
            let acct = {
                let a = get_fm("account");
                if !a.is_empty() {
                    a
                } else {
                    get_fm("fromaccount")
                }
            };
            let date = {
                let d = get_fm("date");
                if !d.is_empty() {
                    d
                } else {
                    get_fm("created")
                }
            };
            let tx_title = {
                let desc = get_fm("description");
                if !desc.is_empty() {
                    desc
                } else {
                    note.title.clone()
                }
            };
            if tx_type.eq_ignore_ascii_case("income") {
                total_income += amount;
            } else {
                total_expense += amount;
                *category_totals.entry(cat.clone()).or_insert(0.0) += amount;
            }
            transactions.push(json!({
                "relPath": note.rel_path,
                "title": tx_title,
                "date": date,
                "type": if tx_type.is_empty() { "expense".to_string() } else { tx_type },
                "amount": amount,
                "currency": get_fm("currency"),
                "category": cat,
                "account": acct,
                "merchant": get_fm("merchant"),
                "status": get_fm("status"),
            }));
        } else if lower.contains("/accounts/") {
            let bal = get_fm("openingbalance")
                .or_else_empty(|| get_fm("balance"))
                .replace(',', "")
                .parse::<f64>()
                .unwrap_or(0.0);
            accounts.push(json!({
                "relPath": note.rel_path,
                "title": note.title,
                "accountType": get_fm("accounttype"),
                "institution": get_fm("institution"),
                "balance": bal,
                "currency": get_fm("currency"),
                "status": get_fm("status"),
            }));
        } else if lower.contains("/subscription/") {
            let amount = get_fm("amount").replace(',', "").parse::<f64>().unwrap_or(0.0);
            subscriptions.push(json!({
                "relPath": note.rel_path,
                "title": note.title,
                "amount": amount,
                "currency": get_fm("currency"),
                "cycle": get_fm("billingcycle"),
                "nextBillingDate": get_fm("nextbillingdate"),
                "category": get_fm("category"),
                "status": get_fm("status"),
            }));
        }
    }

    transactions.sort_by(|a, b| {
        b["date"]
            .as_str()
            .unwrap_or("")
            .cmp(a["date"].as_str().unwrap_or(""))
    });

    let mut cat_vec: Vec<(String, f64)> = category_totals.into_iter().collect();
    cat_vec.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
    let categories_json: Vec<Value> = cat_vec
        .into_iter()
        .map(|(cat, amt)| json!({ "category": cat, "amount": amt }))
        .collect();
    let opening_balance: f64 = accounts
        .iter()
        .map(|a| a["balance"].as_f64().unwrap_or(0.0))
        .sum();
    let net_cashflow = total_income - total_expense;

    json!({
        "available": true,
        "openingBalance": opening_balance,
        "closingBalance": opening_balance + net_cashflow,
        "totalIncome": total_income,
        "totalExpense": total_expense,
        "totalSpent": total_expense,
        "netCashflow": net_cashflow,
        "balance": opening_balance + net_cashflow,
        "transactions": transactions,
        "accounts": accounts,
        "subscriptions": subscriptions,
        "categories": categories_json,
        "categoryBreakdown": categories_json,
    })
}

trait StringOrElseEmpty {
    fn or_else_empty<F: FnOnce() -> String>(self, f: F) -> String;
}
impl StringOrElseEmpty for String {
    fn or_else_empty<F: FnOnce() -> String>(self, f: F) -> String {
        if self.is_empty() {
            f()
        } else {
            self
        }
    }
}

fn normalize_cache_path(s: &str) -> &str {
    let t = s.trim();
    t.strip_prefix("file://").unwrap_or(t)
}

fn ui_sidecar_cache_path(cache_path_str: &str) -> String {
    let norm = normalize_cache_path(cache_path_str);
    if norm.is_empty() {
        String::new()
    } else {
        format!("{}.ui.json", norm)
    }
}

#[derive(Deserialize)]
struct ScanCacheEnvelope {
    #[serde(rename = "_scanSignature")]
    scan_signature: Option<String>,
    #[serde(rename = "_cachedEntries", default)]
    cached_entries: HashMap<String, CachedMarkdownEntry>,
}

fn load_cached_markdown_entries_and_sig(
    cache_file_opt: Option<&str>,
) -> (HashMap<String, CachedMarkdownEntry>, Option<String>) {
    let Some(cache_path_str) = cache_file_opt.map(normalize_cache_path).filter(|s| !s.is_empty()) else {
        return (HashMap::new(), None);
    };
    let Ok(bytes) = fs::read(cache_path_str) else {
        return (HashMap::new(), None);
    };
    let Ok(env) = serde_json::from_slice::<ScanCacheEnvelope>(&bytes) else {
        return (HashMap::new(), None);
    };
    (env.cached_entries, env.scan_signature)
}

fn fnv1a_update_bytes(hash: &mut u64, bytes: &[u8]) {
    for &b in bytes {
        *hash ^= b as u64;
        *hash = hash.wrapping_mul(0x100000001b3);
    }
}

fn fnv1a_update_meta(hash: &mut u64, path: &Path) {
    if let Ok(meta) = fs::metadata(path) {
        let mtime = meta
            .modified()
            .ok()
            .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
            .map(|d| d.as_secs())
            .unwrap_or(0);
        fnv1a_update_bytes(hash, &1u8.to_le_bytes());
        fnv1a_update_bytes(hash, &meta.len().to_le_bytes());
        fnv1a_update_bytes(hash, &mtime.to_le_bytes());
    } else {
        fnv1a_update_bytes(hash, &0u8.to_le_bytes());
    }
}

fn parse_scan_today_iso(date_opt: Option<&str>, now_secs: u64) -> Result<String, String> {
    let (ty, tm, td) = civil_from_days((now_secs / 86400) as i64);
    if let Some(date) = date_opt {
        let parts: Vec<&str> = date.split('-').collect();
        if parts.len() != 3 {
            return Err("Expected scan date in YYYY-MM-DD format".to_string());
        }
        let year = parts[0].parse::<i32>().map_err(|_| "Invalid scan year")?;
        let month = parts[1].parse::<u32>().map_err(|_| "Invalid scan month")?;
        let day = parts[2].parse::<u32>().map_err(|_| "Invalid scan day")?;
        if !(1..=12).contains(&month) || day == 0 || day > days_in_month(year, month) {
            return Err("Scan date out of range".to_string());
        }
        Ok(format!("{:04}-{:02}-{:02}", year, month, day))
    } else {
        Ok(format!("{:04}-{:02}-{:02}", ty, tm, td))
    }
}

fn compute_vault_scan_signature(
    vault_canon: &Path,
    today_iso: &str,
    flat_files: &[FlatFileEntry],
    next_cache: &BTreeMap<String, CachedMarkdownEntry>,
) -> String {
    let mut hash: u64 = 0xcbf29ce484222325;
    fnv1a_update_bytes(&mut hash, today_iso.as_bytes());
    fnv1a_update_bytes(&mut hash, b"|");

    let mut file_refs: Vec<&FlatFileEntry> = flat_files.iter().collect();
    file_refs.sort_by(|a, b| a.rel_path.cmp(&b.rel_path));
    for f in file_refs {
        fnv1a_update_bytes(&mut hash, f.rel_path.as_bytes());
        fnv1a_update_bytes(&mut hash, &f.size_bytes.to_le_bytes());
        fnv1a_update_bytes(&mut hash, &f.mtime_secs.to_le_bytes());
        fnv1a_update_bytes(&mut hash, b"\n");
    }

    for (k, entry) in next_cache {
        fnv1a_update_bytes(&mut hash, k.as_bytes());
        fnv1a_update_bytes(&mut hash, &entry.size_bytes.to_le_bytes());
        fnv1a_update_bytes(&mut hash, &entry.mtime_secs.to_le_bytes());
        fnv1a_update_bytes(&mut hash, b";");
    }

    for aux_rel in [
        ".obsidian/hotkeys.json",
        ".obsidian/plugins/obsidian-icon-folder/data.json",
        "90_System/93_Configuration/settings.md",
        "90_System/97_Daily_Schedule",
    ] {
        fnv1a_update_bytes(&mut hash, aux_rel.as_bytes());
        fnv1a_update_meta(&mut hash, &vault_canon.join(aux_rel));
    }

    format!(
        "fnv1a64:{:016x}:files={}:notes={}",
        hash,
        flat_files.len(),
        next_cache.len()
    )
}

fn write_json_cache_atomically(cache_path_str: &str, payload: &Value) -> Result<(), String> {
    let cache_path = Path::new(normalize_cache_path(cache_path_str));
    if cache_path.as_os_str().is_empty() {
        return Ok(());
    }
    if let Some(parent) = cache_path.parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent).map_err(|e| format!("Cannot create cache parent dir: {}", e))?;
        }
    }
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let fname = cache_path
        .file_name()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| "vault-cache.json".to_string());
    let tmp_path = cache_path.with_file_name(format!(".{}.tmp.{}.{}", fname, std::process::id(), nanos));
    let serialized = serde_json::to_vec(payload).map_err(|e| format!("Cannot serialize scan cache: {}", e))?;
    {
        let mut f = fs::File::create(&tmp_path).map_err(|e| format!("Cannot create temp cache file: {}", e))?;
        f.write_all(&serialized).map_err(|e| format!("Cannot write temp cache file: {}", e))?;
        let _ = f.sync_all();
    }
    fs::rename(&tmp_path, cache_path).map_err(|e| {
        let _ = fs::remove_file(&tmp_path);
        format!("Cannot commit scan cache atomically: {}", e)
    })
}

pub fn cmd_scan(vault_str: &str) -> Result<Value, String> {
    cmd_scan_for_date_with_cache(vault_str, None, None)
}

#[cfg(test)]
fn cmd_scan_for_date(vault_str: &str, date_opt: Option<&str>) -> Result<Value, String> {
    cmd_scan_for_date_with_cache(vault_str, date_opt, None)
}

pub fn cmd_scan_for_date_with_cache(
    vault_str: &str,
    date_opt: Option<&str>,
    cache_file_opt: Option<&str>,
) -> Result<Value, String> {
    cmd_scan_for_date_with_cache_opts(vault_str, date_opt, cache_file_opt, false)
}

pub fn cmd_scan_for_date_with_cache_opts(
    vault_str: &str,
    date_opt: Option<&str>,
    cache_file_opt: Option<&str>,
    skip_if_unchanged: bool,
) -> Result<Value, String> {
    let vault_canon = resolve_vault_root(vault_str)?;
    let (prev_cache, prev_sig) = load_cached_markdown_entries_and_sig(cache_file_opt);
    let use_cache = cache_file_opt.map(|s| !s.trim().is_empty()).unwrap_or(false);
    let mut next_cache: BTreeMap<String, CachedMarkdownEntry> = BTreeMap::new();
    let mut cache_stats = (0usize, 0usize);
    let mut flat_files = Vec::new();
    let mut notes = Vec::new();
    let mut tree = scan_directory_recursive_with_cache(
        &vault_canon,
        &vault_canon,
        &mut flat_files,
        &mut notes,
        if use_cache { Some(&prev_cache) } else { None },
        if use_cache { Some(&mut next_cache) } else { None },
        &mut cache_stats,
        false,
    );
    let now_secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let today_iso = parse_scan_today_iso(date_opt, now_secs)?;
    let scan_signature = if use_cache {
        compute_vault_scan_signature(&vault_canon, &today_iso, &flat_files, &next_cache)
    } else {
        String::new()
    };

    if skip_if_unchanged
        && use_cache
        && cache_stats.1 == 0
        && prev_cache.len() == next_cache.len()
        && prev_sig.as_deref() == Some(scan_signature.as_str())
    {
        if let Some(cache_path_str) = cache_file_opt.map(normalize_cache_path).filter(|s| !s.is_empty()) {
            let ui_path = ui_sidecar_cache_path(cache_path_str);
            if Path::new(cache_path_str).is_file() && Path::new(&ui_path).is_file() {
                return Ok(json!({
                    "ok": true,
                    "unchanged": true,
                    "vaultPath": vault_canon.to_string_lossy(),
                    "scanSignature": scan_signature,
                    "stats": {
                        "cacheHits": cache_stats.0,
                        "parsedNotes": 0,
                    }
                }));
            }
        }
    }

    let folder_icons = read_vault_folder_icons(&vault_canon);
    apply_vault_folder_icons_recursive(&mut tree, &folder_icons);

    let lookup = build_note_lookup(&notes);
    let graph = compute_vault_graph(&notes, &lookup);

    // Aggregate tags
    let mut tag_map: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for note in &notes {
        for tag in &note.tags {
            tag_map.entry(tag.clone()).or_default().push(note.rel_path.clone());
        }
    }
    let mut tags_list: Vec<Value> = tag_map
        .into_iter()
        .map(|(name, note_paths)| {
            json!({
                "name": name,
                "count": note_paths.len(),
                "notes": note_paths,
            })
        })
        .collect();
    tags_list.sort_by(|a, b| {
        b["count"]
            .as_u64()
            .unwrap_or(0)
            .cmp(&a["count"].as_u64().unwrap_or(0))
    });

    let earliest_mtime = flat_files
        .iter()
        .map(|f| f.mtime_secs)
        .filter(|&t| t > 0)
        .min()
        .unwrap_or(now_secs);

    // Read optional 90_System/93_Configuration/settings.md once for vault metadata & schedule paths
    let mut cfg_username = String::new();
    let mut cfg_vault_name = String::new();
    let mut cfg_start_date = String::new();
    let mut cfg_callout_path = "90_System/97_Daily_Schedule".to_string();
    let mut cfg_schedule_heading = "Daily Schedule".to_string();
    let mut cfg_exercise_heading = "Calisthenics".to_string();
    let mut cfg_cardio_heading = "Cardio".to_string();
    let mut cfg_weather_loc = "Can Tho, VN".to_string();
    let mut cfg_globe_settings = serde_json::Map::new();

    let settings_md_path = vault_canon.join("90_System/93_Configuration/settings.md");
    if let Ok(settings_raw) = fs::read_to_string(&settings_md_path) {
        let s_lines: Vec<String> = settings_raw.lines().map(|s| s.to_string()).collect();
        let (s_props, _, _, _) = parse_frontmatter(&s_lines);
        if let Some(u) = s_props.get("username").filter(|s| !s.trim().is_empty()) {
            cfg_username = u.trim().to_string();
        }
        if let Some(vn) = s_props.get("vault_name").filter(|s| !s.trim().is_empty()) {
            cfg_vault_name = vn.trim().to_string();
        }
        if let Some(sd) = s_props.get("start_date").filter(|s| !s.trim().is_empty()) {
            cfg_start_date = sd.trim().to_string();
        }
        if let Some(cp) = s_props.get("callout_path").filter(|s| !s.trim().is_empty()) {
            cfg_callout_path = cp.trim().to_string();
        }
        if let Some(sh) = s_props.get("schedule_heading").filter(|s| !s.trim().is_empty()) {
            cfg_schedule_heading = sh.trim().to_string();
        }
        if let Some(eh) = s_props.get("exercise_heading").filter(|s| !s.trim().is_empty()) {
            cfg_exercise_heading = eh.trim().to_string();
        }
        if let Some(ch) = s_props.get("cardio_heading").filter(|s| !s.trim().is_empty()) {
            cfg_cardio_heading = ch.trim().to_string();
        }
        if let Some(wl) = s_props.get("weather_location").filter(|s| !s.trim().is_empty()) {
            cfg_weather_loc = wl.trim().to_string();
        }
        for gk in [
            "globe_size",
            "globe_style",
            "globe_monochrome_color",
            "location_pins",
            "globe_source_folders",
            "globe_display_min",
            "globe_display_max",
            "globe_render_min",
            "globe_render_max",
            "globe_min_zoom",
            "globe_max_zoom",
            "globe_default_zoom",
            "globe_base_scale",
            "globe_texture_width",
            "globe_texture_height",
            "globe_map_provider",
            "globe_api_key",
            "globe_tile_url",
        ] {
            if let Some(val) = s_props.get(gk) {
                cfg_globe_settings.insert(gk.to_string(), Value::String(val.trim().to_string()));
            }
        }
    }

    let vault_age_days = if let Some((y_s, rest)) = cfg_start_date.split_once('-') {
        if let Some((m_s, d_s)) = rest.split_once('-') {
            if let (Ok(y), Ok(m), Ok(d)) = (
                y_s.trim().parse::<i32>(),
                m_s.trim().parse::<u32>(),
                d_s.trim().parse::<u32>(),
            ) {
                let start_days = days_from_civil(y, m, d);
                let today_days = (now_secs / 86400) as i64;
                (today_days - start_days).max(0) as u64
            } else {
                now_secs.saturating_sub(earliest_mtime) / 86400
            }
        } else {
            now_secs.saturating_sub(earliest_mtime) / 86400
        }
    } else {
        now_secs.saturating_sub(earliest_mtime) / 86400
    };

    let age_years = vault_age_days / 365;
    let age_rem_days = vault_age_days % 365;
    let vault_age_formatted = if age_years > 0 {
        format!(
            "{} year{} {} day{}",
            age_years,
            if age_years == 1 { "" } else { "s" },
            age_rem_days,
            if age_rem_days == 1 { "" } else { "s" }
        )
    } else {
        format!("{} days", vault_age_days)
    };

    let journal_count = notes.iter().filter(|n| n.is_journal).count();
    let book_count = notes
        .iter()
        .filter(|n| {
            n.tags.iter().any(|t| t.eq_ignore_ascii_case("book"))
                || n.rel_path.contains("24_Book_Tracker")
        })
        .count();
    let open_tasks: usize = notes.iter().map(|n| n.open_tasks).sum();
    let done_tasks: usize = notes.iter().map(|n| n.done_tasks).sum();
    let image_count = flat_files.iter().filter(|f| f.category == "image").count();
    let code_count = flat_files.iter().filter(|f| f.category == "code").count();
    let external_count = flat_files.iter().filter(|f| f.category == "external").count();

    let asset_index = AssetLookupIndex::from_flat_files(&flat_files);

    // Build custom collections across all vault domains (building full dossier JSON only for collection notes)
    let mut col_movies = Vec::new();
    let mut col_tvseries = Vec::new();
    let mut col_games = Vec::new();
    let mut col_websites = Vec::new();
    let mut col_cornell = Vec::new();
    let mut col_zettelkasten = Vec::new();
    let mut col_places = Vec::new();
    let mut col_books = Vec::new();
    let mut col_recipes = Vec::new();
    let mut col_exercises = Vec::new();
    let mut col_clippings = Vec::new();
    let mut col_finance = Vec::new();
    let mut col_contacts = Vec::new();

    for note in &notes {
        let kind = classify_note_kind(
            &note.rel_path,
            &note.stem,
            &note.title,
            &note.frontmatter,
            &note.tags,
        );
        let build_dossier = || {
            let mut d = build_note_dossier_with_index(
                &vault_canon,
                kind,
                &note.rel_path,
                &note.title,
                &note.frontmatter,
                &note.snippet,
                &asset_index,
            );
            if let Some(obj) = d.as_object_mut() {
                obj.insert("tags".to_string(), json!(note.tags));
                obj.insert("linkCount".to_string(), json!(note.outgoing_links.len()));
                obj.insert("openTasks".to_string(), json!(note.open_tasks));
                obj.insert("doneTasks".to_string(), json!(note.done_tasks));
                obj.insert("mtimeSecs".to_string(), json!(note.mtime_secs));
            }
            d
        };
        match kind {
            "movie" => col_movies.push(build_dossier()),
            "tvseries" => col_tvseries.push(build_dossier()),
            "game" => col_games.push(build_dossier()),
            "website" => col_websites.push(build_dossier()),
            "cornell" => col_cornell.push(build_dossier()),
            "zettelkasten" => col_zettelkasten.push(build_dossier()),
            "place" => col_places.push(build_dossier()),
            "book" => col_books.push(build_dossier()),
            "recipe" => col_recipes.push(build_dossier()),
            "exercise" => col_exercises.push(build_dossier()),
            "clipping" => col_clippings.push(build_dossier()),
            "finance" => col_finance.push(build_dossier()),
            "contact" => col_contacts.push(build_dossier()),
            _ => {}
        }
    }

    let finance_summary = compute_vault_finance_summary(&notes);

    let homepage_photo_url = [
        "797722956_17919373971425474_540898127545340166_n.jpg",
        "90_System/95_Attachments/b93849c34966ce3a9c5af52b02521bf3.jpg",
    ]
    .iter()
    .map(|cand| resolve_vault_asset_url_with_index(&vault_canon, cand, &asset_index))
    .find(|u| !u.is_empty())
    .unwrap_or_default();

    let homepage_cover_url = [
        "90_System/95_Media_Assets/Avatar/Dont_Starve_Avatar_Dark_Teal.png",
        "797722956_17919373971425474_540898127545340166_n.jpg",
        "90_System/95_Attachments/b93849c34966ce3a9c5af52b02521bf3.jpg",
    ]
    .iter()
    .map(|cand| resolve_vault_asset_url_with_index(&vault_canon, cand, &asset_index))
    .find(|u| !u.is_empty())
    .unwrap_or_default();

    let mut sorted_notes: Vec<ParsedNoteSummary> = notes
        .iter()
        .filter(|n| !is_template_note_summary(n))
        .cloned()
        .collect();
    sorted_notes.sort_by(|a, b| b.mtime_secs.cmp(&a.mtime_secs));
    let recent_notes: Vec<Value> = sorted_notes
        .iter()
        .take(16)
        .map(|n| {
            json!({
                "relPath": n.rel_path,
                "title": n.title,
                "folder": n.folder,
                "mtimeSecs": n.mtime_secs,
                "snippet": n.snippet,
                "tags": n.tags,
                "openTasks": n.open_tasks,
                "doneTasks": n.done_tasks,
            })
        })
        .collect();

    let top_folders: Vec<Value> = tree
        .children
        .iter()
        .filter(|c| c.is_dir)
        .map(|c| {
            json!({
                "name": c.name,
                "relPath": c.rel_path,
                "noteCount": c.note_count,
                "prefixCode": c.prefix_code,
                "colorHex": c.color_hex,
                "textColorHex": c.text_color_hex,
                "iconName": c.icon_name,
            })
        })
        .collect();

    let user_name = if !cfg_username.is_empty() {
        cfg_username
    } else {
        env::var("USER").unwrap_or_else(|_| "user".to_string())
    };
    let vault_name = if !cfg_vault_name.is_empty() {
        cfg_vault_name
    } else {
        vault_canon
            .file_name()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_else(|| "vault".to_string())
    };

    let heatmap = compute_activity_heatmap(&notes, now_secs);
    let heatmap_extended = compute_activity_heatmap_days(&notes, now_secs, 364);
    let today_journal = if let Some(jn) = notes.iter().find(|n| n.journal_date.as_deref() == Some(today_iso.as_str())) {
        let mood = jn.frontmatter.get("mood").cloned().unwrap_or_default();
        let energy = jn.frontmatter.get("energy").cloned().unwrap_or_default();
        let weight = jn
            .frontmatter
            .get("weight")
            .or_else(|| jn.frontmatter.get("body_weight"))
            .or_else(|| jn.frontmatter.get("bodyweight"))
            .cloned()
            .unwrap_or_default();
        let has_weight = jn.frontmatter.contains_key("weight")
            || jn.frontmatter.contains_key("body_weight")
            || jn.frontmatter.contains_key("bodyweight");
        json!({
            "date": today_iso,
            "exists": true,
            "relPath": jn.rel_path,
            "mood": mood,
            "energy": energy,
            "weight": weight,
            "hasMood": jn.frontmatter.contains_key("mood"),
            "hasEnergy": jn.frontmatter.contains_key("energy"),
            "hasWeight": has_weight,
        })
    } else {
        json!({
            "date": today_iso,
            "exists": false,
            "relPath": "",
            "mood": "",
            "energy": "",
            "weight": "",
            "hasMood": false,
            "hasEnergy": false,
            "hasWeight": false,
        })
    };
    let daily_schedule = parse_vault_daily_schedule(
        &vault_canon,
        &cfg_callout_path,
        &cfg_schedule_heading,
        &cfg_exercise_heading,
        &cfg_cardio_heading,
        now_secs,
    );
    let mut all_weekdays_schedule = serde_json::Map::new();
    for wd in 0..7 {
        let sched = parse_vault_daily_schedule_for_weekday(
            &vault_canon,
            &cfg_callout_path,
            &cfg_schedule_heading,
            &cfg_exercise_heading,
            &cfg_cardio_heading,
            wd,
        );
        all_weekdays_schedule.insert(weekday_name(wd).to_ascii_lowercase(), sched);
    }
    let vault_hotkeys = read_vault_obsidian_hotkeys(&vault_canon);

    // Build Homepage Local Graph (centered on "Homepage" with radial dandelion spokes to top/recent non-template notes)
    let mut home_nodes = Vec::new();
    let mut home_edges = Vec::new();
    home_nodes.push(json!({
        "id": "__homepage__",
        "title": "Homepage",
        "relPath": "Homepage.md",
        "colorHex": "#8dc9d6",
        "hop": 0,
        "isHub": true,
        "x": 0.5,
        "y": 0.5,
    }));
    let hub_notes: Vec<&ParsedNoteSummary> = sorted_notes.iter().take(12).collect();
    let hub_count = hub_notes.len().max(1) as f64;
    for (pos, h_note) in hub_notes.iter().enumerate() {
        let angle = (pos as f64 / hub_count) * std::f64::consts::TAU - std::f64::consts::FRAC_PI_2;
        let radius = if pos % 2 == 0 { 0.29 } else { 0.36 };
        let nx = 0.5 + radius * angle.cos();
        let ny = 0.5 + radius * angle.sin();
        home_nodes.push(json!({
            "id": h_note.rel_path,
            "title": h_note.title,
            "relPath": h_note.rel_path,
            "colorHex": "#7bb5c1",
            "hop": 1,
            "isHub": false,
            "x": (nx * 10000.0).round() / 10000.0,
            "y": (ny * 10000.0).round() / 10000.0,
        }));
        home_edges.push(json!({
            "source": "__homepage__",
            "target": h_note.rel_path,
        }));
    }

    let mut payload = json!({
        "ok": true,
        "vaultPath": vault_canon.to_string_lossy(),
        "vaultName": vault_name,
        "tree": tree,
        "files": flat_files,
        "tags": tags_list,
        "graph": graph,
        "homepageLocalGraph": {
            "nodes": home_nodes,
            "edges": home_edges,
        },
        "recentNotes": recent_notes,
        "topFolders": top_folders,
        "dailySchedule": daily_schedule,
        "allWeekdaysSchedule": all_weekdays_schedule,
        "todayJournal": today_journal,
        "financeSummary": finance_summary,
        "vaultHotkeys": vault_hotkeys,
        "homepageCoverUrl": homepage_cover_url,
        "homepagePhotoUrl": if homepage_photo_url.is_empty() { homepage_cover_url.clone() } else { homepage_photo_url },
        "weatherLocation": cfg_weather_loc,
        "globeSettings": Value::Object(cfg_globe_settings),
        "collections": {
            "movies": col_movies,
            "tvSeries": col_tvseries.clone(),
            "tvseries": col_tvseries,
            "games": col_games,
            "websites": col_websites,
            "cornell": col_cornell,
            "zettelkasten": col_zettelkasten,
            "places": col_places,
            "books": col_books,
            "recipes": col_recipes,
            "exercises": col_exercises,
            "clippings": col_clippings,
            "finance": col_finance,
            "contacts": col_contacts,
        },
        "stats": {
            "userHost": format!("{}@{}", user_name, vault_name.to_ascii_lowercase()),
            "noteCount": notes.len(),
            "journalCount": journal_count,
            "bookCount": book_count,
            "tagCount": tags_list.len(),
            "openTasks": open_tasks,
            "doneTasks": done_tasks,
            "imageCount": image_count,
            "codeCount": code_count,
            "externalCount": external_count,
            "vaultAgeDays": vault_age_days,
            "vaultAgeFormatted": vault_age_formatted,
            "activityHeatmap": heatmap,
            "activityHeatmapExtended": heatmap_extended,
            "weatherLocation": cfg_weather_loc,
            "cacheHits": cache_stats.0,
            "parsedNotes": cache_stats.1,
        }
    });
    if let Some(cache_path_str) = cache_file_opt.map(|s| s.trim()).filter(|s| !s.is_empty()) {
        let ui_cache_path = ui_sidecar_cache_path(cache_path_str);
        if !ui_cache_path.is_empty() {
            let _ = write_json_cache_atomically(&ui_cache_path, &payload);
        }
        if let Some(obj) = payload.as_object_mut() {
            obj.insert("_scanSignature".to_string(), Value::String(scan_signature));
            if let Ok(entries_json) = serde_json::to_value(&next_cache) {
                obj.insert("_cachedEntries".to_string(), entries_json);
            }
        }
        let _ = write_json_cache_atomically(cache_path_str, &payload);
        if let Some(obj) = payload.as_object_mut() {
            obj.remove("_scanSignature");
            obj.remove("_cachedEntries");
        }
    }
    Ok(payload)
}

pub fn cmd_read(vault_str: &str, rel_str: &str) -> Result<Value, String> {
    let vault_canon = resolve_vault_root(vault_str)?;
    let (target_path, rel_norm) = resolve_inside_vault(&vault_canon, rel_str, true)?;
    let meta = fs::metadata(&target_path).map_err(|e| format!("Cannot stat '{}': {}", rel_norm, e))?;
    if !meta.is_file() {
        return Err(format!("'{}' is not a regular file", rel_norm));
    }
    let size_bytes = meta.len();
    let mtime_secs = meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let ext = target_path
        .extension()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default();
    let stem = target_path
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default();
    let (cat_enum, lang) = classify_extension(&ext);
    let abs_str = target_path.to_string_lossy().to_string();

    match cat_enum {
        FileCategory::External => Ok(json!({
            "ok": true,
            "category": "external",
            "language": "external",
            "relPath": rel_norm,
            "absPath": abs_str,
            "title": stem,
            "ext": ext,
            "sizeBytes": size_bytes,
            "mtimeSecs": mtime_secs,
        })),
        FileCategory::Image => Ok(json!({
            "ok": true,
            "category": "image",
            "language": "image",
            "relPath": rel_norm,
            "absPath": abs_str,
            "fileUrl": format!("file://{}", abs_str),
            "title": stem,
            "ext": ext,
            "sizeBytes": size_bytes,
            "mtimeSecs": mtime_secs,
        })),
        FileCategory::Code => {
            let bytes = fs::read(&target_path).map_err(|e| format!("Cannot read '{}': {}", rel_norm, e))?;
            let digest = sha256_hex(&bytes);
            let content = String::from_utf8_lossy(&bytes).to_string();
            let line_count = content.lines().count();
            Ok(json!({
                "ok": true,
                "category": "code",
                "language": lang,
                "relPath": rel_norm,
                "absPath": abs_str,
                "title": target_path.file_name().map(|s| s.to_string_lossy().to_string()).unwrap_or(stem),
                "ext": ext,
                "sizeBytes": size_bytes,
                "mtimeSecs": mtime_secs,
                "sha256": digest,
                "content": content,
                "lineCount": line_count,
            }))
        }
        FileCategory::Markdown => {
            let bytes = fs::read(&target_path).map_err(|e| format!("Cannot read '{}': {}", rel_norm, e))?;
            let digest = sha256_hex(&bytes);
            let content = String::from_utf8_lossy(&bytes).to_string();
            let lines: Vec<String> = content.lines().map(|s| s.to_string()).collect();
            let (frontmatter, mut tags, aliases, body_start) = parse_frontmatter(&lines);
            let (mut blocks, outline, flashcards, open_tasks, done_tasks) = parse_blocks(&lines, body_start);

            for b in &blocks {
                for t in &b.tags {
                    if !tags.contains(t) {
                        tags.push(t.clone());
                    }
                }
            }

            // Only use H1 (# Heading) that is not a generic template section as fallback before filename stem
            let title = frontmatter
                .get("title")
                .or_else(|| frontmatter.get("name"))
                .cloned()
                .filter(|s| !s.is_empty() && !s.contains("<%"))
                .or_else(|| {
                    outline
                        .iter()
                        .find(|h| {
                            h.level == 1
                                && !h.text.is_empty()
                                && !matches!(h.text.as_str(), "Day Planner" | "Daily Schedule" | "Daily Log")
                                && !h.text.contains("<%")
                                && !h.text.ends_with('-')
                        })
                        .map(|h| h.text.clone())
                })
                .unwrap_or_else(|| stem.clone());

            // Scan vault notes to compute Local Graph, Linked Backlinks, Unlinked Mentions, and Asset URLs
            let mut flat_files = Vec::new();
            let mut notes = Vec::new();
            let _ = scan_directory_recursive(&vault_canon, &vault_canon, &mut flat_files, &mut notes);
            let lookup = build_note_lookup(&notes);

            // Resolve inline image blocks and dossier assets via O(1) AssetLookupIndex
            let asset_index = AssetLookupIndex::from_flat_files(&flat_files);
            for b in &mut blocks {
                if b.kind == "image" {
                    b.lang = resolve_vault_asset_url_with_index(&vault_canon, &b.text, &asset_index);
                }
            }

            let first_snippet = blocks
                .iter()
                .find(|b| b.kind == "paragraph" || b.kind == "callout")
                .map(|b| b.text.as_str())
                .unwrap_or("");
            let note_kind = classify_note_kind(&rel_norm, &stem, &title, &frontmatter, &tags).to_string();
            let dossier = build_note_dossier_with_index(
                &vault_canon,
                &note_kind,
                &rel_norm,
                &title,
                &frontmatter,
                first_snippet,
                &asset_index,
            );

            // If a frontmatter-driven note (Movie, TV Series, Place, etc.) has 0 body blocks, synthesize overview blocks
            if blocks.is_empty() && !frontmatter.is_empty() {
                if let Some(plot) = frontmatter.get("plot").or_else(|| frontmatter.get("description")) {
                    let clean_plot = strip_wikilink_brackets(plot);
                    if !clean_plot.is_empty() {
                        blocks.push(BlockItem {
                            id: 0,
                            kind: "callout".to_string(),
                            level: 0,
                            indent: 0,
                            line_start: 1,
                            line_end: lines.len().max(1),
                            fold_end_line: lines.len().max(1),
                            foldable: false,
                            todo_state: String::new(),
                            callout_type: "INFO".to_string(),
                            title: "Synopsis".to_string(),
                            lang: String::new(),
                            text: clean_plot.clone(),
                            raw_text: clean_plot.clone(),
                            rich_html: render_inline_rich_html(plot),
                            wikilinks: extract_wikilinks_from_line(plot).into_iter().map(|(t, _)| t).collect(),
                            tags: Vec::new(),
                            table_headers: Vec::new(),
                            table_rows: Vec::new(),
                        });
                    }
                }
            }

            // Build Custom View domain-specific payloads
            let journal_view = if note_kind == "journal" {
                let now_secs = SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .map(|d| d.as_secs())
                    .unwrap_or(0);
                let j_date = detect_journal_date_from_path(&rel_norm, &stem).unwrap_or_else(|| {
                    let (y, m, d) = civil_from_days((now_secs / 86400) as i64);
                    format!("{:04}-{:02}-{:02}", y, m, d)
                });
                let parts: Vec<&str> = j_date.split('-').collect();
                let (jy, jm, jd) = if parts.len() == 3 {
                    (
                        parts[0].parse::<i32>().unwrap_or(2026),
                        parts[1].parse::<u32>().unwrap_or(1),
                        parts[2].parse::<u32>().unwrap_or(1),
                    )
                } else {
                    (2026, 1, 1)
                };
                let j_days = days_from_civil(jy, jm, jd);
                let (prev_y, prev_m, prev_d) = civil_from_days(j_days - 1);
                let (next_y, next_m, next_d) = civil_from_days(j_days + 1);
                let prev_iso = format!("{:04}-{:02}-{:02}", prev_y, prev_m, prev_d);
                let next_iso = format!("{:04}-{:02}-{:02}", next_y, next_m, next_d);
                let prev_path = notes
                    .iter()
                    .find(|n| n.journal_date.as_deref() == Some(prev_iso.as_str()))
                    .map(|n| n.rel_path.clone())
                    .unwrap_or_default();
                let next_path = notes
                    .iter()
                    .find(|n| n.journal_date.as_deref() == Some(next_iso.as_str()))
                    .map(|n| n.rel_path.clone())
                    .unwrap_or_default();

                let wd = weekday_monday_zero(jy, jm, jd);
                let wd_name = weekday_name(wd);
                let m_name = month_name(jm);
                let start_of_year = days_from_civil(jy, 1, 1);
                let end_of_year = days_from_civil(jy + 1, 1, 1);
                let day_of_year = (j_days - start_of_year + 1).max(1) as f64;
                let total_year_days = (end_of_year - start_of_year).max(365) as f64;
                let year_pct = ((day_of_year / total_year_days) * 100.0).round() as i32;
                let dim = days_in_month(jy, jm).max(1) as f64;
                let month_pct = (((jd as f64) / dim) * 100.0).round() as i32;
                let week_pct = ((((wd + 1) as f64) / 7.0) * 100.0).round() as i32;

                let seed = (jy as usize)
                    .wrapping_mul(372)
                    .wrapping_add((jm as usize) * 31)
                    .wrapping_add(jd as usize);
                let (default_q, default_a) = pick_vault_quote_for_seed(&vault_canon, seed);
                let quote_text = frontmatter
                    .get("quote")
                    .cloned()
                    .filter(|s| !s.is_empty())
                    .unwrap_or(default_q);
                let quote_author = frontmatter
                    .get("quote_author")
                    .cloned()
                    .filter(|s| !s.is_empty())
                    .unwrap_or(default_a);

                let snap_sched = parse_vault_daily_schedule_for_weekday(
                    &vault_canon,
                    "90_System/97_Daily_Schedule",
                    "Daily Schedule",
                    "Calisthenics",
                    "Cardio",
                    wd,
                );

                // Extract Daily Log body lines (preferring `## Daily Log` / `## Notes & Log` section, or after `## Day Planner` divider)
                let is_daily_log_heading = |title: &str| -> bool {
                    let t = title.trim().trim_start_matches('#').trim();
                    t.eq_ignore_ascii_case("Daily Log")
                        || t.eq_ignore_ascii_case("Notes & Log")
                        || t.eq_ignore_ascii_case("Notes and Log")
                };
                let mut log_start_line = body_start + 1;
                if let Some((dl_idx, dl_block)) = blocks
                    .iter()
                    .enumerate()
                    .find(|(_, b)| b.kind == "heading" && is_daily_log_heading(&b.title))
                {
                    if let Some(next_b) = blocks.get(dl_idx + 1) {
                        if next_b.kind == "divider" || next_b.kind == "hr" {
                            log_start_line = next_b.line_end + 1;
                        } else {
                            log_start_line = next_b.line_start;
                        }
                    } else {
                        log_start_line = dl_block.line_end + 1;
                    }
                } else {
                    let dp_idx = blocks
                        .iter()
                        .position(|b| b.kind == "heading" && b.title.trim().eq_ignore_ascii_case("Day Planner"))
                        .unwrap_or(0);
                    for (idx, b) in blocks.iter().enumerate().skip(dp_idx) {
                        if b.kind == "divider" || b.kind == "hr" {
                            if let Some(next_b) = blocks.get(idx + 1) {
                                log_start_line = next_b.line_start;
                            } else {
                                log_start_line = b.line_end + 1;
                            }
                            break;
                        }
                    }
                }
                let log_lines: Vec<String> = if log_start_line >= 1 && log_start_line <= lines.len() {
                    lines[log_start_line - 1..]
                        .iter()
                        .filter(|l| {
                            let t = l.trim();
                            let is_redundant_heading = t.starts_with('#') && is_daily_log_heading(t);
                            !is_redundant_heading
                                && t != "#Daily-notes"
                                && t != "---"
                                && !t.starts_with("![[90_System/93_Configuration/Custom_Views/Journal/")
                        })
                        .cloned()
                        .collect()
                } else {
                    Vec::new()
                };

                // Find historical notes on this month-day in earlier years
                let mm_dd = format!("-{:02}-{:02}", jm, jd);
                let on_this_day: Vec<Value> = notes
                    .iter()
                    .filter(|n| {
                        n.rel_path != rel_norm
                            && n.journal_date
                                .as_deref()
                                .map(|d| d.ends_with(&mm_dd))
                                .unwrap_or(false)
                    })
                    .map(|n| {
                        json!({
                            "relPath": n.rel_path,
                            "title": n.title,
                            "date": n.journal_date,
                            "snippet": n.snippet,
                        })
                    })
                    .collect();

                json!({
                    "dateIso": j_date,
                    "isoDate": j_date,
                    "year": jy,
                    "month": jm,
                    "day": jd,
                    "weekday": wd_name,
                    "monthName": m_name,
                    "displayDate": format!("{}, {} {:02}, {:04}", wd_name, m_name, jd, jy),
                    "prevDateIso": prev_iso,
                    "prevDate": prev_iso,
                    "nextDateIso": next_iso,
                    "nextDate": next_iso,
                    "prevJournalPath": prev_path,
                    "nextJournalPath": next_path,
                    "yearProgress": year_pct,
                    "monthProgress": month_pct,
                    "weekProgress": week_pct,
                    "quote": quote_text,
                    "quoteText": quote_text,
                    "quoteAuthor": quote_author,
                    "mood": frontmatter.get("mood").cloned().unwrap_or_default(),
                    "energy": frontmatter.get("energy").cloned().unwrap_or_default(),
                    "hasMood": frontmatter.contains_key("mood"),
                    "hasEnergy": frontmatter.contains_key("energy"),
                    "hasWeight": frontmatter.contains_key("weight")
                        || frontmatter.contains_key("body_weight")
                        || frontmatter.contains_key("bodyweight"),
                    "weather": frontmatter.get("weather").cloned().unwrap_or_default(),
                    "reflection": frontmatter.get("reflection").cloned().unwrap_or_default(),
                    "weight": frontmatter
                        .get("weight")
                        .or_else(|| frontmatter.get("body_weight"))
                        .or_else(|| frontmatter.get("bodyweight"))
                        .cloned()
                        .unwrap_or_default(),
                    "schedule": snap_sched,
                    "snapshotSchedule": snap_sched,
                    "dailyLogLineStart": log_start_line,
                    "dailyLogLineEnd": lines.len().max(log_start_line),
                    "dailyLogText": log_lines.join("\n").trim().to_string(),
                    "dailyLogRichHtml": render_markdown_block_rich_html(log_lines.join("\n").trim()),
                    "onThisDay": on_this_day,
                })
            } else {
                Value::Null
            };

            let cornell_view = if note_kind == "cornell" {
                let mut cues: Vec<Value> = Vec::new();
                let mut summary_items: Vec<String> = Vec::new();
                let mut objectives: Vec<String> = Vec::new();
                let mut recall_questions: Vec<String> = Vec::new();
                let mut review_schedule: Vec<String> = Vec::new();
                let mut body_course = String::new();
                let mut body_topic = String::new();
                let mut body_date = String::new();
                let mut body_source = String::new();
                let mut body_status = String::new();
                let mut h2_section = "";
                let mut in_objectives_inline = false;
                let mut in_cornell_fence = false;
                let mut current_cue: Option<(usize, String, String, String, String, String, Vec<String>, usize)> = None;

                let classify_cornell_cue = |raw_heading: &str| -> (String, String, String, String) {
                    let t = raw_heading.trim();
                    let prefixes: &[(&str, &str, &str, &str)] = &[
                        ("? ", "CORNELL_QUESTION", "?", "Question"),
                        ("!", "CORNELL_IMPORTANT", "!", "Important"),
                        ("! ", "CORNELL_IMPORTANT", "!", "Important"),
                        (". ", "CORNELL_KEYPOINT", "•", "Key Point"),
                        ("E- ", "CORNELL_EXAMPLE", "E", "Example"),
                        ("e- ", "CORNELL_EXAMPLE", "E", "Example"),
                        ("V- ", "CORNELL_VERIFIED", "✓", "Verified"),
                        ("v- ", "CORNELL_VERIFIED", "✓", "Verified"),
                        ("X- ", "CORNELL_MISTAKE", "✕", "Common Mistake"),
                        ("x- ", "CORNELL_MISTAKE", "✕", "Common Mistake"),
                        ("R- ", "CORNELL_RELATED", "↗", "Related"),
                        ("r- ", "CORNELL_RELATED", "↗", "Related"),
                        ("* ", "CORNELL_FEYNMAN", "★", "Feynman"),
                    ];
                    for &(pref, ctype, marker, label) in prefixes {
                        if let Some(rest) = t.strip_prefix(pref) {
                            let clean = rest.trim();
                            let title = if clean.is_empty() || clean.eq_ignore_ascii_case(label) {
                                match ctype {
                                    "CORNELL_QUESTION" => "Guiding Question".to_string(),
                                    "CORNELL_IMPORTANT" => "Key Concept".to_string(),
                                    "CORNELL_KEYPOINT" => "Core Takeaway".to_string(),
                                    "CORNELL_EXAMPLE" => "Concrete Example".to_string(),
                                    "CORNELL_VERIFIED" => "Verified Evidence".to_string(),
                                    "CORNELL_MISTAKE" => "Common Misconception".to_string(),
                                    "CORNELL_RELATED" => "Related Concept".to_string(),
                                    "CORNELL_FEYNMAN" => "Feynman Simplification".to_string(),
                                    _ => label.to_string(),
                                }
                            } else {
                                clean.to_string()
                            };
                            return (ctype.to_string(), marker.to_string(), label.to_string(), title);
                        }
                    }
                    match t {
                        "?" => ("CORNELL_QUESTION".to_string(), "?".to_string(), "Question".to_string(), "Guiding Question".to_string()),
                        "!" => ("CORNELL_IMPORTANT".to_string(), "!".to_string(), "Important".to_string(), "Key Concept".to_string()),
                        "." => ("CORNELL_KEYPOINT".to_string(), "•".to_string(), "Key Point".to_string(), "Core Takeaway".to_string()),
                        s if s.eq_ignore_ascii_case("E-") => ("CORNELL_EXAMPLE".to_string(), "E".to_string(), "Example".to_string(), "Concrete Example".to_string()),
                        s if s.eq_ignore_ascii_case("V-") => ("CORNELL_VERIFIED".to_string(), "✓".to_string(), "Verified".to_string(), "Verified Evidence".to_string()),
                        s if s.eq_ignore_ascii_case("X-") => ("CORNELL_MISTAKE".to_string(), "✕".to_string(), "Common Mistake".to_string(), "Common Misconception".to_string()),
                        s if s.eq_ignore_ascii_case("R-") => ("CORNELL_RELATED".to_string(), "↗".to_string(), "Related".to_string(), "Related Concept".to_string()),
                        "*" => ("CORNELL_FEYNMAN".to_string(), "★".to_string(), "Feynman".to_string(), "Feynman Simplification".to_string()),
                        other => ("CORNELL_CUE".to_string(), "•".to_string(), "Cue".to_string(), other.to_string()),
                    }
                };

                let flush_cue = |cue_opt: &mut Option<(usize, String, String, String, String, String, Vec<String>, usize)>, out: &mut Vec<Value>| {
                    if let Some((cid, ctype, marker, label, raw_title, clean_cue, body_parts, lstart)) = cue_opt.take() {
                        let trimmed_parts: Vec<String> = body_parts
                            .into_iter()
                            .filter(|l| {
                                let t = l.trim();
                                t != "-" && t != "*" && t != "- [ ]"
                            })
                            .collect();
                        let notes_text = trimmed_parts.join("\n").trim().to_string();
                        let display_notes = if notes_text.is_empty() {
                            String::new()
                        } else {
                            notes_text.clone()
                        };
                        let rich_html = if display_notes.is_empty() {
                            String::new()
                        } else {
                            render_markdown_block_rich_html(&display_notes)
                        };
                        let title_str = if clean_cue.is_empty() || clean_cue.eq_ignore_ascii_case(&label) {
                            raw_title
                        } else {
                            clean_cue.clone()
                        };
                        out.push(json!({
                            "id": cid,
                            "type": ctype,
                            "marker": marker,
                            "label": label,
                            "title": strip_wikilink_brackets(&title_str),
                            "cue": strip_wikilink_brackets(&clean_cue),
                            "cueRichHtml": render_inline_rich_html(&title_str),
                            "text": display_notes,
                            "notes": display_notes,
                            "richHtml": rich_html,
                            "lineStart": lstart,
                        }));
                    }
                };

                if body_start < lines.len() {
                    for (offset, raw_line) in lines[body_start..].iter().enumerate() {
                        let line_no = body_start + offset + 1;
                        let mut s = raw_line.trim();
                        while let Some(stripped) = s.strip_prefix('>') {
                            s = stripped.trim();
                        }
                        if s.is_empty() {
                            continue;
                        }
                        if s.starts_with("```") {
                            let lang = s.trim_start_matches('`').trim();
                            if !in_cornell_fence && lang.eq_ignore_ascii_case("cornell") {
                                flush_cue(&mut current_cue, &mut cues);
                                in_cornell_fence = true;
                                continue;
                            } else if in_cornell_fence {
                                flush_cue(&mut current_cue, &mut cues);
                                in_cornell_fence = false;
                                continue;
                            }
                        }
                        if in_cornell_fence {
                            if s == "---" || s == "***" || s == "___" {
                                flush_cue(&mut current_cue, &mut cues);
                                continue;
                            }
                            if let Some(sum_rest) = s.strip_prefix("summary:").or_else(|| s.strip_prefix("Summary:")) {
                                flush_cue(&mut current_cue, &mut cues);
                                h2_section = "summary";
                                let trimmed_sum = sum_rest.trim();
                                if !trimmed_sum.is_empty() {
                                    summary_items.push(trimmed_sum.to_string());
                                }
                                continue;
                            }
                            if let Some((cue_lhs, note_rhs)) = s.split_once("::") {
                                flush_cue(&mut current_cue, &mut cues);
                                let cue_txt = cue_lhs.trim();
                                let note_txt = note_rhs.trim();
                                let (ctype, marker, label, clean_cue) = classify_cornell_cue(cue_txt);
                                let next_id = cues.len() + 1;
                                let mut parts = Vec::new();
                                if !note_txt.is_empty() {
                                    parts.push(note_txt.to_string());
                                }
                                current_cue = Some((
                                    next_id,
                                    ctype,
                                    marker,
                                    label,
                                    cue_txt.to_string(),
                                    clean_cue,
                                    parts,
                                    line_no,
                                ));
                                continue;
                            }
                        }
                        if s.starts_with("![[") && s.contains("Custom_Views/") {
                            continue;
                        }
                        if s.starts_with("[!") {
                            let low_c = s.to_ascii_lowercase();
                            if low_c.starts_with("[!summary]") {
                                flush_cue(&mut current_cue, &mut cues);
                                h2_section = "summary";
                                in_objectives_inline = false;
                            } else if (low_c.starts_with("[!note]") || low_c.starts_with("[!question]"))
                                && low_c.contains("cue")
                            {
                                flush_cue(&mut current_cue, &mut cues);
                                h2_section = "callout_cues";
                                in_objectives_inline = false;
                            } else if low_c.starts_with("[!info]") && low_c.contains("note") {
                                h2_section = "callout_notes";
                                in_objectives_inline = false;
                                if current_cue.is_none() && cues.is_empty() {
                                    let (ctype, marker, label, clean_cue) =
                                        classify_cornell_cue("Lecture Notes");
                                    current_cue = Some((
                                        1,
                                        ctype,
                                        marker,
                                        label,
                                        "Lecture Notes".to_string(),
                                        clean_cue,
                                        Vec::new(),
                                        line_no,
                                    ));
                                }
                            }
                            continue;
                        }
                        if s == "---" || s == "***" || s == "___" {
                            flush_cue(&mut current_cue, &mut cues);
                            in_objectives_inline = false;
                            continue;
                        }
                        let s_unbulleted = s
                            .strip_prefix("- [ ] ")
                            .or_else(|| s.strip_prefix("- [x] "))
                            .or_else(|| s.strip_prefix("- [X] "))
                            .or_else(|| s.strip_prefix("- "))
                            .or_else(|| s.strip_prefix("* "))
                            .or_else(|| s.strip_prefix("+ "))
                            .unwrap_or(s)
                            .trim();
                        let s_low = s_unbulleted.to_ascii_lowercase();
                        if s_low.starts_with("**course:**") || s_low.starts_with("course:") {
                            let val = s_unbulleted
                                .split_once(':')
                                .map(|(_, v)| v.trim().trim_start_matches('*').trim())
                                .unwrap_or("");
                            let clean_val = strip_wikilink_brackets(val).trim().to_string();
                            if !clean_val.is_empty() && body_course.is_empty() {
                                body_course = clean_val;
                            }
                            in_objectives_inline = false;
                            continue;
                        }
                        if s_low.starts_with("**topic:**") || s_low.starts_with("topic:") {
                            let val = s_unbulleted
                                .split_once(':')
                                .map(|(_, v)| v.trim().trim_start_matches('*').trim())
                                .unwrap_or("");
                            let clean_val = strip_wikilink_brackets(val).trim().to_string();
                            if !clean_val.is_empty() && body_topic.is_empty() {
                                body_topic = clean_val;
                            }
                            in_objectives_inline = false;
                            continue;
                        }
                        if s_low.starts_with("**date:**") || (h2_section == "metadata" && s_low.starts_with("date:")) {
                            let val = s_unbulleted
                                .split_once(':')
                                .map(|(_, v)| v.trim().trim_start_matches('*').trim())
                                .unwrap_or("");
                            let clean_val = strip_wikilink_brackets(val).trim().to_string();
                            if !clean_val.is_empty() && body_date.is_empty() {
                                body_date = clean_val;
                            }
                            continue;
                        }
                        if s_low.starts_with("**source:**") || (h2_section == "metadata" && s_low.starts_with("source:")) {
                            let val = s_unbulleted
                                .split_once(':')
                                .map(|(_, v)| v.trim().trim_start_matches('*').trim())
                                .unwrap_or("");
                            let clean_val = strip_wikilink_brackets(val).trim().to_string();
                            if !clean_val.is_empty() && body_source.is_empty() {
                                body_source = clean_val;
                            }
                            continue;
                        }
                        if s_low.starts_with("**status:**") || (h2_section == "metadata" && s_low.starts_with("status:")) {
                            let val = s_unbulleted
                                .split_once(':')
                                .map(|(_, v)| v.trim().trim_start_matches('*').trim())
                                .unwrap_or("");
                            let clean_val = strip_wikilink_brackets(val).trim().to_string();
                            if !clean_val.is_empty() && body_status.is_empty() {
                                body_status = clean_val;
                            }
                            continue;
                        }
                        if s_low.starts_with("**objectives:**") || s_low.starts_with("**learning objectives:**") {
                            in_objectives_inline = true;
                            let rest = s_unbulleted
                                .split_once(':')
                                .map(|(_, v)| v.trim().trim_start_matches('*').trim())
                                .unwrap_or("");
                            let clean_rest = strip_wikilink_brackets(rest).trim().to_string();
                            if !clean_rest.is_empty() && clean_rest != "-" {
                                objectives.push(clean_rest);
                            }
                            continue;
                        }

                        if s.starts_with('#') {
                            let hashes = s.chars().take_while(|&c| c == '#').count();
                            let h_title = s[hashes..].trim();
                            let h_low = h_title.to_ascii_lowercase();
                            in_objectives_inline = false;
                            if hashes <= 2 {
                                let is_notes_h2 = h_low == "notes" || h_low == "lecture notes";
                                let cue_has_empty_notes = current_cue
                                    .as_ref()
                                    .map(|c| c.6.is_empty())
                                    .unwrap_or(false);
                                if !(is_notes_h2 && cue_has_empty_notes) {
                                    flush_cue(&mut current_cue, &mut cues);
                                }
                                if h_low.contains("session metadata") || h_low == "metadata" {
                                    h2_section = "metadata";
                                } else if h_low.contains("next review") || h_low.contains("review schedule") {
                                    h2_section = "review";
                                } else if h_low.contains("summary") {
                                    h2_section = "summary";
                                } else if h_low.contains("learning objective") || h_low == "objectives" || h_low.contains("learning goal") {
                                    h2_section = "objectives";
                                } else if h_low.contains("active recall") || h_low.contains("review question") || h_low.contains("self-test") {
                                    h2_section = "recall";
                                } else if h_low.contains("cue") || h_low.contains("note") || h_low.contains("key point") {
                                    h2_section = "cues";
                                } else {
                                    h2_section = "cues";
                                }
                                continue;
                            } else if hashes == 3 {
                                flush_cue(&mut current_cue, &mut cues);
                                if h_low.contains("session metadata") || h_low == "metadata" {
                                    h2_section = "metadata";
                                    continue;
                                }
                                if h_low.contains("review schedule") || h_low.contains("next review") {
                                    h2_section = "review";
                                    continue;
                                }
                                if h_low.contains("summary") {
                                    h2_section = "summary";
                                    continue;
                                }
                                if h_low.contains("learning goal") || h_low.contains("learning objective") || h2_section == "objectives" {
                                    h2_section = "objectives";
                                    continue;
                                }
                                if h_low.contains("self-test") || h_low.contains("active recall") || h2_section == "recall" {
                                    h2_section = "recall";
                                    continue;
                                }
                                if h2_section == "metadata" || h2_section == "review" {
                                    continue;
                                }
                                let (ctype, marker, label, clean_cue) = classify_cornell_cue(h_title);
                                let next_id = cues.len() + 1;
                                current_cue = Some((
                                    next_id,
                                    ctype,
                                    marker,
                                    label,
                                    h_title.to_string(),
                                    clean_cue,
                                    Vec::new(),
                                    line_no,
                                ));
                                continue;
                            }
                        }

                        if in_objectives_inline {
                            if s.starts_with("- ") || s.starts_with("* ") {
                                let item = strip_wikilink_brackets(s[2..].trim());
                                if !item.is_empty() {
                                    objectives.push(item);
                                }
                                continue;
                            } else if s == "-" || s == "*" {
                                continue;
                            } else {
                                in_objectives_inline = false;
                            }
                        }

                        if h2_section == "callout_cues" && current_cue.is_none() && (s.starts_with("- ") || s.starts_with("* ")) {
                            let bullet_text = s[2..].trim();
                            if !bullet_text.is_empty() {
                                let (ctype, marker, label, clean_cue) = classify_cornell_cue(bullet_text);
                                let next_id = cues.len() + 1;
                                current_cue = Some((
                                    next_id,
                                    ctype,
                                    marker,
                                    label,
                                    bullet_text.to_string(),
                                    clean_cue,
                                    Vec::new(),
                                    line_no,
                                ));
                                continue;
                            }
                        }

                        if let Some((_, _, _, _, _, _, ref mut parts, _)) = current_cue {
                            parts.push(s.to_string());
                        } else if h2_section == "summary" {
                            if s != "-" && s != "*" {
                                summary_items.push(s.to_string());
                            }
                        } else if h2_section == "objectives" {
                            let item = s
                                .trim_start_matches("- [ ] ")
                                .trim_start_matches("- [x] ")
                                .trim_start_matches("- [X] ")
                                .trim_start_matches("- ")
                                .trim_start_matches("* ")
                                .trim();
                            if !item.is_empty() && item != "-" && item != "*" && item != "[ ]" {
                                objectives.push(strip_wikilink_brackets(item));
                            }
                        } else if h2_section == "recall" {
                            let item = s
                                .trim_start_matches(|c: char| c.is_ascii_digit() || c == '.' || c == ')')
                                .trim_start_matches("- ")
                                .trim();
                            if !item.is_empty() && item != "-" {
                                recall_questions.push(strip_wikilink_brackets(item));
                            }
                        } else if h2_section == "review" {
                            let item = s_unbulleted.trim();
                            if !item.is_empty() && item != "-" && item != "*" && !item.ends_with(':') {
                                review_schedule.push(strip_wikilink_brackets(item));
                            }
                        }
                    }
                }
                flush_cue(&mut current_cue, &mut cues);

                let summary_str = summary_items.join("\n").trim().to_string();
                let course_val = {
                    let c = dossier["course"].as_str().unwrap_or("").trim();
                    if !c.is_empty() {
                        c.to_string()
                    } else if !body_course.is_empty() {
                        body_course
                    } else {
                        frontmatter
                            .get("subject")
                            .or_else(|| frontmatter.get("class"))
                            .or_else(|| frontmatter.get("module"))
                            .map(|s| strip_wikilink_brackets(s))
                            .unwrap_or_default()
                    }
                };
                let topic_val = {
                    let t = dossier["topic"].as_str().unwrap_or("").trim();
                    if !t.is_empty() {
                        t.to_string()
                    } else {
                        body_topic
                    }
                };
                let date_val = frontmatter
                    .get("date")
                    .or_else(|| frontmatter.get("created"))
                    .map(|s| strip_wikilink_brackets(s))
                    .filter(|s| !s.is_empty())
                    .unwrap_or_else(|| {
                        let d = dossier["date"].as_str().unwrap_or("").trim();
                        if !d.is_empty() { d.to_string() } else { body_date }
                    });
                let status_val = frontmatter
                    .get("status")
                    .or_else(|| frontmatter.get("stage"))
                    .or_else(|| frontmatter.get("review"))
                    .cloned()
                    .filter(|s| !s.is_empty())
                    .unwrap_or_else(|| {
                        if !body_status.is_empty() { body_status } else { "Draft".to_string() }
                    });
                let source_val = frontmatter
                    .get("source")
                    .map(|s| strip_wikilink_brackets(s))
                    .filter(|s| !s.is_empty())
                    .unwrap_or(body_source);
                let note_type_val = frontmatter
                    .get("type")
                    .or_else(|| frontmatter.get("method"))
                    .map(|s| strip_wikilink_brackets(s))
                    .filter(|s| !s.is_empty())
                    .unwrap_or_else(|| "Cornell".to_string());
                let cue_width_val = frontmatter
                    .get("cornell_cue_width")
                    .and_then(|s| s.trim().parse::<i64>().ok())
                    .map(|w| w.clamp(22, 46))
                    .unwrap_or(30);
                let review_count_val = frontmatter
                    .get("review_count")
                    .or_else(|| frontmatter.get("reviews"))
                    .and_then(|s| s.trim().parse::<i64>().ok())
                    .unwrap_or(0);
                let reviewed_val = frontmatter
                    .get("reviewed")
                    .map(|s| matches!(s.trim().to_ascii_lowercase().as_str(), "true" | "yes" | "1"))
                    .unwrap_or(review_count_val > 0);

                json!({
                    "cueCount": cues.len(),
                    "cues": cues,
                    "pairs": cues,
                    "objectives": objectives,
                    "recallQuestions": recall_questions,
                    "reviewSchedule": review_schedule,
                    "summary": summary_str,
                    "summaryHtml": render_markdown_block_rich_html(&summary_str),
                    "summaryRichHtml": render_markdown_block_rich_html(&summary_str),
                    "course": course_val,
                    "context": course_val,
                    "topic": topic_val,
                    "date": date_val,
                    "status": status_val,
                    "source": source_val,
                    "noteType": note_type_val,
                    "cueWidth": cue_width_val,
                    "reviewCount": review_count_val,
                    "reviewed": reviewed_val,
                    "nextReview": frontmatter.get("next_review").cloned().unwrap_or_default(),
                    "duration": frontmatter.get("duration").cloned().unwrap_or_default(),
                    "understanding": frontmatter.get("understanding").cloned().unwrap_or_default(),
                    "confidence": frontmatter.get("confidence").cloned().unwrap_or_default(),
                })
            } else {
                Value::Null
            };

            let zettelkasten_view = if note_kind == "zettelkasten" {
                let fm_id = frontmatter
                    .get("id")
                    .or_else(|| frontmatter.get("zettel_id"))
                    .or_else(|| frontmatter.get("uid"))
                    .map(|s| strip_wikilink_brackets(s).trim().to_string())
                    .filter(|s| !s.is_empty() && !s.contains("<%"));
                let zettel_id = fm_id
                    .or_else(|| {
                        stem.split_once(" - ")
                            .map(|(id, _)| id.trim().to_string())
                            .filter(|s| !s.is_empty())
                    })
                    .or_else(|| {
                        let digits: String = stem.chars().take_while(|c| c.is_ascii_digit()).collect();
                        if digits.len() >= 8 { Some(digits) } else { None }
                    })
                    .unwrap_or_else(|| "No ID".to_string());
                let clean_title = stem
                    .split_once(" - ")
                    .map(|(_, rest)| rest.trim().to_string())
                    .filter(|s| !s.is_empty())
                    .unwrap_or_else(|| title.clone());
                let raw_zettel_type = frontmatter
                    .get("type")
                    .or_else(|| frontmatter.get("note_type"))
                    .or_else(|| frontmatter.get("kind"))
                    .map(|s| strip_wikilink_brackets(s))
                    .unwrap_or_else(|| "Permanent".to_string());
                let zt_low = raw_zettel_type.to_ascii_lowercase();
                let zettel_type = if (zt_low.contains("permanent") && zt_low.contains("literature") && zt_low.contains("fleeting"))
                    || zt_low.starts_with("permanent")
                {
                    "Permanent".to_string()
                } else if zt_low.contains("literature") {
                    "Literature".to_string()
                } else if zt_low.contains("fleeting") {
                    "Fleeting".to_string()
                } else if raw_zettel_type.trim().is_empty() {
                    "Permanent".to_string()
                } else {
                    raw_zettel_type.trim().to_string()
                };
                let date_val = frontmatter
                    .get("date")
                    .or_else(|| frontmatter.get("created"))
                    .map(|s| strip_wikilink_brackets(s))
                    .filter(|s| !s.trim().is_empty() && !s.contains("<%"))
                    .unwrap_or_else(|| dossier["date"].as_str().unwrap_or("—").to_string());

                let mut sec_map: BTreeMap<String, Vec<String>> = BTreeMap::new();
                let mut ordered_sections: Vec<(String, String, Vec<String>)> = Vec::new();
                let mut cur_sec = "core".to_string();
                let mut cur_heading = "Core Idea".to_string();
                let mut seen_first_h1 = false;

                if body_start < lines.len() {
                    for raw_line in &lines[body_start..] {
                        let t = raw_line.trim();
                        let t_low = t.to_lowercase();
                        if t == "---"
                            || (t.starts_with("![[") && t.contains("Custom_Views/"))
                            || t_low == "<center>end</center>"
                            || t_low == "> [!abstract] ý tưởng chính"
                            || t_low == "> một câu duy nhất mô tả cốt lõi của ghi chú này."
                        {
                            continue;
                        }
                        if t.starts_with("# ") && !t.starts_with("## ") && !seen_first_h1 {
                            seen_first_h1 = true;
                            let h1_text = t[2..].trim();
                            let h1_clean = h1_text.trim_end_matches('-').trim();
                            if h1_clean.is_empty()
                                || h1_text.contains("<%")
                                || h1_clean.eq_ignore_ascii_case(&zettel_id)
                                || h1_clean.eq_ignore_ascii_case(&stem)
                                || h1_clean.eq_ignore_ascii_case(&clean_title)
                                || h1_clean.eq_ignore_ascii_case(&title)
                            {
                                continue;
                            }
                        }
                        if t.starts_with("## ") || t.starts_with("# ") {
                            let h_text = t.trim_start_matches('#').trim().to_string();
                            let low = h_text.to_lowercase();
                            let clean_h = low
                                .trim_matches(|c: char| {
                                    matches!(c, '*' | '_' | ':' | '-' | '–' | '—') || c.is_whitespace()
                                })
                                .trim();
                            // Only treat short structural headings (without internal colons or leading cluster numbers)
                            // as canonical Zettelkasten section delimiters so topic headings like
                            // "## CỤM 6: NỘI DUNG GIÁO DỤC..." or "# 1. Mục tiêu (SMART Goal)" are preserved.
                            let is_structural_heading = !clean_h.contains(':')
                                && clean_h.chars().count() <= 36
                                && !clean_h.chars().next().map_or(false, |c| c.is_ascii_digit());
                            let is_core = is_structural_heading
                                && (clean_h.contains("core")
                                    || clean_h.contains("claim")
                                    || clean_h.contains("thesis")
                                    || clean_h.contains("summary")
                                    || clean_h.contains("idea")
                                    || clean_h.contains("tóm tắt")
                                    || clean_h.contains("tom tat")
                                    || clean_h.contains("ý tưởng")
                                    || clean_h.contains("y tuong")
                                    || clean_h.contains("khái niệm"));
                            let is_content = is_structural_heading
                                && (clean_h.contains("content")
                                    || clean_h.contains("elaborat")
                                    || clean_h.contains("explanation")
                                    || clean_h.contains("argument")
                                    || clean_h.contains("detail")
                                    || clean_h.contains("note")
                                    || clean_h.contains("example")
                                    || clean_h.contains("nội dung")
                                    || clean_h.contains("noi dung")
                                    || clean_h.contains("chi tiết")
                                    || clean_h.contains("diễn giải")
                                    || clean_h.contains("phân tích"));
                            let is_conn = is_structural_heading
                                && (clean_h.contains("context")
                                    || clean_h.contains("connect")
                                    || clean_h.contains("link")
                                    || clean_h.contains("related")
                                    || clean_h.contains("see also")
                                    || clean_h.contains("kết nối")
                                    || clean_h.contains("ket noi")
                                    || clean_h.contains("liên kết")
                                    || clean_h.contains("lien ket")
                                    || clean_h.contains("liên hệ"));
                            let is_refs = is_structural_heading
                                && (clean_h.contains("source")
                                    || clean_h.contains("refer")
                                    || clean_h.contains("citation")
                                    || clean_h.contains("origin")
                                    || clean_h.contains("further")
                                    || clean_h.contains("nguồn")
                                    || clean_h.contains("nguon")
                                    || clean_h.contains("tham khảo")
                                    || clean_h.contains("tài liệu"));

                            if is_core {
                                cur_heading = h_text.clone();
                                cur_sec = "core".to_string();
                            } else if is_content {
                                cur_heading = h_text.clone();
                                cur_sec = "content".to_string();
                            } else if is_conn {
                                cur_heading = h_text.clone();
                                cur_sec = "connections".to_string();
                            } else if is_refs {
                                cur_heading = h_text.clone();
                                cur_sec = "references".to_string();
                            } else {
                                // Custom topic heading inside the active section (core or content):
                                // preserve it inline in exact document order.
                                let normalized_h = if t.starts_with("# ") {
                                    format!("## {}", h_text)
                                } else {
                                    raw_line.clone()
                                };
                                let target_sec = if cur_sec == "connections" || cur_sec == "references" {
                                    "content".to_string()
                                } else {
                                    cur_sec.clone()
                                };
                                sec_map.entry(target_sec.clone()).or_default().push(normalized_h.clone());
                                if let Some((_, _, vec_lines)) = ordered_sections
                                    .iter_mut()
                                    .rev()
                                    .find(|(k, _, _)| k == &target_sec || k.starts_with("custom:"))
                                {
                                    vec_lines.push(normalized_h);
                                } else {
                                    ordered_sections.push((
                                        format!("custom:{}", h_text),
                                        h_text,
                                        vec![normalized_h],
                                    ));
                                }
                                continue;
                            }
                            if !ordered_sections.iter().any(|(k, _, _)| k == &cur_sec) {
                                ordered_sections.push((cur_sec.clone(), cur_heading.clone(), Vec::new()));
                            }
                            continue;
                        }
                        if t == "-" || t == "*" {
                            continue;
                        }
                        sec_map.entry(cur_sec.clone()).or_default().push(raw_line.clone());
                        if let Some((_, _, vec_lines)) = ordered_sections
                            .iter_mut()
                            .rev()
                            .find(|(k, _, _)| k == &cur_sec || k.starts_with("custom:"))
                        {
                            vec_lines.push(raw_line.clone());
                        } else {
                            ordered_sections.push((cur_sec.clone(), cur_heading.clone(), vec![raw_line.clone()]));
                        }
                    }
                }

                let mut core_lines = sec_map.get("core").cloned().unwrap_or_default();
                let mut content_lines = sec_map.get("content").cloned().unwrap_or_default();
                while core_lines.first().map_or(false, |l| l.trim().is_empty()) {
                    core_lines.remove(0);
                }
                while core_lines.last().map_or(false, |l| l.trim().is_empty()) {
                    core_lines.pop();
                }
                while content_lines.first().map_or(false, |l| l.trim().is_empty()) {
                    content_lines.remove(0);
                }
                while content_lines.last().map_or(false, |l| l.trim().is_empty()) {
                    content_lines.pop();
                }

                // If the note wrote everything under Core/Tóm tắt (or without canonical headings)
                // and left Content/Nội dung empty, split after the lead overview block so both
                // Core Idea and Content & Elaboration are populated without duplicating any lines.
                if content_lines.is_empty() && core_lines.len() > 3 {
                    let starts_with_heading = core_lines.first().map_or(false, |l| l.trim().starts_with('#'));
                    let mut seen_non_heading = false;
                    let mut split_idx: Option<usize> = None;
                    for (idx, line) in core_lines.iter().enumerate() {
                        let lt = line.trim();
                        if lt.is_empty() {
                            continue;
                        }
                        let is_h = lt.starts_with("## ") || lt.starts_with("### ") || lt.starts_with("#### ");
                        let is_table = lt.starts_with('|') && lt.ends_with('|') && lt.len() > 2;
                        if seen_non_heading && (is_h || (starts_with_heading && is_table)) {
                            split_idx = Some(idx);
                            break;
                        }
                        if !lt.starts_with('#') {
                            seen_non_heading = true;
                        }
                    }
                    if let Some(idx) = split_idx {
                        content_lines = core_lines.split_off(idx);
                    }
                } else if core_lines.is_empty() && content_lines.len() > 1 {
                    // Note started directly with ## Content / ## Elaboration and skipped ## Core Idea:
                    // move the first non-empty paragraph/block into core_lines without duplicating it.
                    let mut split_idx = content_lines.len();
                    let mut seen_non_heading = false;
                    for (idx, line) in content_lines.iter().enumerate() {
                        let lt = line.trim();
                        if lt.is_empty() && seen_non_heading {
                            split_idx = idx;
                            break;
                        }
                        if !lt.is_empty() && !lt.starts_with('#') {
                            seen_non_heading = true;
                        }
                    }
                    if split_idx < content_lines.len() {
                        let rest = content_lines.split_off(split_idx);
                        core_lines = content_lines;
                        content_lines = rest;
                    }
                }

                let mut core_str = core_lines.join("\n").trim().to_string();
                let content_str = content_lines.join("\n").trim().to_string();
                if core_str.is_empty() && !content_str.is_empty() && !clean_title.trim().is_empty() {
                    core_str = clean_title.clone();
                }
                let conn_str = sec_map.get("connections").cloned().unwrap_or_default().join("\n").trim().to_string();
                let refs_str = sec_map.get("references").cloned().unwrap_or_default().join("\n").trim().to_string();

                let mut connection_count: usize = 0;
                if body_start < lines.len() {
                    for raw_line in &lines[body_start..] {
                        let t = raw_line.trim();
                        if t.starts_with("![[") && t.contains("Custom_Views/") {
                            continue;
                        }
                        connection_count += extract_wikilinks_from_line(raw_line).len();
                        // Count non-empty markdown links [label](url) and bare http(s):// URLs
                        let chars: Vec<char> = raw_line.chars().collect();
                        let n = chars.len();
                        let mut i = 0;
                        while i < n {
                            if chars[i] == '[' && (i + 1 < n && chars[i + 1] != '[') {
                                let mut j = i + 1;
                                while j < n && chars[j] != ']' && chars[j] != '\n' {
                                    j += 1;
                                }
                                if j + 2 < n && chars[j] == ']' && chars[j + 1] == '(' {
                                    let mut k = j + 2;
                                    while k < n && chars[k] != ')' && chars[k] != '\n' {
                                        k += 1;
                                    }
                                    if k < n && chars[k] == ')' {
                                        let url: String = chars[j + 2..k].iter().collect();
                                        if !url.trim().is_empty() {
                                            connection_count += 1;
                                        }
                                        i = k + 1;
                                        continue;
                                    }
                                }
                            } else if (chars[i] == 'h' || chars[i] == 'H') && i + 8 < n {
                                let prefix: String = chars[i..(i + 8).min(n)].iter().collect();
                                let prefix_low = prefix.to_ascii_lowercase();
                                if prefix_low.starts_with("https://") || prefix_low.starts_with("http://") {
                                    let mut j = i;
                                    while j < n && !chars[j].is_whitespace() && !matches!(chars[j], ')' | ']' | '>' | '"' | '\'') {
                                        j += 1;
                                    }
                                    connection_count += 1;
                                    i = j;
                                    continue;
                                }
                            }
                            i += 1;
                        }
                    }
                }

                let mut main_sections = Vec::new();
                let mut rail_sections = Vec::new();
                for (key, heading, sec_lines) in ordered_sections {
                    let body_md = sec_lines.join("\n").trim().to_string();
                    let body_html = render_markdown_block_rich_html(&body_md);
                    let entry = json!({
                        "key": key,
                        "heading": heading,
                        "text": body_md,
                        "richHtml": body_html,
                    });
                    if key == "connections" || key == "references" {
                        rail_sections.push(entry);
                    } else {
                        main_sections.push(entry);
                    }
                }

                json!({
                    "zettelId": zettel_id,
                    "cleanTitle": clean_title,
                    "zettelType": zettel_type,
                    "date": date_val,
                    "connectionCount": connection_count,
                    "coreIdea": core_str,
                    "coreIdeaRichHtml": render_markdown_block_rich_html(&core_str),
                    "contentSection": content_str,
                    "contentRichHtml": render_markdown_block_rich_html(&content_str),
                    "connections": conn_str,
                    "connectionsSection": conn_str,
                    "connectionsRichHtml": render_markdown_block_rich_html(&conn_str),
                    "sources": refs_str,
                    "referencesSection": refs_str,
                    "sourcesRichHtml": render_markdown_block_rich_html(&refs_str),
                    "mainSections": main_sections,
                    "railSections": rail_sections,
                })
            } else {
                Value::Null
            };

            let recipe_view = if note_kind == "recipe" {
                let mut ingredients = extract_frontmatter_yaml_list(&lines, "ingredients");
                let mut instructions = extract_frontmatter_yaml_list(&lines, "instructions");
                if instructions.is_empty() {
                    instructions = extract_frontmatter_yaml_list(&lines, "directions");
                }
                if instructions.is_empty() {
                    instructions = extract_frontmatter_yaml_list(&lines, "steps");
                }
                let mut tips = extract_frontmatter_yaml_list(&lines, "tips");
                let mut pairings = extract_frontmatter_yaml_list(&lines, "pairs_well_with");
                if pairings.is_empty() {
                    pairings = extract_frontmatter_yaml_list(&lines, "pairings");
                }
                let mut done_flags: Vec<bool> = extract_frontmatter_yaml_list(&lines, "instruction_done")
                    .into_iter()
                    .map(|s| s.eq_ignore_ascii_case("true") || s == "1")
                    .collect();
                if done_flags.is_empty() && !instructions.is_empty() {
                    done_flags = vec![false; instructions.len()];
                }
                let ingredients_done: Vec<i64> = extract_frontmatter_yaml_list(&lines, "ingredients_done")
                    .into_iter()
                    .filter_map(|s| s.trim().parse::<i64>().ok())
                    .collect();
                let steps_progress: i64 = frontmatter
                    .get("steps_progress")
                    .and_then(|s| s.trim().parse::<i64>().ok())
                    .unwrap_or_else(|| done_flags.iter().take_while(|&&b| b).count() as i64);

                let mut md_ingredients: Vec<String> = Vec::new();
                let mut md_instructions: Vec<String> = Vec::new();
                let mut md_tips: Vec<String> = Vec::new();
                let mut md_pairings: Vec<String> = Vec::new();
                let mut personal_notes_lines: Vec<String> = Vec::new();
                let mut unheaded_lines: Vec<String> = Vec::new();
                let mut current_md_sec = "";
                let mut found_pn_heading = false;

                if body_start < lines.len() {
                    for line in &lines[body_start..] {
                        let t = line.trim();
                        if t == "---" || (t.starts_with("![[") && t.contains("Custom_Views/")) {
                            continue;
                        }
                        if t.starts_with("## ") {
                            let h_title = t.trim_start_matches('#').trim();
                            if h_title.eq_ignore_ascii_case("Personal Notes")
                                || h_title.eq_ignore_ascii_case("Personal Note")
                                || h_title.eq_ignore_ascii_case("Notes")
                            {
                                current_md_sec = "notes";
                                found_pn_heading = true;
                                personal_notes_lines.clear();
                            } else if h_title.eq_ignore_ascii_case("Ingredients") {
                                current_md_sec = "ingredients";
                            } else if h_title.eq_ignore_ascii_case("Instructions")
                                || h_title.eq_ignore_ascii_case("Directions")
                                || h_title.eq_ignore_ascii_case("Steps")
                                || h_title.eq_ignore_ascii_case("Method")
                            {
                                current_md_sec = "instructions";
                            } else if h_title.eq_ignore_ascii_case("Tips")
                                || h_title.eq_ignore_ascii_case("Kitchen Notes")
                            {
                                current_md_sec = "tips";
                            } else if h_title.eq_ignore_ascii_case("Pairs Well With")
                                || h_title.eq_ignore_ascii_case("Pairings")
                            {
                                current_md_sec = "pairings";
                            } else {
                                current_md_sec = "other";
                            }
                            continue;
                        }
                        match current_md_sec {
                            "notes" => personal_notes_lines.push(line.clone()),
                            "ingredients" => {
                                let item = t
                                    .trim_start_matches("- [ ] ")
                                    .trim_start_matches("- [x] ")
                                    .trim_start_matches("- [X] ")
                                    .trim_start_matches("- ")
                                    .trim_start_matches("* ")
                                    .trim();
                                if !item.is_empty() {
                                    md_ingredients.push(strip_wikilink_brackets(item));
                                }
                            }
                            "instructions" => {
                                let item = t
                                    .trim_start_matches(|c: char| c.is_ascii_digit() || c == '.' || c == ')')
                                    .trim_start_matches("- ")
                                    .trim_start_matches("* ")
                                    .trim();
                                if !item.is_empty() {
                                    md_instructions.push(strip_wikilink_brackets(item));
                                }
                            }
                            "tips" => {
                                let item = t.trim_start_matches("- ").trim_start_matches("* ").trim();
                                if !item.is_empty() {
                                    md_tips.push(strip_wikilink_brackets(item));
                                }
                            }
                            "pairings" => {
                                let item = t.trim_start_matches("- ").trim_start_matches("* ").trim();
                                if !item.is_empty() {
                                    md_pairings.push(strip_wikilink_brackets(item));
                                }
                            }
                            "" => unheaded_lines.push(line.clone()),
                            _ => {}
                        }
                    }
                    if !found_pn_heading {
                        personal_notes_lines = unheaded_lines;
                    }
                }
                if ingredients.is_empty() && !md_ingredients.is_empty() {
                    ingredients = md_ingredients;
                }
                if instructions.is_empty() && !md_instructions.is_empty() {
                    instructions = md_instructions;
                    if done_flags.is_empty() {
                        done_flags = vec![false; instructions.len()];
                    }
                }
                if tips.is_empty() && !md_tips.is_empty() {
                    tips = md_tips;
                }
                if pairings.is_empty() && !md_pairings.is_empty() {
                    pairings = md_pairings;
                }
                let personal_notes_text = personal_notes_lines.join("\n").trim().to_string();
                let personal_notes_html = render_markdown_block_rich_html(&personal_notes_text);
                let recipe_description = frontmatter
                    .get("recipe_description")
                    .or_else(|| frontmatter.get("description"))
                    .or_else(|| frontmatter.get("summary"))
                    .map(|s| strip_wikilink_brackets(s))
                    .unwrap_or_default();
                let recipe_source = frontmatter
                    .get("source")
                    .or_else(|| frontmatter.get("source_name"))
                    .or_else(|| frontmatter.get("source_url"))
                    .map(|s| strip_wikilink_brackets(s))
                    .unwrap_or_default();

                json!({
                    "recipeCategory": dossier["category"],
                    "cuisine": dossier["cuisine"],
                    "tagline": dossier["tagline"],
                    "description": recipe_description,
                    "coverUrl": dossier["posterUrl"],
                    "servings": dossier["servings"],
                    "prepTime": dossier["prepTime"],
                    "cookTime": dossier["cookTime"],
                    "totalTime": dossier["totalTime"],
                    "difficulty": dossier["difficulty"],
                    "calories": dossier["calories"],
                    "rating": dossier["rating"],
                    "favorite": dossier["favorite"],
                    "bookmarked": dossier["bookmarked"],
                    "ingredients": ingredients,
                    "ingredientsDone": ingredients_done,
                    "instructions": instructions,
                    "stepsProgress": steps_progress,
                    "tips": tips,
                    "pairings": pairings,
                    "pairsWellWith": pairings,
                    "instructionDone": done_flags,
                    "personalNotes": personal_notes_text,
                    "personalNotesHtml": personal_notes_html,
                    "source": recipe_source,
                    "sourceName": frontmatter.get("source_name").cloned().unwrap_or_default(),
                    "sourceUrl": frontmatter.get("source_url").cloned().unwrap_or_default(),
                })
            } else {
                Value::Null
            };

            let exercise_view = if note_kind == "exercise" {
                let mut steps: Vec<String> = extract_frontmatter_yaml_list(&lines, "instructions");
                let mut tips: Vec<String> = extract_frontmatter_yaml_list(&lines, "tips");
                let mut mode = "";
                for b in &blocks {
                    if b.kind == "heading" {
                        let low = b.title.to_ascii_lowercase();
                        if low.contains("how to perform") || low.contains("execution") || low.contains("instruction") {
                            mode = "steps";
                        } else if low.contains("tip") || low.contains("note") {
                            mode = "tips";
                        } else {
                            mode = "";
                        }
                        continue;
                    }
                    let txt = b.text.trim();
                    if txt.is_empty() || txt.starts_with("![[") {
                        continue;
                    }
                    if mode == "steps" || b.kind == "numbered" {
                        steps.push(txt.to_string());
                    } else if mode == "tips" {
                        tips.push(txt.to_string());
                    }
                }
                let primary_muscles = extract_frontmatter_yaml_list(&lines, "primaryMuscles");
                let secondary_muscles = extract_frontmatter_yaml_list(&lines, "secondaryMuscles");
                let done_flags: Vec<bool> = extract_frontmatter_yaml_list(&lines, "instruction_done")
                    .into_iter()
                    .map(|s| s.eq_ignore_ascii_case("true") || s == "1")
                    .collect();
                json!({
                    "id": frontmatter.get("id").cloned().unwrap_or_default(),
                    "name": frontmatter.get("name").cloned().unwrap_or_default(),
                    "steps": steps,
                    "tips": tips,
                    "instructionDone": done_flags,
                    "primaryMuscles": primary_muscles,
                    "secondaryMuscles": secondary_muscles,
                    "level": frontmatter.get("level").cloned().unwrap_or_default(),
                    "force": frontmatter.get("force").cloned().unwrap_or_default(),
                    "mechanic": frontmatter.get("mechanic").cloned().unwrap_or_default(),
                    "equipment": frontmatter.get("equipment").cloned().unwrap_or_default(),
                    "category": frontmatter.get("category").cloned().unwrap_or_default(),
                    "previewUrl": dossier["posterUrl"],
                    "animationUrl": dossier["featuredImageUrl"],
                })
            } else {
                Value::Null
            };

            let settings_view = if note_kind == "settings" {
                json!({
                    "general": {
                        "username": frontmatter.get("username").cloned().unwrap_or_default(),
                        "vault_name": frontmatter.get("vault_name").cloned().unwrap_or_default(),
                        "start_date": frontmatter.get("start_date").cloned().unwrap_or_default(),
                        "callout_path": frontmatter.get("callout_path").cloned().unwrap_or_default(),
                        "schedule_heading": frontmatter.get("schedule_heading").cloned().unwrap_or_default(),
                        "exercise_heading": frontmatter.get("exercise_heading").cloned().unwrap_or_default(),
                        "cardio_heading": frontmatter.get("cardio_heading").cloned().unwrap_or_default(),
                    },
                    "weather": {
                        "weather_provider": frontmatter.get("weather_provider").cloned().unwrap_or_default(),
                        "weather_location": frontmatter.get("weather_location").cloned().unwrap_or_default(),
                        "weather_units": frontmatter.get("weather_units").cloned().unwrap_or_default(),
                        "openweathermap_key": frontmatter.get("openweathermap_key").cloned().unwrap_or_default(),
                        "weatherapi_key": frontmatter.get("weatherapi_key").cloned().unwrap_or_default(),
                    },
                    "media": {
                        "omdb_key": frontmatter.get("omdb_key").cloned().unwrap_or_default(),
                        "tmdb_key": frontmatter.get("tmdb_key").cloned().unwrap_or_default(),
                        "tmdb_Read_Access_Token": frontmatter.get("tmdb_Read_Access_Token").cloned().unwrap_or_default(),
                        "mal_client_id": frontmatter.get("mal_client_id").cloned().unwrap_or_default(),
                        "simkl_client_id": frontmatter.get("simkl_client_id").cloned().unwrap_or_default(),
                        "comic_vine_key": frontmatter.get("comic_vine_key").cloned().unwrap_or_default(),
                        "youtube_key": frontmatter.get("youtube_key").cloned().unwrap_or_default(),
                        "spotify_client_id": frontmatter.get("spotify_client_id").cloned().unwrap_or_default(),
                        "goodreads_key": frontmatter.get("goodreads_key").cloned().unwrap_or_default(),
                        "spoonacular_key": frontmatter.get("spoonacular_key").cloned().unwrap_or_default(),
                    },
                    "games": {
                        "rawg_key": frontmatter.get("rawg_key").cloned().unwrap_or_default(),
                        "igdb_client_id": frontmatter.get("igdb_client_id").cloned().unwrap_or_default(),
                        "giantbomb_key": frontmatter.get("giantbomb_key").cloned().unwrap_or_default(),
                        "steam_key": frontmatter.get("steam_key").cloned().unwrap_or_default(),
                        "steam_id": frontmatter.get("steam_id").cloned().unwrap_or_default(),
                    },
                    "finance": {
                        "default_currency": frontmatter.get("default_currency").cloned().unwrap_or_default(),
                        "currency_symbol": frontmatter.get("currency_symbol").cloned().unwrap_or_default(),
                        "monthly_budget": frontmatter.get("monthly_budget").cloned().unwrap_or_default(),
                        "savings_goal_pct": frontmatter.get("savings_goal_pct").cloned().unwrap_or_default(),
                        "exchangerate_key": frontmatter.get("exchangerate_key").cloned().unwrap_or_default(),
                        "alphavantage_key": frontmatter.get("alphavantage_key").cloned().unwrap_or_default(),
                        "coingecko_key": frontmatter.get("coingecko_key").cloned().unwrap_or_default(),
                    },
                    "globe": {
                        "globe_marker_color": frontmatter.get("globe_marker_color").cloned().unwrap_or_default(),
                        "globe_Visited_Country_color": frontmatter.get("globe_Visited_Country_color").cloned().unwrap_or_default(),
                        "globe_glow_color": frontmatter.get("globe_glow_color").cloned().unwrap_or_default(),
                        "globe_Location_Name": frontmatter.get("globe_Location_Name").cloned().unwrap_or_default(),
                        "globe_Latitude": frontmatter.get("globe_Latitude").cloned().unwrap_or_default(),
                        "globe_Longitude": frontmatter.get("globe_Longitude").cloned().unwrap_or_default(),
                    }
                })
            } else {
                Value::Null
            };

            let finance_view = if note_kind == "finance" || rel_norm.to_ascii_lowercase().contains("finance") {
                let mut base = compute_vault_finance_summary(&notes);
                if let Some(obj) = base.as_object_mut() {
                    let currency = frontmatter
                        .get("currency")
                        .or_else(|| frontmatter.get("bookcurrency"))
                        .or_else(|| frontmatter.get("default_currency"))
                        .map(|s| strip_wikilink_brackets(s))
                        .filter(|s| !s.is_empty())
                        .unwrap_or_else(|| "VND".to_string());
                    let period = frontmatter
                        .get("period")
                        .or_else(|| frontmatter.get("defaultrange"))
                        .or_else(|| frontmatter.get("range"))
                        .or_else(|| frontmatter.get("timeframe"))
                        .map(|s| strip_wikilink_brackets(s))
                        .unwrap_or_default();
                    let subtitle = frontmatter
                        .get("subtitle")
                        .or_else(|| frontmatter.get("description"))
                        .or_else(|| frontmatter.get("summary"))
                        .map(|s| strip_wikilink_brackets(s))
                        .unwrap_or_default();
                    let mut note_notes_lines = Vec::new();
                    if body_start < lines.len() {
                        for l in &lines[body_start..] {
                            let t = l.trim();
                            if t == "---"
                                || (t.starts_with("![[") && t.contains("Custom_Views/"))
                                || (t.starts_with('|') && t.ends_with('|'))
                            {
                                continue;
                            }
                            if t.starts_with("## ") {
                                let h = t.trim_start_matches('#').trim().to_ascii_lowercase();
                                if h.contains("income") || h.contains("spending") || h.contains("expense") || h.contains("transaction") || h.contains("balance") {
                                    continue;
                                }
                            }
                            note_notes_lines.push(l.clone());
                        }
                    }
                    let notes_md = note_notes_lines.join("\n").trim().to_string();
                    obj.insert("currency".to_string(), json!(currency));
                    obj.insert("period".to_string(), json!(period));
                    obj.insert("subtitle".to_string(), json!(subtitle));
                    obj.insert("notesText".to_string(), json!(notes_md));
                    obj.insert("notesRichHtml".to_string(), json!(render_markdown_block_rich_html(&notes_md)));
                }
                base
            } else {
                Value::Null
            };

            let current_idx = lookup
                .get(&rel_norm.to_ascii_lowercase())
                .copied()
                .or_else(|| lookup.get(&stem.to_ascii_lowercase()).copied());

            let mut linked_backlinks = Vec::new();
            let mut unlinked_mentions = Vec::new();
            let mut neighbors_1hop: BTreeSet<usize> = BTreeSet::new();

            // Outgoing from current note
            if let Some(c_idx) = current_idx {
                for (target_raw, _, _) in &notes[c_idx].outgoing_links {
                    let key = target_raw.trim().trim_end_matches(".md").to_ascii_lowercase();
                    if let Some(&dst_idx) = lookup.get(&key) {
                        if dst_idx != c_idx && !is_template_note_summary(&notes[dst_idx]) {
                            neighbors_1hop.insert(dst_idx);
                        }
                    }
                }
            }

            let stem_lower = stem.to_ascii_lowercase();
            let title_lower = title.to_ascii_lowercase();
            let search_terms: Vec<(String, String)> = {
                let mut v = vec![stem_lower.clone()];
                if !title.eq_ignore_ascii_case(&stem) && title.len() >= 3 {
                    v.push(title_lower.clone());
                }
                for a in &aliases {
                    if a.len() >= 3 {
                        v.push(a.to_ascii_lowercase());
                    }
                }
                v.into_iter()
                    .filter(|s| s.len() >= 2)
                    .map(|term| {
                        let bracketed = format!("[[{}", term);
                        (term, bracketed)
                    })
                    .collect()
            };

            for (idx, other) in notes.iter().enumerate() {
                if Some(idx) == current_idx || other.rel_path == rel_norm || is_template_note_summary(other) {
                    continue;
                }
                let mut linked_lines: HashSet<usize> = HashSet::new();
                for (target_raw, line_no, snippet) in &other.outgoing_links {
                    let key = target_raw.trim().trim_end_matches(".md").to_ascii_lowercase();
                    let matches_self = Some(idx) != current_idx
                        && (lookup.get(&key).copied() == current_idx
                            || key == stem_lower
                            || key == title_lower);
                    if matches_self {
                        neighbors_1hop.insert(idx);
                        linked_lines.insert(*line_no);
                        linked_backlinks.push(json!({
                            "relPath": other.rel_path,
                            "title": other.title,
                            "line": line_no,
                            "snippet": snippet,
                        }));
                    }
                }

                // Check unlinked mentions in other note's lines (capped to 25 total, zero per-line String allocation)
                if unlinked_mentions.len() < 25 && !search_terms.is_empty() {
                    for (line_idx, raw_line) in other.lines.iter().enumerate() {
                        let line_1based = line_idx + 1;
                        if linked_lines.contains(&line_1based) {
                            continue;
                        }
                        let t = raw_line.trim();
                        if t.is_empty() || t.starts_with("---") || t.starts_with("```") {
                            continue;
                        }
                        for (term, bracketed_term) in &search_terms {
                            if term.len() >= 3 && contains_ascii_case_insensitive(t, term) {
                                if !contains_ascii_case_insensitive(t, bracketed_term) {
                                    unlinked_mentions.push(json!({
                                        "relPath": other.rel_path,
                                        "title": other.title,
                                        "line": line_1based,
                                        "snippet": t.chars().take(160).collect::<String>(),
                                        "matchedTerm": title,
                                    }));
                                    break;
                                }
                            }
                        }
                        if unlinked_mentions.len() >= 25 {
                            break;
                        }
                    }
                }
            }

            // If no direct wikilink neighbors exist, include up to 10 cluster peers sharing a tag or category for Local Graph
            if neighbors_1hop.is_empty() {
                let my_cat = frontmatter.get("categories").cloned().unwrap_or_default();
                for (idx, other) in notes.iter().enumerate() {
                    if Some(idx) == current_idx || other.rel_path == rel_norm || is_template_note_summary(other) {
                        continue;
                    }
                    let shares_tag = !tags.is_empty()
                        && other.tags.iter().any(|t| tags.iter().any(|mt| mt.eq_ignore_ascii_case(t)));
                    let shares_cat = !my_cat.is_empty()
                        && other.frontmatter.get("categories") == Some(&my_cat);
                    if shares_tag || shares_cat {
                        neighbors_1hop.insert(idx);
                        if neighbors_1hop.len() >= 10 {
                            break;
                        }
                    }
                }
            }

            // Build Local Graph (dandelion hub-and-spoke: center node + 1-hop spokes + 2-hop outer fan)
            let hop1_vec: Vec<usize> = neighbors_1hop.iter().copied().collect();
            let hop1_count = hop1_vec.len().max(1) as f64;
            let mut hop2_parent_angles: BTreeMap<usize, Vec<f64>> = BTreeMap::new();
            let mut local_edges = Vec::new();
            let mut raw_local_nodes: Vec<(String, String, usize, f64, f64)> = Vec::new();
            raw_local_nodes.push((rel_norm.clone(), title.clone(), 0, 0.0, 0.0));

            for (pos, &n_idx) in hop1_vec.iter().enumerate() {
                let angle = (pos as f64 / hop1_count) * std::f64::consts::TAU - std::f64::consts::FRAC_PI_2;
                let radius = if hop1_vec.len() <= 2 {
                    0.20
                } else if hop1_vec.len() <= 6 {
                    0.25
                } else {
                    0.28 + ((pos % 2) as f64) * 0.035
                };
                let nx = radius * angle.cos();
                let ny = radius * angle.sin();
                let n_note = &notes[n_idx];
                raw_local_nodes.push((n_note.rel_path.clone(), n_note.title.clone(), 1, nx, ny));
                local_edges.push(json!({
                    "source": rel_norm,
                    "target": n_note.rel_path,
                }));

                for (t_raw, _, _) in &n_note.outgoing_links {
                    let key = t_raw.trim().trim_end_matches(".md").to_ascii_lowercase();
                    if let Some(&h2_idx) = lookup.get(&key) {
                        if Some(h2_idx) != current_idx
                            && !neighbors_1hop.contains(&h2_idx)
                            && !is_template_note_summary(&notes[h2_idx])
                            && (hop2_parent_angles.len() < 16 || hop2_parent_angles.contains_key(&h2_idx))
                        {
                            hop2_parent_angles.entry(h2_idx).or_default().push(angle);
                            local_edges.push(json!({
                                "source": n_note.rel_path,
                                "target": notes[h2_idx].rel_path,
                            }));
                        }
                    }
                }
            }

            let hop2_vec: Vec<(usize, Vec<f64>)> = hop2_parent_angles.into_iter().collect();
            let hop2_count = hop2_vec.len();
            for (pos, (h2_idx, parent_angles)) in hop2_vec.into_iter().enumerate() {
                let base_angle = if !parent_angles.is_empty() {
                    let sum_sin: f64 = parent_angles.iter().map(|a| a.sin()).sum();
                    let sum_cos: f64 = parent_angles.iter().map(|a| a.cos()).sum();
                    sum_sin.atan2(sum_cos)
                } else {
                    ((pos as f64 + 0.5) / hop2_count.max(1) as f64) * std::f64::consts::TAU
                };
                let spread = ((pos as f64 % 3.0) - 1.0) * 0.16;
                let angle = base_angle + spread;
                let radius = 0.40 + ((pos % 2) as f64) * 0.035;
                let nx = radius * angle.cos();
                let ny = radius * angle.sin();
                let h2_note = &notes[h2_idx];
                raw_local_nodes.push((h2_note.rel_path.clone(), h2_note.title.clone(), 2, nx, ny));
            }

            let mut min_lx = f64::INFINITY;
            let mut max_lx = f64::NEG_INFINITY;
            let mut min_ly = f64::INFINITY;
            let mut max_ly = f64::NEG_INFINITY;
            for (_, _, _, x, y) in &raw_local_nodes {
                min_lx = min_lx.min(*x);
                max_lx = max_lx.max(*x);
                min_ly = min_ly.min(*y);
                max_ly = max_ly.max(*y);
            }
            let min_span_floor = if raw_local_nodes.len() <= 8 {
                0.80
            } else {
                0.55
            };
            let norm_scale = if raw_local_nodes.len() <= 3 {
                0.66
            } else if raw_local_nodes.len() <= 8 {
                0.70
            } else {
                0.76
            };
            let span_l = (max_lx - min_lx).max(max_ly - min_ly).max(min_span_floor);
            let center_bias = if raw_local_nodes.len() <= 8 { 0.22 } else { 0.5 };
            let cx_l = (min_lx + max_lx) * center_bias;
            let cy_l = (min_ly + max_ly) * center_bias;
            let single = raw_local_nodes.len() <= 1;
            let local_nodes: Vec<Value> = raw_local_nodes
                .into_iter()
                .map(|(rpath, ntitle, hop, x, y)| {
                    let nx = if single {
                        0.5
                    } else {
                        0.5 + ((x - cx_l) / span_l) * norm_scale
                    };
                    let ny = if single {
                        0.5
                    } else {
                        0.5 + ((y - cy_l) / span_l) * norm_scale
                    };
                    let color_hex = if hop == 0 {
                        "#8dc9d6"
                    } else if hop == 1 {
                        "#7bb5c1"
                    } else {
                        "#577980"
                    };
                    json!({
                        "id": rpath,
                        "title": ntitle,
                        "relPath": rpath,
                        "colorHex": color_hex,
                        "hop": hop,
                        "isHub": hop == 0,
                        "x": (nx * 10000.0).round() / 10000.0,
                        "y": (ny * 10000.0).round() / 10000.0,
                    })
                })
                .collect();

            Ok(json!({
                "ok": true,
                "category": "markdown",
                "language": "markdown",
                "noteKind": note_kind,
                "dossier": dossier,
                "journalView": journal_view,
                "cornellView": cornell_view,
                "zettelkastenView": zettelkasten_view,
                "recipeView": recipe_view,
                "exerciseView": exercise_view,
                "settingsView": settings_view,
                "financeSummary": finance_view,
                "relPath": rel_norm,
                "absPath": abs_str,
                "title": title,
                "stem": stem,
                "ext": ext,
                "sizeBytes": size_bytes,
                "mtimeSecs": mtime_secs,
                "sha256": digest,
                "content": content,
                "lineCount": lines.len(),
                "bodyStartLine": body_start + 1,
                "frontmatter": frontmatter,
                "tags": tags,
                "aliases": aliases,
                "blocks": blocks,
                "outline": outline,
                "flashcards": flashcards,
                "openTasks": open_tasks,
                "doneTasks": done_tasks,
                "backlinks": linked_backlinks,
                "unlinkedMentions": unlinked_mentions,
                "localGraph": {
                    "nodes": local_nodes,
                    "edges": local_edges,
                }
            }))
        }
    }
}

pub fn atomic_write_inside_vault(vault_canon: &Path, rel_str: &str, content: &str) -> Result<(PathBuf, String), String> {
    let (target_path, rel_norm) = resolve_inside_vault(vault_canon, rel_str, false)?;
    let Some(parent) = target_path.parent() else {
        return Err("Target file has no parent directory".to_string());
    };
    fs::create_dir_all(parent).map_err(|e| format!("Cannot create parent directory: {}", e))?;
    let parent_canon = fs::canonicalize(parent).map_err(|e| format!("Cannot canonicalize parent: {}", e))?;
    if !parent_canon.starts_with(vault_canon) {
        return Err("Parent directory escapes vault boundary".to_string());
    }
    let existing_perms = fs::metadata(&target_path).ok().map(|m| m.permissions());
    let pid = std::process::id();
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.subsec_nanos())
        .unwrap_or(0);
    let tmp_name = format!(
        ".alis-nexus-tmp-{}-{}-{}",
        target_path
            .file_name()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_else(|| "note".to_string()),
        pid,
        nanos
    );
    let tmp_path = parent_canon.join(tmp_name);
    {
        let mut file = fs::File::create(&tmp_path)
            .map_err(|e| format!("Cannot create temporary file: {}", e))?;
        file.write_all(content.as_bytes())
            .map_err(|e| format!("Cannot write temporary file: {}", e))?;
        file.sync_all()
            .map_err(|e| format!("Cannot fsync temporary file: {}", e))?;
    }
    if let Some(perms) = existing_perms {
        let _ = fs::set_permissions(&tmp_path, perms);
    }
    fs::rename(&tmp_path, &target_path).map_err(|e| {
        let _ = fs::remove_file(&tmp_path);
        format!("Cannot commit file atomically: {}", e)
    })?;
    Ok((target_path, rel_norm))
}

pub fn cmd_write(vault_str: &str, rel_str: &str, content: &str) -> Result<Value, String> {
    let vault_canon = resolve_vault_root(vault_str)?;
    let (_, rel_norm) = atomic_write_inside_vault(&vault_canon, rel_str, content)?;
    cmd_read(vault_str, &rel_norm)
}

fn try_load_vault_template(vault_canon: &Path, template_kind: &str, title: &str, date_str: &str) -> Option<String> {
    let kind_norm = match template_kind.trim().to_ascii_lowercase().as_str() {
        "tv" => "tvseries".to_string(),
        other => other.to_string(),
    };
    if kind_norm.is_empty() || kind_norm == "standard" {
        return None;
    }
    let mut candidate_dirs = vec![
        "90_System/92_Templates".to_string(),
        "90_System/91_Templates".to_string(),
        "01_Templates".to_string(),
        "Templates".to_string(),
    ];
    let obs_tpl_cfg = vault_canon.join(".obsidian/templates.json");
    if let Ok(cfg_raw) = fs::read_to_string(&obs_tpl_cfg) {
        if let Ok(cfg_val) = serde_json::from_str::<Value>(&cfg_raw) {
            if let Some(folder) = cfg_val["folder"].as_str().map(|s| s.trim()).filter(|s| !s.is_empty()) {
                if !candidate_dirs.iter().any(|d| d == folder) {
                    candidate_dirs.insert(0, folder.to_string());
                }
            }
        }
    }
    let aliases: &[&str] = match kind_norm.as_str() {
        "tvseries" => &["tvseries", "tv series", "tv_series", "tv"],
        "movie" => &["movie", "movies", "film"],
        "book" => &["book", "books"],
        "game" => &["game", "games"],
        "recipe" => &["recipe", "recipes"],
        "place" => &["place", "places", "location"],
        "daily" => &["daily", "journal", "daily note"],
        _ => &[kind_norm.as_str()],
    };
    for rel_dir in candidate_dirs {
        let dir_path = vault_canon.join(&rel_dir);
        let Ok(entries) = fs::read_dir(&dir_path) else { continue };
        for entry in entries.flatten() {
            let p = entry.path();
            if p.extension().and_then(|e| e.to_str()).map(|e| e.eq_ignore_ascii_case("md")) != Some(true) {
                continue;
            }
            let stem = p.file_stem().and_then(|s| s.to_str()).unwrap_or("").trim().to_ascii_lowercase();
            let clean_stem = stem.trim_end_matches(" template").trim_end_matches("_template").trim();
            if aliases.iter().any(|a| *a == stem || *a == clean_stem) {
                if let Ok(raw) = fs::read_to_string(&p) {
                    if raw.contains("<%") && raw.contains("%>") {
                        continue;
                    }
                    let expanded = raw
                        .replace("{{title}}", title)
                        .replace("{{Title}}", title)
                        .replace("{{date}}", date_str)
                        .replace("{{Date}}", date_str);
                    return Some(expanded);
                }
            }
        }
    }
    None
}

fn note_has_user_recipe_section(raw: &str, section_kind: &str) -> bool {
    let lines: Vec<String> = raw.lines().map(|s| s.to_string()).collect();
    let fm_list = extract_frontmatter_yaml_list(&lines, section_kind);
    if fm_list.iter().any(|s| !s.trim().is_empty() && s.trim() != "-") {
        return true;
    }
    let (_, _, _, body_start) = parse_frontmatter(&lines);
    let mut in_section = false;
    for line in lines.iter().skip(body_start) {
        let t = line.trim();
        if t.starts_with("##") {
            let h = t.trim_start_matches('#').trim().to_ascii_lowercase();
            in_section = if section_kind == "ingredients" {
                h.contains("ingredient")
            } else {
                h.contains("instruction") || h.contains("direction") || h.contains("method") || h.contains("step")
            };
            continue;
        }
        if in_section {
            let item = t
                .trim_start_matches("- [ ]")
                .trim_start_matches("- [x]")
                .trim_start_matches("- [X]")
                .trim_start_matches("- ")
                .trim_start_matches("* ")
                .trim_start_matches(|c: char| c.is_ascii_digit() || c == '.')
                .trim();
            if !item.is_empty() && item != "-" {
                return true;
            }
        }
    }
    false
}

fn inject_recipe_markdown_sections_if_missing(
    raw: &str,
    ingredients: &[String],
    instructions: &[String],
) -> String {
    let add_ing = !ingredients.is_empty() && !note_has_user_recipe_section(raw, "ingredients");
    let add_ins = !instructions.is_empty() && !note_has_user_recipe_section(raw, "instructions");
    if !add_ing && !add_ins {
        return raw.to_string();
    }
    let mut block = String::new();
    if add_ing {
        block.push_str("\n## Ingredients\n");
        for item in ingredients {
            if !item.trim().is_empty() {
                block.push_str(&format!("- {}\n", item.trim()));
            }
        }
    }
    if add_ins {
        block.push_str("\n## Instructions\n");
        for (idx, step) in instructions.iter().enumerate() {
            if !step.trim().is_empty() {
                block.push_str(&format!("{}. {}\n", idx + 1, step.trim()));
            }
        }
    }
    if let Some(pn_idx) = raw.find("## Personal Notes") {
        let mut out = String::with_capacity(raw.len() + block.len() + 4);
        out.push_str(raw[..pn_idx].trim_end());
        out.push('\n');
        out.push_str(&block);
        out.push('\n');
        out.push_str(&raw[pn_idx..]);
        out
    } else {
        let mut out = raw.trim_end().to_string();
        out.push('\n');
        out.push_str(&block);
        out
    }
}

pub fn cmd_create(vault_str: &str, rel_str: &str, title_opt: Option<&str>, template: &str) -> Result<Value, String> {
    cmd_create_with_candidate(vault_str, rel_str, title_opt, template, None)
}

pub fn cmd_create_with_candidate(
    vault_str: &str,
    rel_str: &str,
    title_opt: Option<&str>,
    template: &str,
    candidate_json_opt: Option<&str>,
) -> Result<Value, String> {
    let vault_canon = resolve_vault_root(vault_str)?;
    let mut normalized_rel = rel_str.trim().to_string();
    if !normalized_rel.contains('.') {
        normalized_rel.push_str(".md");
    }
    let (target_path, rel_norm) = resolve_inside_vault(&vault_canon, &normalized_rel, false)?;
    if target_path.exists() {
        return cmd_read(vault_str, &rel_norm);
    }
    let stem = target_path
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| "Untitled".to_string());
    let title = title_opt.filter(|s| !s.trim().is_empty()).unwrap_or(&stem);
    let now_secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let (y, m, d) = civil_from_days((now_secs / 86400) as i64);
    let date_str = format!("{:04}-{:02}-{:02}", y, m, d);

    let tpl_lower = template.trim().to_ascii_lowercase();
    let tpl_norm = match tpl_lower.as_str() {
        "tv" => "tvseries",
        other => other,
    };

    let mut initial_content = if let Some(vault_tpl) = try_load_vault_template(&vault_canon, tpl_norm, title, &date_str) {
        vault_tpl
    } else {
        match tpl_norm {
        "zettelkasten" => format!(
            "---\ntitle: \"{}\"\ntype: Fleeting\ncreated: {}\ntags: [zettelkasten]\naliases: []\n---\n\n# {}\n\n## Core Idea\n- \n\n## Content\n- \n\n## Context & Connections\n- \n\n## Sources & References\n- \n",
            title, date_str, title
        ),
        "cornell" => format!(
            "---\ncreated: {}\ncourse: \"\"\ntopic: \"{}\"\nstatus: \"#review\"\ntags:\n  - cornell-notes\ncssclasses:\n  - cornell-note\n  - cornell-border\n---\n\n## {}\n\n### ?\nCâu hỏi chính của bài?\n\n- Ý chính 1\n- Ý chính 2\n\n### !\nĐiểm quan trọng cần nhớ\n\n- Chi tiết quan trọng\n\n### Summary\n> [!SUMMARY] Tóm tắt\n> - Kết luận cốt lõi.\n",
            date_str, title, title
        ),
        "movie" => format!(
            "---\ncategories:\n  - \"[[Movies]]\"\ntitle: \"{}\"\nposter: \"\"\nbackdrop: \"\"\nscoreImdb: \"\"\nrating: \"\"\nstatus: \"To Watch\"\nwatched: false\nfavorite: false\ngenre:\n  - \"[[Drama]]\"\nyear: 2026\nplot: \"\"\ndirector: []\ncast: []\n---\n",
            title
        ),
        "tvseries" => format!(
            "---\ncategories:\n  - \"[[TV Series]]\"\ntitle: \"{}\"\nposter: \"\"\nbackdrop: \"\"\nscoreImdb: \"\"\nrating: \"\"\nstatus: \"To Watch\"\nwatched: false\nfavorite: false\ntotal_seasons: 1\ntotal_episodes: 10\ngenre:\n  - \"[[Drama]]\"\nyear: \"2026\"\nplot: \"\"\ncreator: []\ncast: []\n---\n",
            title
        ),
        "game" => format!(
            "---\ntitle: \"{}\"\ncover: \"\"\nbackdrop: \"\"\ndeveloper: \"\"\npublisher: \"\"\nrelease_year: 2026\nstatus: \"Backlog\"\nrating: 0\nhours_played: 0\nplatform:\n  - PC\ngenre:\n  - Action\nfavorite: false\ntags:\n  - Game\n---\n\n## Thoughts & Review\n\n- \n\n## Memorable Moments\n\n- \n",
            title
        ),
        "website" => format!(
            "---\ntitle: \"{}\"\nurl: \"http://example.onion\"\nstatus: ONLINE\nlanguage: en\ncreated: {}\ntags:\n  - OnionSite\n---\n\n> [!multi-column]\n>\n>> [!blank-container]\n>> ### Description\n>> **{}** description.\n",
            title, date_str, title
        ),
        "place" => format!(
            "---\ncategories:\n  - \"[[Places]]\"\ntitle: \"{}\"\naddress: \"\"\ncity: \"\"\ncountry: \"\"\ncoordinates: \"\"\nplace_type: \"tourist\"\nvisited: false\nfavorite: false\ncreated: {}\ntags:\n  - place\n---\n\n## Notes\n\n- \n",
            title, date_str
        ),
        "book" => format!(
            "---\nTitle: \"{}\"\nAuthor: \"\"\nCover: \"\"\nGenre:\n  - \"[[Non-Fiction]]\"\nStatus: \"Haven't started\"\nCurrentPage: 0\nTotalPages: 0\nRating: \"\"\nDateStarted: \"\"\nDateFinished: \"\"\ntags:\n  - \"#Book\"\n---\n\n## Synopsis\n\n## Notes & Takeaways\n- \n",
            title
        ),
        "recipe" => format!(
            "---\ncategories:\n  - \"[[Recipes]]\"\ncover: \"\"\nrecipe_category: \"Main Course\"\ncuisine: \"\"\ntagline: \"\"\ndescription: \"\"\nservings: 2\nprep_time: 15\ncook_time: 20\ndifficulty: \"Easy\"\nfavorite: false\nbookmarked: false\ningredients:\n  - \ninstructions:\n  - \ninstruction_done:\n  - false\ntips:\n  - \npairs_well_with:\n  - \ncreated: {}\n---\n\n![[90_System/93_Configuration/Custom_Views/Recipe/Recipe.html]]\n\n## Personal Notes\n\n",
            date_str
        ),
        "exercise" => format!(
            "---\nname: \"{}\"\nlevel: \"beginner\"\nforce: \"push\"\nmechanic: \"compound\"\nequipment: \"body only\"\ncategory: \"strength\"\nprimaryMuscles:\n  - chest\nsecondaryMuscles: []\npreview: \"\"\nanimation: \"\"\n---\n\n## Instructions\n1. \n\n## Tips\n- \n",
            title
        ),
        "clipping" => format!(
            "---\ntitle: \"{}\"\nsource: \"\"\nauthor: \"\"\npublished: {}\ncreated: {}\ndescription: \"\"\ntags:\n  - clippings\n---\n\n# {}\n\n",
            title, date_str, date_str, title
        ),
        "contact" => format!(
            "---\nFull Name: \"{}\"\nBirthday: \"\"\nPhone: \"\"\nAddress: \"\"\nCompany: \"\"\nEmail: \"\"\ncreated:\n  - \"{}\"\ntags:\n  - \"#Contact\"\n---\n",
            title, date_str
        ),
        "teaching" => format!(
            "---\ncourse: \"\"\nsession: 1\ntopic: \"{}\"\ndate: {}\ntime: \"19:00 - 21:00\"\nlocation: \"Online\"\nmaterials: []\nprerequisites: []\nassignments: []\n---\n\n# 📚 [Session 1] {}\n\n## 🎯 1. Learning Objectives\n- [ ] \n",
            title, date_str, title
        ),
        "vocabulary" => format!(
            "---\nType: literature\nSource: \"\"\nUnit: \"[[{}]]\"\nDateCreated: {}\ntags:\n  - flashcards/english/vocabulary\n  - review/english/vocabulary\n---\n\n📝 Danh sách từ vựng: [[{}]]\n",
            title, date_str, title
        ),
        "daily" => format!(
            "---\ntitle: \"{}\"\ntype: Journal\ncreated: {}\ntags: [journal, daily, Daily-notes]\n---\n\n## Day Planner\n- [ ] 08:00 - 09:00 Deep Work\n\n---\n\n## Notes & Log\n- \n",
            title, date_str
        ),
        "finance" => format!(
            "---\ncategories:\n  - Finance Report\ncurrency: VND\nperiod: Monthly\ncreated: {}\n---\n\n# {}\n\n## Income\n| Date | Source | Category | Amount |\n| --- | --- | --- | --- |\n| {} | Salary | Work | 25000000 |\n\n## Spending\n| Date | Item | Category | Amount |\n| --- | --- | --- | --- |\n| {} | Groceries | Food | 450000 |\n",
            date_str, title, date_str, date_str
        ),
        _ => format!(
            "---\ntitle: \"{}\"\ncreated: {}\ntags: []\naliases: []\n---\n\n# {}\n\n- \n",
            title, date_str, title
        ),
        }
    };

    if let Some(cand_str) = candidate_json_opt.filter(|s| !s.trim().is_empty()) {
        if let Ok(cand_val) = serde_json::from_str::<Value>(cand_str) {
            if let Some(fm_obj) = cand_val.get("frontmatter").and_then(|v| v.as_object()) {
                initial_content = apply_frontmatter_updates_to_content(&initial_content, fm_obj);
            }
            if tpl_norm == "recipe" {
                let ing_list: Vec<String> = cand_val["body_sections"]["ingredients"]
                    .as_array()
                    .map(|arr| arr.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect())
                    .unwrap_or_default();
                let ins_list: Vec<String> = cand_val["body_sections"]["instructions"]
                    .as_array()
                    .map(|arr| arr.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect())
                    .unwrap_or_default();
                initial_content = inject_recipe_markdown_sections_if_missing(&initial_content, &ing_list, &ins_list);
            } else if tpl_norm == "book" {
                if let Some(syn) = cand_val["body_sections"]["synopsis"]
                    .as_str()
                    .or_else(|| cand_val["overview"].as_str())
                    .filter(|s| !s.trim().is_empty())
                {
                    if initial_content.contains("## Synopsis\n\n##") {
                        initial_content = initial_content.replacen(
                            "## Synopsis\n\n##",
                            &format!("## Synopsis\n{}\n\n##", syn.trim()),
                            1,
                        );
                    }
                }
            }
        }
    }

    let (_, saved_rel) = atomic_write_inside_vault(&vault_canon, &rel_norm, &initial_content)?;
    cmd_read(vault_str, &saved_rel)
}

pub fn cmd_create_folder(vault_str: &str, rel_str: &str) -> Result<Value, String> {
    let vault_canon = resolve_vault_root(vault_str)?;
    let (target_path, rel_norm) = resolve_inside_vault(&vault_canon, rel_str, false)?;
    if !target_path.exists() {
        fs::create_dir_all(&target_path)
            .map_err(|e| format!("Cannot create folder '{}': {}", rel_norm, e))?;
    }
    Ok(json!({
        "ok": true,
        "relPath": rel_norm,
        "isDir": true
    }))
}

// Journal check-in scalars are patched without reserializing unrelated YAML or body bytes.
fn apply_check_in_updates(raw: &str, updates: &serde_json::Map<String, Value>) -> String {
    let lines: Vec<&str> = raw.split_inclusive('\n').collect();
    let newline = if lines.first().is_some_and(|line| line.ends_with("\r\n")) { "\r\n" } else { "\n" };
    let fm_end = if lines.first().is_some_and(|line| line.trim() == "---") {
        lines.iter().enumerate().skip(1).find_map(|(index, line)| {
            if line.trim() == "---" || line.trim() == "..." { Some(index) } else { None }
        })
    } else { None };
    let mut out = String::new();
    let mut updated = HashSet::new();
    if let Some(end) = fm_end {
        out.push_str(lines[0]);
        let mut index = 1;
        while index < end {
            let line = lines[index];
            let entry = if !line.starts_with(' ') && !line.starts_with('\t') && !line.trim_start().starts_with('-') {
                line.split_once(':').and_then(|(key, _)| {
                    updates.iter().find(|(name, _)| name.eq_ignore_ascii_case(key.trim())).map(|(name, value)| (key, name, value))
                })
            } else { None };
            if let Some((key, name, value)) = entry {
                out.push_str(&format!("{}: {}{}", key, format_yaml_scalar(value), if line.ends_with("\r\n") { "\r\n" } else { "\n" }));
                updated.insert(name.to_ascii_lowercase());
                index += 1;
                while index < end && (lines[index].starts_with(' ') || lines[index].starts_with('\t') || lines[index].trim_start().starts_with("- ") || lines[index].trim().is_empty()) {
                    if lines[index].trim().is_empty() || lines[index].trim_start().starts_with('#') {
                        out.push_str(lines[index]);
                    }
                    index += 1;
                }
            } else {
                out.push_str(line);
                index += 1;
            }
        }
        for (key, value) in updates {
            if !updated.contains(&key.to_ascii_lowercase()) {
                out.push_str(&format!("{}: {}{}", key, format_yaml_scalar(value), newline));
            }
        }
        for line in &lines[end..] { out.push_str(line); }
    } else {
        out.push_str(&format!("---{}", newline));
        for (key, value) in updates { out.push_str(&format!("{}: {}{}", key, format_yaml_scalar(value), newline)); }
        out.push_str(&format!("---{}", newline));
        out.push_str(raw);
    }
    out
}

pub fn cmd_journal_weather(vault_str: &str, rel_str: &str, summary: &str, replace_existing: bool) -> Result<Value, String> {
    let vault = resolve_vault_root(vault_str)?;
    let (target, rel) = resolve_inside_vault(&vault, rel_str, true)?;
    let mut document = cmd_read(vault_str, &rel)?;
    if document["noteKind"].as_str() != Some("journal") {
        return Err("Weather synchronization requires a Journal note".to_string());
    }
    let existing = document["journalView"]["weather"].as_str().unwrap_or("");
    if summary.trim().is_empty() || (!replace_existing && !existing.trim().is_empty()) {
        document["weatherWriteApplied"] = json!(false);
        return Ok(document);
    }
    let raw = fs::read_to_string(&target).map_err(|e| format!("Cannot read '{}': {}", rel, e))?;
    let updates = json!({ "weather": summary.trim() });
    let updated = apply_check_in_updates(&raw, updates.as_object().unwrap());
    let changed = updated != raw;
    if changed { atomic_write_inside_vault(&vault, &rel, &updated)?; }
    let mut document = cmd_read(vault_str, &rel)?;
    document["weatherWriteApplied"] = json!(changed);
    Ok(document)
}

pub fn cmd_daily_with_check_in(
    vault_str: &str,
    date_opt: Option<&str>,
    folder_opt: Option<&str>,
    format_opt: Option<&str>,
    mood_opt: Option<&str>,
    energy_opt: Option<&str>,
    weight_opt: Option<&str>,
) -> Result<Value, String> {
    let vault_canon = resolve_vault_root(vault_str)?;
    let now_secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let (year, month, day) = if let Some(d_str) = date_opt.filter(|s| !s.trim().is_empty()) {
        let parts: Vec<&str> = d_str.trim().split('-').collect();
        if parts.len() == 3 {
            let y = parts[0].parse::<i32>().map_err(|_| "Invalid year")?;
            let m = parts[1].parse::<u32>().map_err(|_| "Invalid month")?;
            let d = parts[2].parse::<u32>().map_err(|_| "Invalid day")?;
            if !(1..=12).contains(&m) || !(1..=31).contains(&d) {
                return Err("Date out of range".to_string());
            }
            (y, m, d)
        } else {
            return Err("Expected date in YYYY-MM-DD format".to_string());
        }
    } else {
        civil_from_days((now_secs / 86400) as i64)
    };

    let target_iso = format!("{:04}-{:02}-{:02}", year, month, day);

    // First check if a journal note for this date already exists in the vault
    let mut flat_files = Vec::new();
    let mut notes = Vec::new();
    let _ = scan_directory_recursive(&vault_canon, &vault_canon, &mut flat_files, &mut notes);
    let target_rel_path = if let Some(existing) = notes.iter().find(|n| n.journal_date.as_deref() == Some(target_iso.as_str())) {
        existing.rel_path.clone()
    } else {
        let folder = folder_opt
            .filter(|s| !s.trim().is_empty())
            .unwrap_or("00_Capture/01_Journal");
        let fmt = format_opt
            .filter(|s| !s.trim().is_empty())
            .unwrap_or("YYYY/MMMM/DD-MM-YYYY-dddd");
        let rel_path = format_daily_note_rel_path(folder, fmt, year, month, day);
        let wd = weekday_name(weekday_monday_zero(year, month, day));
        let nice_title = format!("{}, {} {:02}, {:04}", wd, month_name(month), day, year);
        let created = cmd_create(vault_str, &rel_path, Some(&nice_title), "daily")?;
        let created_rel = created["relPath"].as_str().unwrap_or(&rel_path).to_string();
        let _ = cmd_set_frontmatter(vault_str, &created_rel, &json!({ "created": target_iso }).to_string());
        created_rel
    };

    let mut fm_updates = serde_json::Map::new();
    if let Some(m) = mood_opt.map(|s| s.trim()) {
        fm_updates.insert("mood".to_string(), Value::String(m.to_string()));
    }
    if let Some(e) = energy_opt.map(|s| s.trim()) {
        fm_updates.insert("energy".to_string(), Value::String(e.to_string()));
    }
    if let Some(w) = weight_opt.map(|s| s.trim()) {
        fm_updates.insert("weight".to_string(), Value::String(w.to_string()));
    }
    if !fm_updates.is_empty() {
        let (target, rel) = resolve_inside_vault(&vault_canon, &target_rel_path, true)?;
        let raw = fs::read_to_string(&target).map_err(|e| format!("Cannot read '{}': {}", rel, e))?;
        let updated = apply_check_in_updates(&raw, &fm_updates);
        if updated != raw {
            atomic_write_inside_vault(&vault_canon, &rel, &updated)?;
        }
    }
    cmd_read(vault_str, &target_rel_path)
}

pub fn cmd_daily(
    vault_str: &str,
    date_opt: Option<&str>,
    folder_opt: Option<&str>,
    format_opt: Option<&str>,
) -> Result<Value, String> {
    cmd_daily_with_check_in(vault_str, date_opt, folder_opt, format_opt, None, None, None)
}

fn read_calendar_plugin_settings(vault_canon: &Path) -> (usize, bool, String) {
    let mut words_per_dot = 250usize;
    let mut show_weekly = false;
    let mut week_start = "monday".to_string();
    let cfg_path = vault_canon.join(".obsidian/plugins/calendar/data.json");
    if let Ok(raw) = fs::read_to_string(&cfg_path) {
        if let Ok(val) = serde_json::from_str::<Value>(&raw) {
            if let Some(wpd) = val.get("wordsPerDot").and_then(|v| v.as_u64()) {
                if wpd > 0 {
                    words_per_dot = (wpd as usize).clamp(1, 10000);
                }
            }
            if let Some(sw) = val.get("showWeeklyNote").and_then(|v| v.as_bool()) {
                show_weekly = sw;
            }
            if let Some(ws) = val.get("weekStart").and_then(|v| v.as_str()) {
                let low = ws.trim().to_ascii_lowercase();
                if low == "sunday" || low == "monday" {
                    week_start = low;
                }
            }
        }
    }
    (words_per_dot, show_weekly, week_start)
}

fn iso_week_number(year: i32, month: u32, day: u32) -> u32 {
    let days_from_civil = |y: i32, m: u32, d: u32| -> i64 {
        let y_adj = if m <= 2 { y - 1 } else { y } as i64;
        let era = if y_adj >= 0 { y_adj } else { y_adj - 399 } / 400;
        let yoe = (y_adj - era * 400) as u64;
        let m_adj = if m > 2 { m - 3 } else { m + 9 } as u64;
        let doy = (153 * m_adj + 2) / 5 + d as u64 - 1;
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
        era * 146097 + doe as i64 - 719468
    };
    let wd = weekday_monday_zero(year, month, day) as i64; // 0=Mon..6=Sun
    let thursday_serial = days_from_civil(year, month, day) + (3 - wd);
    let (iso_year, _, _) = civil_from_days(thursday_serial);
    let jan4_serial = days_from_civil(iso_year, 1, 4);
    let jan4_wd = weekday_monday_zero(iso_year, 1, 4) as i64;
    let week1_mon = jan4_serial - jan4_wd;
    ((thursday_serial - week1_mon) / 7 + 1).clamp(1, 53) as u32
}

fn collect_calendar_journal_tasks_recursive(
    vault_canon: &Path,
    dir: &Path,
    journal_by_date: &mut HashMap<String, (String, usize, usize, usize)>,
) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    let mut collected: Vec<_> = entries.flatten().collect();
    collected.sort_by_key(|e| e.file_name());
    for entry in collected {
        let fname = entry.file_name().to_string_lossy().to_string();
        if should_skip_entry(&fname) {
            continue;
        }
        let Ok(ft) = entry.file_type() else { continue };
        if ft.is_symlink() {
            continue;
        }
        let full_path = entry.path();
        if ft.is_dir() {
            if full_path != vault_canon && full_path.join(".git").exists() {
                continue;
            }
            collect_calendar_journal_tasks_recursive(vault_canon, &full_path, journal_by_date);
        } else if ft.is_file() {
            let ext = full_path
                .extension()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or_default();
            if classify_extension(&ext).0 != FileCategory::Markdown {
                continue;
            }
            let rel_path = full_path
                .strip_prefix(vault_canon)
                .map(|p| p.to_string_lossy().replace('\\', "/"))
                .unwrap_or_default();
            let stem = full_path
                .file_stem()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or_else(|| fname.clone());
            let Some(date_iso) = detect_journal_date_from_path(&rel_path, &stem) else {
                continue;
            };
            let Ok(meta) = entry.metadata() else { continue };
            if meta.len() > 4 * 1024 * 1024 {
                continue;
            }
            let Ok(content) = fs::read_to_string(&full_path) else { continue };
            let lines: Vec<String> = content.lines().map(|s| s.to_string()).collect();
            let (_, _, _, body_start) = parse_frontmatter(&lines);
            let mut open_tasks = 0usize;
            let mut done_tasks = 0usize;
            let mut word_count = 0usize;
            let mut in_fence = false;
            for line in lines.iter().skip(body_start) {
                let t = line.trim();
                if t.starts_with("```") {
                    in_fence = !in_fence;
                    continue;
                }
                if in_fence || t.is_empty() {
                    continue;
                }
                word_count += t
                    .split_whitespace()
                    .filter(|w| w.chars().any(|c| c.is_alphanumeric()))
                    .count();
                let lb = t.as_bytes();
                if matches!(lb.first(), Some(b'-' | b'*' | b'+' | b'T' | b'D')) {
                    if let Some((_, todo_st, _)) = parse_list_or_task_line(line) {
                        if !todo_st.is_empty() {
                            if todo_st == "DONE" {
                                done_tasks += 1;
                            } else {
                                open_tasks += 1;
                            }
                        }
                    }
                }
            }
            journal_by_date.insert(date_iso, (rel_path, open_tasks, done_tasks, word_count));
        }
    }
}

pub fn cmd_calendar(vault_str: &str, year: i32, month: u32) -> Result<Value, String> {
    cmd_calendar_with_today(vault_str, year, month, None)
}

pub fn cmd_calendar_with_today(
    vault_str: &str,
    year: i32,
    month: u32,
    today_opt: Option<&str>,
) -> Result<Value, String> {
    if !(1..=12).contains(&month) {
        return Err("Month must be between 1 and 12".to_string());
    }
    let vault_canon = resolve_vault_root(vault_str)?;
    let (words_per_dot, show_weekly, week_start) = read_calendar_plugin_settings(&vault_canon);
    let mut journal_by_date: HashMap<String, (String, usize, usize, usize)> = HashMap::new();
    collect_calendar_journal_tasks_recursive(&vault_canon, &vault_canon, &mut journal_by_date);

    let first_wd_mon = weekday_monday_zero(year, month, 1); // 0 = Mon .. 6 = Sun
    let first_wd = if week_start == "sunday" {
        (first_wd_mon + 1) % 7
    } else {
        first_wd_mon
    };
    let dim = days_in_month(year, month);
    let (prev_year, prev_month) = if month == 1 {
        (year - 1, 12)
    } else {
        (year, month - 1)
    };
    let (next_year, next_month) = if month == 12 {
        (year + 1, 1)
    } else {
        (year, month + 1)
    };
    let prev_dim = days_in_month(prev_year, prev_month);

    let today_iso = if let Some(t) = today_opt.filter(|s| s.len() == 10 && s.as_bytes()[4] == b'-' && s.as_bytes()[7] == b'-') {
        t.to_string()
    } else {
        let now_secs = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        let (today_y, today_m, today_d) = civil_from_days((now_secs / 86400) as i64);
        format!("{:04}-{:02}-{:02}", today_y, today_m, today_d)
    };

    let build_cell = |cy: i32, cm: u32, cd: u32, in_month: bool| -> Value {
        let date_str = format!("{:04}-{:02}-{:02}", cy, cm, cd);
        let j = journal_by_date.get(&date_str);
        let has_journal = j.is_some();
        let open_tasks = j.map(|x| x.1).unwrap_or(0);
        let done_tasks = j.map(|x| x.2).unwrap_or(0);
        let word_count = j.map(|x| x.3).unwrap_or(0);
        let solid_dots = if has_journal {
            (word_count / words_per_dot).clamp(1, 5)
        } else {
            0
        };
        json!({
            "day": cd,
            "month": cm,
            "year": cy,
            "dateStr": date_str,
            "inMonth": in_month,
            "isToday": date_str == today_iso,
            "hasJournal": has_journal,
            "journalPath": j.map(|x| x.0.as_str()).unwrap_or(""),
            "openTasks": open_tasks,
            "doneTasks": done_tasks,
            "wordCount": word_count,
            "solidDots": solid_dots,
            "hasOpenTasks": open_tasks > 0,
            "weekNumber": iso_week_number(cy, cm, cd),
        })
    };

    let mut cells = Vec::with_capacity(42);
    for idx in 0..first_wd {
        let d = prev_dim - first_wd + 1 + idx;
        cells.push(build_cell(prev_year, prev_month, d, false));
    }
    for d in 1..=dim {
        cells.push(build_cell(year, month, d, true));
    }
    let mut next_d = 1u32;
    while cells.len() < 42 {
        cells.push(build_cell(next_year, next_month, next_d, false));
        next_d += 1;
    }

    Ok(json!({
        "ok": true,
        "year": year,
        "month": month,
        "monthName": month_name(month),
        "monthShortName": month_short_name(month),
        "headerLabel": format!("{} {:04}", month_short_name(month), year),
        "todayStr": today_iso,
        "wordsPerDot": words_per_dot,
        "showWeeklyNote": show_weekly,
        "weekStart": week_start,
        "cells": cells,
    }))
}

pub fn toggle_line_todo_syntax(line: &str) -> String {
    if let Some(pos) = line.find("- [ ] ") {
        let mut out = String::with_capacity(line.len());
        out.push_str(&line[..pos]);
        out.push_str("- [x] ");
        out.push_str(&line[pos + 6..]);
        return out;
    }
    if let Some(pos) = line.find("- [x] ").or_else(|| line.find("- [X] ")) {
        let mut out = String::with_capacity(line.len());
        out.push_str(&line[..pos]);
        out.push_str("- [ ] ");
        out.push_str(&line[pos + 6..]);
        return out;
    }
    for (from, to) in [
        ("- TODO ", "- DOING "),
        ("- DOING ", "- DONE "),
        ("- DONE ", "- TODO "),
        ("TODO ", "DOING "),
        ("DOING ", "DONE "),
        ("DONE ", "TODO "),
    ] {
        if let Some(pos) = line.find(from) {
            let mut out = String::with_capacity(line.len() + 2);
            out.push_str(&line[..pos]);
            out.push_str(to);
            out.push_str(&line[pos + from.len()..]);
            return out;
        }
    }
    line.to_string()
}

pub fn cmd_toggle_todo(vault_str: &str, rel_str: &str, line_1based: usize) -> Result<Value, String> {
    if line_1based == 0 {
        return Err("Line number must be >= 1".to_string());
    }
    let vault_canon = resolve_vault_root(vault_str)?;
    let (target_path, rel_norm) = resolve_inside_vault(&vault_canon, rel_str, true)?;
    let raw = fs::read_to_string(&target_path).map_err(|e| format!("Cannot read '{}': {}", rel_norm, e))?;
    let trailing_newline = raw.ends_with('\n');
    let mut lines: Vec<String> = raw.lines().map(|s| s.to_string()).collect();
    if line_1based > lines.len() {
        return Err(format!("Line {} out of range (total {})", line_1based, lines.len()));
    }
    lines[line_1based - 1] = toggle_line_todo_syntax(&lines[line_1based - 1]);
    let mut updated = lines.join("\n");
    if trailing_newline {
        updated.push('\n');
    }
    atomic_write_inside_vault(&vault_canon, &rel_norm, &updated)?;
    cmd_read(vault_str, &rel_norm)
}

pub fn cmd_link_mention(
    vault_str: &str,
    source_rel_str: &str,
    line_1based: usize,
    target_title: &str,
) -> Result<Value, String> {
    if line_1based == 0 || target_title.trim().is_empty() {
        return Err("Invalid line number or target title".to_string());
    }
    let vault_canon = resolve_vault_root(vault_str)?;
    let (source_path, rel_norm) = resolve_inside_vault(&vault_canon, source_rel_str, true)?;
    let raw = fs::read_to_string(&source_path).map_err(|e| format!("Cannot read '{}': {}", rel_norm, e))?;
    let trailing_newline = raw.ends_with('\n');
    let mut lines: Vec<String> = raw.lines().map(|s| s.to_string()).collect();
    if line_1based > lines.len() {
        return Err("Line number out of range".to_string());
    }
    let line = &lines[line_1based - 1];
    let lower_line = line.to_ascii_lowercase();
    let lower_target = target_title.trim().to_ascii_lowercase();
    if let Some(pos) = lower_line.find(&lower_target) {
        let end = pos + target_title.trim().len();
        if line.is_char_boundary(pos) && line.is_char_boundary(end) {
            let mut new_line = String::with_capacity(line.len() + 4);
            new_line.push_str(&line[..pos]);
            new_line.push_str("[[");
            new_line.push_str(&line[pos..end]);
            new_line.push_str("]]");
            new_line.push_str(&line[end..]);
            lines[line_1based - 1] = new_line;
        }
    }
    let mut updated = lines.join("\n");
    if trailing_newline {
        updated.push('\n');
    }
    atomic_write_inside_vault(&vault_canon, &rel_norm, &updated)?;
    Ok(json!({
        "ok": true,
        "sourcePath": rel_norm,
        "line": line_1based,
    }))
}

pub fn cmd_search(vault_str: &str, query: &str) -> Result<Value, String> {
    let vault_canon = resolve_vault_root(vault_str)?;
    let q = query.trim().to_ascii_lowercase();
    if q.is_empty() {
        return Ok(json!({ "ok": true, "results": [] }));
    }
    let mut flat_files = Vec::new();
    let mut notes = Vec::new();
    let _ = scan_directory_recursive(&vault_canon, &vault_canon, &mut flat_files, &mut notes);

    let clean_q_tag = q.trim_start_matches('#');
    let score_note = |(orig_idx, note): (usize, &ParsedNoteSummary)| -> Option<(i64, usize, Value)> {
        let mut score = 0i64;
        let mut matched_line = 1usize;
        let mut matched_snippet: Option<String> = None;

        if contains_ascii_case_insensitive(&note.title, &q) {
            score += 500;
            if starts_with_ascii_case_insensitive(&note.title, &q) {
                score += 300;
            }
        }
        if contains_ascii_case_insensitive(&note.rel_path, &q) {
            score += 200;
        }
        if !clean_q_tag.is_empty()
            && note
                .tags
                .iter()
                .any(|t| contains_ascii_case_insensitive(t, clean_q_tag))
        {
            score += 400;
        }
        for (idx, line) in note.lines.iter().enumerate() {
            if contains_ascii_case_insensitive(line, &q) {
                if score < 100 || matched_line == 1 {
                    matched_line = idx + 1;
                    matched_snippet = Some(line.trim().chars().take(160).collect());
                }
                score += 50;
            }
        }
        if score > 0 {
            let final_snippet = matched_snippet.unwrap_or_else(|| note.snippet.clone());
            Some((
                score,
                orig_idx,
                json!({
                    "relPath": note.rel_path,
                    "title": note.title,
                    "folder": note.folder,
                    "category": "markdown",
                    "line": matched_line,
                    "snippet": final_snippet,
                    "tags": note.tags,
                    "score": score,
                }),
            ))
        } else {
            None
        }
    };

    let worker_count = std::thread::available_parallelism()
        .map(|n| n.get().clamp(1, 8))
        .unwrap_or(4);
    let mut results: Vec<(i64, usize, Value)> = if notes.len() < 32 || worker_count <= 1 {
        notes.iter().enumerate().filter_map(score_note).collect()
    } else {
        let chunk_size = notes.len().div_ceil(worker_count);
        std::thread::scope(|s| {
            let handles: Vec<_> = notes
                .chunks(chunk_size)
                .enumerate()
                .map(|(chunk_idx, chunk)| {
                    let base = chunk_idx * chunk_size;
                    s.spawn(move || {
                        chunk
                            .iter()
                            .enumerate()
                            .filter_map(|(i, note)| score_note((base + i, note)))
                            .collect::<Vec<_>>()
                    })
                })
                .collect();
            let mut merged = Vec::new();
            for h in handles {
                if let Ok(part) = h.join() {
                    merged.extend(part);
                }
            }
            merged
        })
    };

    results.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1.cmp(&b.1)));
    let top: Vec<Value> = results.into_iter().take(50).map(|(_, _, v)| v).collect();
    Ok(json!({
        "ok": true,
        "query": query,
        "results": top,
    }))
}

pub fn cmd_update_block(
    vault_str: &str,
    rel_str: &str,
    line_start_1based: usize,
    line_end_1based: usize,
    replacement: &str,
) -> Result<Value, String> {
    if line_start_1based == 0 || line_end_1based < line_start_1based {
        return Err("Invalid block line range".to_string());
    }
    let vault_canon = resolve_vault_root(vault_str)?;
    let (target_path, rel_norm) = resolve_inside_vault(&vault_canon, rel_str, true)?;
    let raw = fs::read_to_string(&target_path).map_err(|e| format!("Cannot read '{}': {}", rel_norm, e))?;
    let trailing_newline = raw.ends_with('\n');
    let mut lines: Vec<String> = raw.lines().map(|s| s.to_string()).collect();
    let new_lines: Vec<String> = if replacement.is_empty() {
        vec![String::new()]
    } else {
        replacement.lines().map(|s| s.to_string()).collect()
    };
    if line_start_1based == lines.len() + 1 && line_end_1based == lines.len() + 1 {
        lines.extend(new_lines);
    } else {
        if line_end_1based > lines.len() {
            return Err(format!(
                "Block range {}..={} out of bounds (total {})",
                line_start_1based,
                line_end_1based,
                lines.len()
            ));
        }
        lines.splice((line_start_1based - 1)..line_end_1based, new_lines);
    }
    let mut updated = lines.join("\n");
    if trailing_newline {
        updated.push('\n');
    }
    atomic_write_inside_vault(&vault_canon, &rel_norm, &updated)?;
    cmd_read(vault_str, &rel_norm)
}

#[cfg(target_os = "linux")]
fn rename_without_overwrite(source: &Path, destination: &Path) -> std::io::Result<()> {
    use std::ffi::{CString, c_char, c_int, c_uint};
    use std::os::unix::ffi::OsStrExt;

    unsafe extern "C" {
        fn renameat2(oldfd: c_int, old: *const c_char, newfd: c_int, new: *const c_char, flags: c_uint) -> c_int;
    }
    let source = CString::new(source.as_os_str().as_bytes())?;
    let destination = CString::new(destination.as_os_str().as_bytes())?;
    // AT_FDCWD and RENAME_NOREPLACE: the kernel rejects every occupied destination,
    // including directories and dangling symlinks, without a check/rename race.
    let result = unsafe { renameat2(-100, source.as_ptr(), -100, destination.as_ptr(), 1) };
    if result == 0 {
        Ok(())
    } else {
        Err(std::io::Error::last_os_error())
    }
}

#[cfg(not(target_os = "linux"))]
fn rename_without_overwrite(_source: &Path, _destination: &Path) -> std::io::Result<()> {
    Err(std::io::Error::new(std::io::ErrorKind::Unsupported, "Atomic trash moves require Linux renameat2"))
}

fn prune_tree_json_recursive(node: &mut Value, deleted_rel: &str, deleted_prefix: &str) -> bool {
    let rel = node["relPath"].as_str().unwrap_or("");
    if !rel.is_empty() && (rel == deleted_rel || rel.starts_with(deleted_prefix)) {
        return false;
    }
    if node["isDir"].as_bool() == Some(true) {
        let mut note_sum = 0u64;
        if let Some(children) = node.get_mut("children").and_then(|v| v.as_array_mut()) {
            let mut kept = Vec::with_capacity(children.len());
            for mut child in children.drain(..) {
                if prune_tree_json_recursive(&mut child, deleted_rel, deleted_prefix) {
                    note_sum += child["noteCount"].as_u64().unwrap_or(0);
                    kept.push(child);
                }
            }
            *children = kept;
        }
        node["noteCount"] = Value::Number(note_sum.into());
    }
    true
}

fn prune_single_cache_file(path_str: &str, deleted_rel: &str, prefix: &str) {
    let Ok(raw) = fs::read_to_string(path_str) else {
        return;
    };
    let Ok(mut root) = serde_json::from_str::<Value>(&raw) else {
        return;
    };
    let matches_del = |p: &str| p == deleted_rel || p.starts_with(prefix);

    if let Some(obj) = root.as_object_mut() {
        obj.remove("_scanSignature");
    }
    if let Some(entries) = root.get_mut("_cachedEntries").and_then(|v| v.as_object_mut()) {
        entries.retain(|k, _| !matches_del(k));
    }
    if let Some(files) = root.get_mut("files").and_then(|v| v.as_array_mut()) {
        files.retain(|f| !f["relPath"].as_str().is_some_and(matches_del));
    }
    if let Some(recent) = root.get_mut("recentNotes").and_then(|v| v.as_array_mut()) {
        recent.retain(|f| !f["relPath"].as_str().is_some_and(matches_del));
    }
    if let Some(cols) = root.get_mut("collections").and_then(|v| v.as_object_mut()) {
        for (_, arr_val) in cols.iter_mut() {
            if let Some(arr) = arr_val.as_array_mut() {
                arr.retain(|item| !item["relPath"].as_str().is_some_and(matches_del));
            }
        }
    }
    if let Some(tree) = root.get_mut("tree") {
        let _ = prune_tree_json_recursive(tree, deleted_rel, prefix);
    }
    let _ = write_json_cache_atomically(path_str, &root);
}

fn prune_rel_path_from_cache_file(cache_path_str: &str, deleted_rel: &str) {
    let trimmed = normalize_cache_path(cache_path_str);
    if trimmed.is_empty() || deleted_rel.trim().is_empty() {
        return;
    }
    let prefix = format!("{}/", deleted_rel);
    prune_single_cache_file(trimmed, deleted_rel, &prefix);
    let sidecar = ui_sidecar_cache_path(trimmed);
    if !sidecar.is_empty() && Path::new(&sidecar).is_file() {
        prune_single_cache_file(&sidecar, deleted_rel, &prefix);
    }
}

pub fn cmd_delete(vault_str: &str, rel_str: &str) -> Result<Value, String> {
    cmd_delete_with_cache(vault_str, rel_str, None)
}

pub fn cmd_delete_with_cache(
    vault_str: &str,
    rel_str: &str,
    cache_file_opt: Option<&str>,
) -> Result<Value, String> {
    let vault_canon = resolve_vault_root(vault_str)?;
    let (target_path, rel_norm) = resolve_inside_vault(&vault_canon, rel_str, true)?;
    let meta = fs::metadata(&target_path).map_err(|e| format!("Cannot stat '{}': {}", rel_norm, e))?;
    if !meta.is_file() && !meta.is_dir() {
        return Err(format!("'{}' is not a regular file or directory", rel_norm));
    }
    let trash_dir = vault_canon.join(".trash");
    fs::create_dir_all(&trash_dir).map_err(|e| format!("Cannot create .trash directory: {}", e))?;
    let trash_dir = fs::canonicalize(&trash_dir).map_err(|e| format!("Cannot resolve .trash directory: {}", e))?;
    if !trash_dir.starts_with(&vault_canon) {
        return Err("Trash directory escapes vault boundary".to_string());
    }
    let fname = target_path
        .file_name()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| "deleted.md".to_string());
    let mut suffix = 0_u64;
    let dest_path = loop {
        let candidate = trash_dir.join(if suffix == 0 { fname.clone() } else { format!("{}-{}", suffix, fname) });
        match rename_without_overwrite(&target_path, &candidate) {
            Ok(()) => break candidate,
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {
                suffix = suffix.checked_add(1).ok_or_else(|| "Trash destination space exhausted".to_string())?;
            }
            Err(e) => return Err(format!("Cannot move '{}' to .trash: {}", rel_norm, e)),
        }
    };
    let trash_rel = dest_path
        .strip_prefix(&vault_canon)
        .map(|p| p.to_string_lossy().replace('\\', "/"))
        .unwrap_or_else(|_| ".trash".to_string());
    if let Some(cache_path) = cache_file_opt {
        prune_rel_path_from_cache_file(cache_path, &rel_norm);
    }
    Ok(json!({
        "ok": true,
        "deletedPath": rel_norm,
        "trashPath": trash_rel,
    }))
}

pub fn cmd_rename(vault_str: &str, old_rel_str: &str, new_rel_str: &str) -> Result<Value, String> {
    let vault_canon = resolve_vault_root(vault_str)?;
    let (old_target_path, old_rel_norm) = resolve_inside_vault(&vault_canon, old_rel_str, true)?;
    let (new_target_path, new_rel_norm) = resolve_inside_vault(&vault_canon, new_rel_str, false)?;
    if !old_target_path.exists() {
        return Err(format!("'{}' does not exist", old_rel_norm));
    }
    if new_target_path.exists() {
        return Err(format!("'{}' already exists", new_rel_norm));
    }
    if let Some(parent) = new_target_path.parent() {
        fs::create_dir_all(parent).map_err(|e| format!("Cannot create parent directory: {}", e))?;
    }
    fs::rename(&old_target_path, &new_target_path)
        .map_err(|e| format!("Cannot rename '{}' to '{}': {}", old_rel_norm, new_rel_norm, e))?;
    Ok(json!({
        "ok": true,
        "oldPath": old_rel_norm,
        "newPath": new_rel_norm,
    }))
}

pub fn cmd_duplicate(vault_str: &str, rel_str: &str) -> Result<Value, String> {
    let vault_canon = resolve_vault_root(vault_str)?;
    let (target_path, rel_norm) = resolve_inside_vault(&vault_canon, rel_str, true)?;
    let meta = fs::metadata(&target_path).map_err(|e| format!("Cannot stat '{}': {}", rel_norm, e))?;
    if !meta.is_file() {
        return Err(format!("'{}' is not a regular file", rel_norm));
    }
    let content = fs::read_to_string(&target_path)
        .map_err(|e| format!("Cannot read '{}': {}", rel_norm, e))?;
    let parent_rel = Path::new(&rel_norm)
        .parent()
        .map(|p| p.to_string_lossy().replace('\\', "/"))
        .unwrap_or_default();
    let stem = target_path
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| "Note".to_string());
    let ext = target_path
        .extension()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| "md".to_string());
    let mut copy_idx = 1usize;
    let new_rel = loop {
        let suffix = if copy_idx == 1 {
            " (Copy)".to_string()
        } else {
            format!(" (Copy {})", copy_idx)
        };
        let fname = format!("{}{}.{}", stem, suffix, ext);
        let cand_rel = if parent_rel.is_empty() {
            fname
        } else {
            format!("{}/{}", parent_rel, fname)
        };
        if !vault_canon.join(&cand_rel).exists() {
            break cand_rel;
        }
        copy_idx += 1;
    };
    let (_, saved_rel) = atomic_write_inside_vault(&vault_canon, &new_rel, &content)?;
    cmd_read(vault_str, &saved_rel)
}

pub fn cmd_hotkeys(vault_str: &str) -> Result<Value, String> {
    let vault_canon = resolve_vault_root(vault_str)?;
    let hotkeys = read_vault_obsidian_hotkeys(&vault_canon);
    Ok(json!({
        "ok": true,
        "vaultHotkeys": hotkeys,
    }))
}

fn format_yaml_scalar(v: &Value) -> String {
    match v {
        Value::Bool(b) => b.to_string(),
        Value::Number(n) => n.to_string(),
        Value::Null => String::new(),
        Value::String(s) => {
            let collapsed = s.replace("\r\n", " ").replace('\n', " ").replace('\r', " ");
            let trimmed = collapsed.trim();
            if trimmed.is_empty() {
                "\"\"".to_string()
            } else if trimmed == "true" || trimmed == "false" || trimmed.parse::<f64>().is_ok() {
                trimmed.to_string()
            } else if trimmed.contains(':')
                || trimmed.contains('#')
                || trimmed.contains('[')
                || trimmed.contains(']')
                || trimmed.contains('{')
                || trimmed.contains('}')
                || trimmed.contains('"')
                || trimmed.contains('\'')
                || trimmed.contains('&')
                || trimmed.contains('*')
                || trimmed.contains('!')
                || trimmed.contains('|')
                || trimmed.contains('>')
                || trimmed.contains('%')
                || trimmed.contains('@')
            {
                format!("\"{}\"", trimmed.replace('\\', "\\\\").replace('"', "\\\""))
            } else {
                trimmed.to_string()
            }
        }
        Value::Array(arr) => {
            let items: Vec<String> = arr
                .iter()
                .map(|x| match x {
                    Value::String(s) => format!("\"{}\"", s.replace('\\', "\\\\").replace('"', "\\\"")),
                    other => other.to_string(),
                })
                .collect();
            format!("[{}]", items.join(", "))
        }
        other => other.to_string(),
    }
}

fn format_yaml_list_item(item: &Value) -> String {
    match item {
        Value::String(s) => {
            let collapsed = s.replace("\r\n", " ").replace('\n', " ").replace('\r', " ");
            let t = collapsed.trim();
            if t.starts_with('"') && t.ends_with('"') && t.len() >= 2 {
                t.to_string()
            } else if t.contains(':')
                || t.contains('#')
                || t.contains('[')
                || t.contains(']')
                || t.contains('"')
            {
                format!("\"{}\"", t.replace('\\', "\\\\").replace('"', "\\\""))
            } else {
                t.to_string()
            }
        }
        other => other.to_string(),
    }
}

fn is_delete_sentinel(val: &Value) -> bool {
    val.as_object()
        .and_then(|m| m.get("__nexus_delete__"))
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
}

fn append_yaml_entry(out: &mut Vec<String>, key: &str, val: &Value, indent: usize) {
    if is_delete_sentinel(val) {
        return;
    }
    let pad = " ".repeat(indent);
    match val {
        Value::Array(arr) => {
            if arr.is_empty() {
                out.push(format!("{}{}: []", pad, key));
                return;
            }
            out.push(format!("{}{}:", pad, key));
            let item_pad = " ".repeat(indent + 2);
            for item in arr {
                match item {
                    Value::Object(obj) => {
                        if obj.is_empty() {
                            out.push(format!("{}- {{}}", item_pad));
                        } else {
                            let mut first = true;
                            for (ok, ov) in obj {
                                if is_delete_sentinel(ov) {
                                    continue;
                                }
                                if first {
                                    first = false;
                                    match ov {
                                        Value::Object(_) | Value::Array(_) => {
                                            out.push(format!("{}-", item_pad));
                                            append_yaml_entry(out, ok, ov, indent + 4);
                                        }
                                        _ => {
                                            out.push(format!("{}- {}: {}", item_pad, ok, format_yaml_scalar(ov)));
                                        }
                                    }
                                } else {
                                    append_yaml_entry(out, ok, ov, indent + 4);
                                }
                            }
                        }
                    }
                    _ => {
                        out.push(format!("{}- {}", item_pad, format_yaml_list_item(item)));
                    }
                }
            }
        }
        Value::Object(obj) => {
            if obj.is_empty() {
                out.push(format!("{}{}: {{}}", pad, key));
                return;
            }
            out.push(format!("{}{}:", pad, key));
            for (ok, ov) in obj {
                append_yaml_entry(out, ok, ov, indent + 2);
            }
        }
        _ => {
            out.push(format!("{}{}: {}", pad, key, format_yaml_scalar(val)));
        }
    }
}

pub fn apply_frontmatter_updates_to_content(raw: &str, updates: &serde_json::Map<String, Value>) -> String {
    let trailing_newline = raw.ends_with('\n');
    let lines: Vec<String> = raw.lines().map(|s| s.to_string()).collect();

    if lines.first().map(|s| s.trim()) == Some("---") {
        if let Some(end_idx) = lines.iter().skip(1).position(|s| {
            let t = s.trim();
            t == "---" || t == "..."
        }) {
            let fm_end = end_idx + 1;
            let mut new_fm: Vec<String> = Vec::new();
            new_fm.push("---".to_string());
            let mut updated_keys: HashSet<String> = HashSet::new();
            let mut i = 1usize;
            while i < fm_end {
                let line = &lines[i];
                let trimmed = line.trim();
                if !trimmed.starts_with('-') && !line.starts_with(' ') && !line.starts_with('\t') {
                    if let Some((k_raw, _)) = trimmed.split_once(':') {
                        let k_clean = k_raw.trim();
                        if let Some((u_key, u_val)) = updates
                            .iter()
                            .find(|(uk, _)| uk.eq_ignore_ascii_case(k_clean))
                        {
                            updated_keys.insert(u_key.to_ascii_lowercase());
                            // Skip any following indented lines belonging to this key
                            let mut next_i = i + 1;
                            while next_i < fm_end {
                                let nl = &lines[next_i];
                                let nt = nl.trim();
                                if nt.starts_with("- ") || nl.starts_with(' ') || nl.starts_with('\t') {
                                    next_i += 1;
                                } else {
                                    break;
                                }
                            }
                            append_yaml_entry(&mut new_fm, k_clean, u_val, 0);
                            i = next_i;
                            continue;
                        }
                    }
                }
                new_fm.push(line.clone());
                i += 1;
            }
            for (u_key, u_val) in updates {
                if !updated_keys.contains(&u_key.to_ascii_lowercase()) {
                    append_yaml_entry(&mut new_fm, u_key, u_val, 0);
                }
            }
            new_fm.push("---".to_string());
            for body_line in &lines[fm_end + 1..] {
                new_fm.push(body_line.clone());
            }
            let mut out = new_fm.join("\n");
            if trailing_newline || !out.ends_with('\n') {
                out.push('\n');
            }
            return out;
        }
    }

    // No existing frontmatter: prepend a new YAML frontmatter block
    let mut new_lines: Vec<String> = Vec::new();
    new_lines.push("---".to_string());
    for (u_key, u_val) in updates {
        append_yaml_entry(&mut new_lines, u_key, u_val, 0);
    }
    new_lines.push("---".to_string());
    if !lines.is_empty() {
        new_lines.extend(lines);
    }
    let mut out = new_lines.join("\n");
    if trailing_newline || !out.ends_with('\n') {
        out.push('\n');
    }
    out
}

pub fn cmd_set_frontmatter(vault_str: &str, rel_str: &str, updates_json_str: &str) -> Result<Value, String> {
    let vault_canon = resolve_vault_root(vault_str)?;
    let (target_path, rel_norm) = resolve_inside_vault(&vault_canon, rel_str, true)?;
    let parsed: Value = serde_json::from_str(updates_json_str)
        .map_err(|e| format!("Invalid --updates JSON: {}", e))?;
    let Some(updates_obj) = parsed.as_object() else {
        return Err("--updates must be a JSON object".to_string());
    };
    let raw = fs::read_to_string(&target_path)
        .map_err(|e| format!("Cannot read '{}': {}", rel_norm, e))?;
    // A check-in edit must preserve legacy YAML/body bytes just like `daily`.
    // Keep the general scalar/array serializer for all other property updates.
    let check_in_only = !updates_obj.is_empty() && updates_obj.iter().all(|(key, value)| {
        (key.eq_ignore_ascii_case("mood") || key.eq_ignore_ascii_case("energy")) && value.is_string()
    });
    let updated = if updates_obj.is_empty() {
        raw.clone()
    } else if check_in_only {
        apply_check_in_updates(&raw, updates_obj)
    } else {
        apply_frontmatter_updates_to_content(&raw, updates_obj)
    };
    atomic_write_inside_vault(&vault_canon, &rel_norm, &updated)?;
    cmd_read(vault_str, &rel_norm)
}

fn run_curl_json(url: &str) -> Option<Value> {
    run_curl_json_with_headers(url, &[])
}

fn run_curl_json_with_headers(url: &str, headers: &[(&str, &str)]) -> Option<Value> {
    let mut cmd = std::process::Command::new("curl");
    cmd.args(["-sS", "-L", "--max-time", "7"]);
    for (k, v) in headers {
        cmd.arg("-H").arg(format!("{}: {}", k, v));
    }
    cmd.arg(url);
    let out = cmd.output().ok()?;
    if !out.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&out.stdout);
    serde_json::from_str::<Value>(&text).ok()
}

fn strip_html_to_plain_text(input: &str) -> String {
    if input.trim().is_empty() {
        return String::new();
    }
    let mut no_tags = String::with_capacity(input.len());
    let mut in_tag = false;
    let mut tag_buf = String::new();
    for ch in input.chars() {
        if ch == '<' {
            in_tag = true;
            tag_buf.clear();
        } else if ch == '>' && in_tag {
            in_tag = false;
            let tl = tag_buf.trim().to_ascii_lowercase();
            if tl.starts_with("br") || tl == "/p" || tl == "p" || tl == "/li" {
                no_tags.push(' ');
            }
        } else if in_tag {
            tag_buf.push(ch);
        } else {
            no_tags.push(ch);
        }
    }
    let decoded = no_tags
        .replace("&amp;", "&")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&apos;", "'")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&nbsp;", " ");
    decoded.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn read_vault_api_settings(vault_canon: &Path) -> BTreeMap<String, String> {
    let settings_path = vault_canon.join("90_System/93_Configuration/settings.md");
    if let Ok(s_raw) = fs::read_to_string(&settings_path) {
        let s_lines: Vec<String> = s_raw.lines().map(|s| s.to_string()).collect();
        let (sp, _, _, _) = parse_frontmatter(&s_lines);
        return sp;
    }
    BTreeMap::new()
}

fn read_mock_api_json(kind: &str, suffix: &str) -> Option<Value> {
    let mock_dir = env::var("ALIS_NEXUS_MOCK_API_DIR").ok()?;
    let trimmed = mock_dir.trim();
    if trimmed.is_empty() {
        return None;
    }
    let base = Path::new(trimmed);
    let candidates = match kind {
        "tv" | "tvseries" => vec![
            format!("tv_{}.json", suffix),
            format!("tvseries_{}.json", suffix),
        ],
        other => vec![format!("{}_{}.json", other, suffix)],
    };
    for fname in candidates {
        let p = base.join(fname);
        if let Ok(raw) = fs::read_to_string(&p) {
            if let Ok(val) = serde_json::from_str::<Value>(&raw) {
                return Some(val);
            }
        }
    }
    None
}

fn extract_meal_ingredients_and_steps(meal: &Value) -> (Vec<String>, Vec<String>) {
    let mut ingredients = Vec::new();
    for idx in 1..=20 {
        let ing_key = format!("strIngredient{}", idx);
        let mea_key = format!("strMeasure{}", idx);
        let ing = meal[&ing_key].as_str().unwrap_or("").trim();
        let mea = meal[&mea_key].as_str().unwrap_or("").trim();
        if !ing.is_empty() {
            if mea.is_empty() {
                ingredients.push(ing.to_string());
            } else {
                ingredients.push(format!("{} | {}", ing, mea));
            }
        }
    }
    let raw_ins = meal["strInstructions"].as_str().unwrap_or("").trim();
    let mut instructions = Vec::new();
    for line in raw_ins.lines() {
        let cleaned = line
            .trim()
            .trim_start_matches(|c: char| c.is_ascii_digit() || c == '.' || c == ')' || c == '-')
            .trim();
        if cleaned.is_empty() {
            continue;
        }
        if cleaned.eq_ignore_ascii_case("step") || cleaned.to_ascii_lowercase().starts_with("step ") && cleaned.len() <= 8 {
            continue;
        }
        instructions.push(cleaned.to_string());
    }
    (ingredients, instructions)
}

fn enrich_steam_appdetails(app_id: &str) -> Option<Value> {
    if app_id.trim().is_empty() {
        return None;
    }
    if let Some(mock_val) = read_mock_api_json("game", "sync") {
        if mock_val[app_id]["data"].is_object() {
            return Some(mock_val[app_id]["data"].clone());
        }
        if mock_val["data"].is_object() {
            return Some(mock_val["data"].clone());
        }
    }
    if env::var("ALIS_NEXUS_MOCK_API_DIR").ok().filter(|s| !s.trim().is_empty()).is_some() {
        return None;
    }
    let url = format!(
        "https://store.steampowered.com/api/appdetails?appids={}&l=english",
        url_encode_simple(app_id.trim())
    );
    let resp = run_curl_json(&url)?;
    let data = &resp[app_id.trim()]["data"];
    if data.is_object() {
        Some(data.clone())
    } else {
        None
    }
}

fn fetch_wikipedia_place_summary(wiki_title: &str) -> (String, String) {
    let cleaned = wiki_title
        .trim()
        .split_once(':')
        .map(|(_, t)| t.trim())
        .unwrap_or_else(|| wiki_title.trim());
    if cleaned.is_empty() {
        return (String::new(), String::new());
    }
    if let Some(mock_wiki) = read_mock_api_json("place", "wiki") {
        let cover = mock_wiki["originalimage"]["source"]
            .as_str()
            .or_else(|| mock_wiki["thumbnail"]["source"].as_str())
            .unwrap_or("")
            .to_string();
        let extract = mock_wiki["extract"].as_str().unwrap_or("").trim().to_string();
        return (cover, extract);
    }
    if env::var("ALIS_NEXUS_MOCK_API_DIR").ok().filter(|s| !s.trim().is_empty()).is_some() {
        return (String::new(), String::new());
    }
    let slug = url_encode_simple(&cleaned.replace(' ', "_"));
    let url = format!("https://en.wikipedia.org/api/rest_v1/page/summary/{}", slug);
    let headers = [("User-Agent", "AlisNexus/1.0 (Linux; Quickshell)")];
    if let Some(resp) = run_curl_json_with_headers(&url, &headers) {
        let cover = resp["originalimage"]["source"]
            .as_str()
            .or_else(|| resp["thumbnail"]["source"].as_str())
            .unwrap_or("")
            .to_string();
        let extract = resp["extract"].as_str().unwrap_or("").trim().to_string();
        return (cover, extract);
    }
    (String::new(), String::new())
}

fn normalize_mock_or_candidate_list(val: &Value, limit: usize) -> Option<Vec<Value>> {
    let arr = if let Some(a) = val["results"].as_array() {
        if a.first().is_some_and(|x| x.get("frontmatter").is_some()) {
            Some(a.clone())
        } else {
            None
        }
    } else if let Some(a) = val.as_array() {
        if a.first().is_some_and(|x| x.get("frontmatter").is_some()) {
            Some(a.clone())
        } else {
            None
        }
    } else if val.get("frontmatter").is_some() {
        Some(vec![val.clone()])
    } else {
        None
    };
    arr.map(|mut v| {
        v.truncate(limit);
        v
    })
}

fn search_api_candidates_internal(
    kind_raw: &str,
    query: &str,
    limit: usize,
    settings_props: &BTreeMap<String, String>,
    mock_suffix: &str,
) -> Vec<Value> {
    let q = query.trim();
    if q.is_empty() {
        return Vec::new();
    }
    let limit = limit.clamp(1, 20);
    let kind_lower_tmp = kind_raw.trim().to_ascii_lowercase();
    let kind = match kind_lower_tmp.as_str() {
        "tvseries" | "tv_series" | "tv" => "tv",
        "movies" | "movie" | "tmdb" => "movie",
        "books" | "book" => "book",
        "games" | "game" | "steam" => "game",
        "recipes" | "recipe" => "recipe",
        "places" | "place" => "place",
        other => other,
    };

    let mock_opt = read_mock_api_json(kind, mock_suffix)
        .or_else(|| if mock_suffix != "search" { read_mock_api_json(kind, "search") } else { None });
    if let Some(ref mv) = mock_opt {
        if let Some(direct) = normalize_mock_or_candidate_list(mv, limit) {
            return direct;
        }
    }
    let offline_mock_mode = env::var("ALIS_NEXUS_MOCK_API_DIR")
        .ok()
        .filter(|s| !s.trim().is_empty())
        .is_some();

    let tmdb_key = settings_props
        .get("tmdb_key")
        .cloned()
        .filter(|s| !s.trim().is_empty())
        .or_else(|| env::var("ALIS_NEXUS_TMDB_KEY").ok().filter(|s| !s.trim().is_empty()))
        .unwrap_or_default();
    let omdb_key = settings_props
        .get("omdb_key")
        .cloned()
        .filter(|s| !s.trim().is_empty())
        .or_else(|| env::var("ALIS_NEXUS_OMDB_KEY").ok().filter(|s| !s.trim().is_empty()))
        .unwrap_or_default();
    let rawg_key = settings_props
        .get("rawg_key")
        .cloned()
        .filter(|s| !s.trim().is_empty())
        .or_else(|| env::var("ALIS_NEXUS_RAWG_KEY").ok().filter(|s| !s.trim().is_empty()))
        .unwrap_or_default();

    let mut out = Vec::new();

    match kind {
        "movie" => {
            if !tmdb_key.is_empty() && !offline_mock_mode {
                let url = format!(
                    "https://api.themoviedb.org/3/search/movie?api_key={}&query={}",
                    tmdb_key.trim(),
                    url_encode_simple(q)
                );
                if let Some(resp) = run_curl_json(&url) {
                    if let Some(arr) = resp["results"].as_array() {
                        for item in arr.iter().take(limit) {
                            let title = item["title"].as_str().unwrap_or("").trim().to_string();
                            if title.is_empty() {
                                continue;
                            }
                            let id = item["id"].to_string().trim_matches('"').to_string();
                            let year = item["release_date"]
                                .as_str()
                                .and_then(|d| d.get(..4))
                                .unwrap_or("")
                                .to_string();
                            let poster = item["poster_path"]
                                .as_str()
                                .filter(|p| !p.is_empty())
                                .map(|p| format!("https://image.tmdb.org/t/p/w500{}", p))
                                .unwrap_or_default();
                            let backdrop = item["backdrop_path"]
                                .as_str()
                                .filter(|p| !p.is_empty())
                                .map(|p| format!("https://image.tmdb.org/t/p/w1280{}", p))
                                .unwrap_or_default();
                            let rating = item["vote_average"]
                                .as_f64()
                                .filter(|&v| v > 0.0)
                                .map(|v| format!("{:.1}", v))
                                .unwrap_or_default();
                            let overview = item["overview"].as_str().unwrap_or("").trim().to_string();
                            let mut fm = serde_json::Map::new();
                            fm.insert("categories".into(), json!(["[[Movies]]"]));
                            fm.insert("title".into(), json!(title));
                            fm.insert("tmdb_id".into(), json!(id));
                            if !poster.is_empty() { fm.insert("poster".into(), json!(poster)); }
                            if !backdrop.is_empty() { fm.insert("backdrop".into(), json!(backdrop)); }
                            if !year.is_empty() { fm.insert("year".into(), json!(year)); }
                            if !rating.is_empty() { fm.insert("scoreImdb".into(), json!(rating)); }
                            if !overview.is_empty() { fm.insert("plot".into(), json!(overview)); }
                            out.push(json!({
                                "id": id,
                                "title": title,
                                "year": year,
                                "creator": "",
                                "subtitle": if year.is_empty() { "Movie".to_string() } else { format!("{} · Movie", year) },
                                "cover": poster,
                                "rating": rating,
                                "overview": overview,
                                "source": "TMDB",
                                "frontmatter": fm,
                                "body_sections": {}
                            }));
                        }
                    }
                }
            }
            if out.is_empty() && !omdb_key.is_empty() && !offline_mock_mode {
                let url = format!(
                    "https://www.omdbapi.com/?apikey={}&type=movie&s={}",
                    omdb_key.trim(),
                    url_encode_simple(q)
                );
                if let Some(resp) = run_curl_json(&url) {
                    if let Some(arr) = resp["Search"].as_array() {
                        for item in arr.iter().take(limit) {
                            let title = item["Title"].as_str().unwrap_or("").trim().to_string();
                            if title.is_empty() { continue; }
                            let id = item["imdbID"].as_str().unwrap_or("").to_string();
                            let year = item["Year"].as_str().unwrap_or("").trim().to_string();
                            let poster = item["Poster"].as_str().filter(|p| *p != "N/A").unwrap_or("").to_string();
                            let mut fm = serde_json::Map::new();
                            fm.insert("categories".into(), json!(["[[Movies]]"]));
                            fm.insert("title".into(), json!(title));
                            if !id.is_empty() { fm.insert("imdbId".into(), json!(id)); }
                            if !poster.is_empty() { fm.insert("poster".into(), json!(poster)); }
                            if !year.is_empty() { fm.insert("year".into(), json!(year)); }
                            out.push(json!({
                                "id": id,
                                "title": title,
                                "year": year,
                                "creator": "",
                                "subtitle": year,
                                "cover": poster,
                                "rating": "",
                                "overview": "",
                                "source": "OMDb",
                                "frontmatter": fm,
                                "body_sections": {}
                            }));
                        }
                    }
                }
            }
            if out.is_empty() {
                let itunes_resp = if let Some(ref mv) = mock_opt {
                    Some(mv.clone())
                } else if !offline_mock_mode {
                    let url = format!(
                        "https://itunes.apple.com/search?media=movie&entity=movie&limit={}&term={}",
                        limit,
                        url_encode_simple(q)
                    );
                    run_curl_json(&url)
                } else {
                    None
                };
                if let Some(resp) = itunes_resp {
                    if let Some(arr) = resp["results"].as_array() {
                        for item in arr.iter().take(limit) {
                            let title = item["trackName"]
                                .as_str()
                                .or_else(|| item["title"].as_str())
                                .unwrap_or("")
                                .trim()
                                .to_string();
                            if title.is_empty() { continue; }
                            let id = item["trackId"]
                                .as_i64()
                                .map(|n| n.to_string())
                                .or_else(|| item["id"].as_str().map(|s| s.to_string()))
                                .unwrap_or_default();
                            let year = item["releaseDate"]
                                .as_str()
                                .and_then(|d| d.get(..4))
                                .or_else(|| item["year"].as_str())
                                .unwrap_or("")
                                .to_string();
                            let director = item["artistName"]
                                .as_str()
                                .or_else(|| item["director"].as_str())
                                .unwrap_or("")
                                .trim()
                                .to_string();
                            let genre = item["primaryGenreName"]
                                .as_str()
                                .or_else(|| item["genre"].as_str())
                                .unwrap_or("")
                                .trim()
                                .to_string();
                            let cover = item["artworkUrl100"]
                                .as_str()
                                .map(|u| u.replace("100x100bb", "600x600bb"))
                                .or_else(|| item["poster"].as_str().map(|s| s.to_string()))
                                .unwrap_or_default();
                            let runtime = item["trackTimeMillis"]
                                .as_i64()
                                .filter(|&ms| ms > 0)
                                .map(|ms| format!("{} min", ms / 60000))
                                .unwrap_or_default();
                            let overview = item["longDescription"]
                                .as_str()
                                .or_else(|| item["shortDescription"].as_str())
                                .or_else(|| item["overview"].as_str())
                                .unwrap_or("")
                                .trim()
                                .to_string();
                            let mut fm = serde_json::Map::new();
                            fm.insert("categories".into(), json!(["[[Movies]]"]));
                            fm.insert("title".into(), json!(title));
                            if !cover.is_empty() { fm.insert("poster".into(), json!(cover)); }
                            if !year.is_empty() { fm.insert("year".into(), json!(year)); }
                            if !director.is_empty() { fm.insert("director".into(), json!([director])); }
                            if !genre.is_empty() { fm.insert("genre".into(), json!([format!("[[{}]]", genre)])); }
                            if !runtime.is_empty() { fm.insert("runtime".into(), json!(runtime)); }
                            if !overview.is_empty() { fm.insert("plot".into(), json!(overview)); }
                            let subtitle = [year.as_str(), director.as_str(), genre.as_str()]
                                .iter()
                                .filter(|s| !s.is_empty())
                                .copied()
                                .collect::<Vec<_>>()
                                .join(" · ");
                            out.push(json!({
                                "id": id,
                                "title": title,
                                "year": year,
                                "creator": director,
                                "subtitle": subtitle,
                                "cover": cover,
                                "rating": "",
                                "overview": overview,
                                "source": "iTunes",
                                "frontmatter": fm,
                                "body_sections": {}
                            }));
                        }
                    }
                }
            }
        }
        "tv" => {
            if !tmdb_key.is_empty() && !offline_mock_mode {
                let url = format!(
                    "https://api.themoviedb.org/3/search/tv?api_key={}&query={}",
                    tmdb_key.trim(),
                    url_encode_simple(q)
                );
                if let Some(resp) = run_curl_json(&url) {
                    if let Some(arr) = resp["results"].as_array() {
                        for item in arr.iter().take(limit) {
                            let title = item["name"].as_str().unwrap_or("").trim().to_string();
                            if title.is_empty() { continue; }
                            let id = item["id"].to_string().trim_matches('"').to_string();
                            let year = item["first_air_date"].as_str().and_then(|d| d.get(..4)).unwrap_or("").to_string();
                            let poster = item["poster_path"]
                                .as_str()
                                .filter(|p| !p.is_empty())
                                .map(|p| format!("https://image.tmdb.org/t/p/w500{}", p))
                                .unwrap_or_default();
                            let backdrop = item["backdrop_path"]
                                .as_str()
                                .filter(|p| !p.is_empty())
                                .map(|p| format!("https://image.tmdb.org/t/p/w1280{}", p))
                                .unwrap_or_default();
                            let rating = item["vote_average"]
                                .as_f64()
                                .filter(|&v| v > 0.0)
                                .map(|v| format!("{:.1}", v))
                                .unwrap_or_default();
                            let overview = item["overview"].as_str().unwrap_or("").trim().to_string();
                            let mut fm = serde_json::Map::new();
                            fm.insert("categories".into(), json!(["[[TV Series]]"]));
                            fm.insert("title".into(), json!(title));
                            fm.insert("tmdb_id".into(), json!(id));
                            if !poster.is_empty() { fm.insert("poster".into(), json!(poster)); }
                            if !backdrop.is_empty() { fm.insert("backdrop".into(), json!(backdrop)); }
                            if !year.is_empty() { fm.insert("year".into(), json!(year)); }
                            if !rating.is_empty() { fm.insert("scoreImdb".into(), json!(rating)); }
                            if !overview.is_empty() { fm.insert("plot".into(), json!(overview)); }
                            out.push(json!({
                                "id": id,
                                "title": title,
                                "year": year,
                                "creator": "",
                                "subtitle": if year.is_empty() { "TV Series".to_string() } else { format!("{} · TV Series", year) },
                                "cover": poster,
                                "rating": rating,
                                "overview": overview,
                                "source": "TMDB",
                                "frontmatter": fm,
                                "body_sections": {}
                            }));
                        }
                    }
                }
            }
            if out.is_empty() {
                let tvmaze_resp = if let Some(ref mv) = mock_opt {
                    Some(mv.clone())
                } else if !offline_mock_mode {
                    let url = format!("https://api.tvmaze.com/search/shows?q={}", url_encode_simple(q));
                    run_curl_json(&url)
                } else {
                    None
                };
                if let Some(resp) = tvmaze_resp {
                    let list_opt = resp.as_array().or_else(|| resp["results"].as_array());
                    if let Some(arr) = list_opt {
                        for entry in arr.iter().take(limit) {
                            let show = if entry.get("show").is_some() { &entry["show"] } else { entry };
                            let title = show["name"].as_str().unwrap_or("").trim().to_string();
                            if title.is_empty() { continue; }
                            let id = show["id"]
                                .as_i64()
                                .map(|n| n.to_string())
                                .or_else(|| show["id"].as_str().map(|s| s.to_string()))
                                .unwrap_or_default();
                            let year = show["premiered"].as_str().and_then(|d| d.get(..4)).unwrap_or("").to_string();
                            let network = show["network"]["name"]
                                .as_str()
                                .or_else(|| show["webChannel"]["name"].as_str())
                                .unwrap_or("")
                                .trim()
                                .to_string();
                            let cover = show["image"]["original"]
                                .as_str()
                                .or_else(|| show["image"]["medium"].as_str())
                                .unwrap_or("")
                                .to_string();
                            let genres: Vec<String> = show["genres"]
                                .as_array()
                                .map(|ga| ga.iter().filter_map(|v| v.as_str().map(|s| format!("[[{}]]", s))).collect())
                                .unwrap_or_default();
                            let rating = show["rating"]["average"]
                                .as_f64()
                                .filter(|&v| v > 0.0)
                                .map(|v| format!("{:.1}", v))
                                .unwrap_or_default();
                            let airing_status = show["status"].as_str().unwrap_or("").trim().to_string();
                            let runtime = show["runtime"]
                                .as_i64()
                                .or_else(|| show["averageRuntime"].as_i64())
                                .filter(|&m| m > 0)
                                .map(|m| format!("{} min", m))
                                .unwrap_or_default();
                            let overview = strip_html_to_plain_text(show["summary"].as_str().unwrap_or(""));
                            let mut fm = serde_json::Map::new();
                            fm.insert("categories".into(), json!(["[[TV Series]]"]));
                            fm.insert("title".into(), json!(title));
                            if !cover.is_empty() { fm.insert("poster".into(), json!(cover)); }
                            if !year.is_empty() { fm.insert("year".into(), json!(year)); }
                            if !network.is_empty() { fm.insert("networks".into(), json!(network)); }
                            if !airing_status.is_empty() { fm.insert("airing_status".into(), json!(airing_status)); }
                            if !runtime.is_empty() { fm.insert("runtime".into(), json!(runtime)); }
                            if !rating.is_empty() { fm.insert("scoreImdb".into(), json!(rating)); }
                            if !genres.is_empty() { fm.insert("genre".into(), json!(genres)); }
                            if !overview.is_empty() { fm.insert("plot".into(), json!(overview)); }
                            let subtitle = [year.as_str(), network.as_str(), airing_status.as_str()]
                                .iter()
                                .filter(|s| !s.is_empty())
                                .copied()
                                .collect::<Vec<_>>()
                                .join(" · ");
                            out.push(json!({
                                "id": id,
                                "title": title,
                                "year": year,
                                "creator": network,
                                "subtitle": subtitle,
                                "cover": cover,
                                "rating": rating,
                                "overview": overview,
                                "source": "TVMaze",
                                "frontmatter": fm,
                                "body_sections": {}
                            }));
                        }
                    }
                }
            }
        }
        "book" => {
            let ol_resp = if let Some(ref mv) = mock_opt {
                Some(mv.clone())
            } else if !offline_mock_mode {
                let url = format!(
                    "https://openlibrary.org/search.json?q={}&limit={}",
                    url_encode_simple(q),
                    limit
                );
                run_curl_json(&url)
            } else {
                None
            };
            if let Some(resp) = ol_resp {
                if let Some(docs) = resp["docs"].as_array() {
                    for doc in docs.iter().take(limit) {
                        let title = doc["title"].as_str().unwrap_or("").trim().to_string();
                        if title.is_empty() { continue; }
                        let id = doc["key"].as_str().unwrap_or("").to_string();
                        let author = doc["author_name"]
                            .as_array()
                            .and_then(|a| a.first())
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .trim()
                            .to_string();
                        let year = doc["first_publish_year"]
                            .as_i64()
                            .map(|y| y.to_string())
                            .unwrap_or_default();
                        let cover = doc["cover_i"]
                            .as_i64()
                            .map(|cid| format!("https://covers.openlibrary.org/b/id/{}-L.jpg", cid))
                            .or_else(|| doc["cover"].as_str().map(|s| s.to_string()))
                            .unwrap_or_default();
                        let pages = doc["number_of_pages_median"].as_i64().unwrap_or(0);
                        let isbn = doc["isbn"]
                            .as_array()
                            .and_then(|a| a.first())
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string();
                        let genres: Vec<String> = doc["subject"]
                            .as_array()
                            .map(|sa| sa.iter().take(3).filter_map(|v| v.as_str().map(|s| format!("[[{}]]", s))).collect())
                            .unwrap_or_default();
                        let overview = doc["first_sentence"]
                            .as_array()
                            .and_then(|a| a.first())
                            .and_then(|v| v.as_str())
                            .or_else(|| doc["first_sentence"].as_str())
                            .or_else(|| doc["description"].as_str())
                            .unwrap_or("")
                            .trim()
                            .to_string();
                        let mut fm = serde_json::Map::new();
                        fm.insert("Title".into(), json!(title));
                        if !author.is_empty() { fm.insert("Author".into(), json!(author)); }
                        if !cover.is_empty() { fm.insert("Cover".into(), json!(cover)); }
                        if pages > 0 { fm.insert("TotalPages".into(), json!(pages)); }
                        if !year.is_empty() { fm.insert("published".into(), json!(year)); }
                        if !isbn.is_empty() { fm.insert("isbn".into(), json!(isbn)); }
                        if !genres.is_empty() { fm.insert("Genre".into(), json!(genres)); }
                        if !overview.is_empty() { fm.insert("description".into(), json!(overview)); }
                        fm.insert("tags".into(), json!(["#Book"]));
                        let subtitle = [author.as_str(), year.as_str()]
                            .iter()
                            .filter(|s| !s.is_empty())
                            .copied()
                            .collect::<Vec<_>>()
                            .join(" · ");
                        out.push(json!({
                            "id": id,
                            "title": title,
                            "year": year,
                            "creator": author,
                            "subtitle": subtitle,
                            "cover": cover,
                            "rating": "",
                            "overview": overview,
                            "source": "OpenLibrary",
                            "frontmatter": fm,
                            "body_sections": {
                                "synopsis": overview
                            }
                        }));
                    }
                }
            }
            // Google Books fallback or enrichment when OpenLibrary has no overview/results
            let needs_gb = !offline_mock_mode
                && (out.is_empty()
                    || out.first().is_some_and(|first| {
                        first["overview"].as_str().unwrap_or("").is_empty()
                            || first["cover"].as_str().unwrap_or("").is_empty()
                    }));
            let gb_resp = if needs_gb {
                let url = format!(
                    "https://www.googleapis.com/books/v1/volumes?q={}&maxResults={}",
                    url_encode_simple(q),
                    limit
                );
                run_curl_json(&url)
            } else if out.is_empty() {
                mock_opt.clone()
            } else {
                None
            };
            if let Some(resp) = gb_resp {
                if let Some(items) = resp["items"].as_array() {
                    if !out.is_empty() {
                        if let Some(vi) = items.first().and_then(|it| it.get("volumeInfo")) {
                            let desc = vi["description"].as_str().unwrap_or("").trim().to_string();
                            let thumb = vi["imageLinks"]["thumbnail"]
                                .as_str()
                                .map(|u| u.replace("http://", "https://"))
                                .unwrap_or_default();
                            let pages = vi["pageCount"].as_i64().unwrap_or(0);
                            if let Some(first_mut) = out.first_mut() {
                                if first_mut["overview"].as_str().unwrap_or("").is_empty() && !desc.is_empty() {
                                    first_mut["overview"] = json!(desc);
                                    first_mut["body_sections"]["synopsis"] = json!(desc);
                                    if let Some(fm) = first_mut["frontmatter"].as_object_mut() {
                                        fm.insert("description".into(), json!(desc));
                                    }
                                }
                                if first_mut["cover"].as_str().unwrap_or("").is_empty() && !thumb.is_empty() {
                                    first_mut["cover"] = json!(thumb);
                                    if let Some(fm) = first_mut["frontmatter"].as_object_mut() {
                                        fm.insert("Cover".into(), json!(thumb));
                                    }
                                }
                                if pages > 0 {
                                    if let Some(fm) = first_mut["frontmatter"].as_object_mut() {
                                        if !fm.contains_key("TotalPages") {
                                            fm.insert("TotalPages".into(), json!(pages));
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        for it in items.iter().take(limit) {
                            let vi = &it["volumeInfo"];
                            let title = vi["title"].as_str().unwrap_or("").trim().to_string();
                            if title.is_empty() { continue; }
                            let id = it["id"].as_str().unwrap_or("").to_string();
                            let author = vi["authors"]
                                .as_array()
                                .and_then(|a| a.first())
                                .and_then(|v| v.as_str())
                                .unwrap_or("")
                                .to_string();
                            let year = vi["publishedDate"]
                                .as_str()
                                .and_then(|d| d.get(..4))
                                .unwrap_or("")
                                .to_string();
                            let cover = vi["imageLinks"]["thumbnail"]
                                .as_str()
                                .map(|u| u.replace("http://", "https://"))
                                .unwrap_or_default();
                            let pages = vi["pageCount"].as_i64().unwrap_or(0);
                            let overview = vi["description"].as_str().unwrap_or("").trim().to_string();
                            let genres: Vec<String> = vi["categories"]
                                .as_array()
                                .map(|ca| ca.iter().take(3).filter_map(|v| v.as_str().map(|s| format!("[[{}]]", s))).collect())
                                .unwrap_or_default();
                            let mut fm = serde_json::Map::new();
                            fm.insert("Title".into(), json!(title));
                            if !author.is_empty() { fm.insert("Author".into(), json!(author)); }
                            if !cover.is_empty() { fm.insert("Cover".into(), json!(cover)); }
                            if pages > 0 { fm.insert("TotalPages".into(), json!(pages)); }
                            if !year.is_empty() { fm.insert("published".into(), json!(year)); }
                            if !genres.is_empty() { fm.insert("Genre".into(), json!(genres)); }
                            if !overview.is_empty() { fm.insert("description".into(), json!(overview)); }
                            fm.insert("tags".into(), json!(["#Book"]));
                            let subtitle = [author.as_str(), year.as_str()]
                                .iter()
                                .filter(|s| !s.is_empty())
                                .copied()
                                .collect::<Vec<_>>()
                                .join(" · ");
                            out.push(json!({
                                "id": id,
                                "title": title,
                                "year": year,
                                "creator": author,
                                "subtitle": subtitle,
                                "cover": cover,
                                "rating": "",
                                "overview": overview,
                                "source": "Google Books",
                                "frontmatter": fm,
                                "body_sections": {
                                    "synopsis": overview
                                }
                            }));
                        }
                    }
                }
            }
        }
        "game" => {
            if !rawg_key.is_empty() && !offline_mock_mode {
                let url = format!(
                    "https://api.rawg.io/api/games?key={}&page_size={}&search={}",
                    rawg_key.trim(),
                    limit,
                    url_encode_simple(q)
                );
                if let Some(resp) = run_curl_json(&url) {
                    if let Some(arr) = resp["results"].as_array() {
                        for item in arr.iter().take(limit) {
                            let title = item["name"].as_str().unwrap_or("").trim().to_string();
                            if title.is_empty() { continue; }
                            let id = item["id"].to_string().trim_matches('"').to_string();
                            let year = item["released"].as_str().and_then(|d| d.get(..4)).unwrap_or("").to_string();
                            let cover = item["background_image"].as_str().unwrap_or("").to_string();
                            let mc = item["metacritic"].as_i64().unwrap_or(0);
                            let genres: Vec<String> = item["genres"]
                                .as_array()
                                .map(|ga| ga.iter().filter_map(|g| g["name"].as_str().map(|s| s.to_string())).collect())
                                .unwrap_or_default();
                            let mut fm = serde_json::Map::new();
                            fm.insert("title".into(), json!(title));
                            fm.insert("rawg_id".into(), json!(id));
                            if !cover.is_empty() {
                                fm.insert("cover".into(), json!(cover));
                                fm.insert("backdrop".into(), json!(cover));
                            }
                            if !year.is_empty() { fm.insert("release_year".into(), json!(year)); }
                            if mc > 0 { fm.insert("metacritic".into(), json!(mc)); }
                            if !genres.is_empty() { fm.insert("genre".into(), json!(genres)); }
                            fm.insert("tags".into(), json!(["Game"]));
                            out.push(json!({
                                "id": id,
                                "title": title,
                                "year": year,
                                "creator": "",
                                "subtitle": year,
                                "cover": cover,
                                "rating": if mc > 0 { mc.to_string() } else { String::new() },
                                "overview": "",
                                "source": "RAWG",
                                "frontmatter": fm,
                                "body_sections": {}
                            }));
                        }
                    }
                }
            }
            if out.is_empty() {
                let steam_resp = if let Some(ref mv) = mock_opt.as_ref().filter(|v| v.get("items").is_some()) {
                    Some((*mv).clone())
                } else if let Some(search_mv) = read_mock_api_json("game", "search").filter(|v| v.get("items").is_some()) {
                    Some(search_mv)
                } else if !offline_mock_mode {
                    let url = format!(
                        "https://store.steampowered.com/api/storesearch/?term={}&l=english&cc=US",
                        url_encode_simple(q)
                    );
                    run_curl_json(&url)
                } else {
                    None
                };
                if let Some(resp) = steam_resp {
                    if let Some(items) = resp["items"].as_array() {
                        for (idx, item) in items.iter().take(limit).enumerate() {
                            let title = item["name"].as_str().unwrap_or("").trim().to_string();
                            if title.is_empty() { continue; }
                            let app_id = item["id"]
                                .as_i64()
                                .map(|n| n.to_string())
                                .or_else(|| item["id"].as_str().map(|s| s.to_string()))
                                .unwrap_or_default();
                            let cover = if !app_id.is_empty() {
                                format!(
                                    "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/{}/library_600x900.jpg",
                                    app_id
                                )
                            } else {
                                item["tiny_image"].as_str().unwrap_or("").to_string()
                            };
                            let backdrop = if !app_id.is_empty() {
                                format!(
                                    "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/{}/header.jpg",
                                    app_id
                                )
                            } else {
                                String::new()
                            };
                            let mut platforms = Vec::new();
                            if item["platforms"]["windows"].as_bool() == Some(true) { platforms.push("PC".to_string()); }
                            if item["platforms"]["mac"].as_bool() == Some(true) { platforms.push("Mac".to_string()); }
                            if item["platforms"]["linux"].as_bool() == Some(true) { platforms.push("Linux".to_string()); }
                            if platforms.is_empty() { platforms.push("PC".to_string()); }

                            let mut dev = item["developer"].as_str().unwrap_or("").trim().to_string();
                            let mut pub_name = item["publisher"].as_str().unwrap_or("").trim().to_string();
                            let mut year = item["release_year"].as_str().unwrap_or("").trim().to_string();
                            let mut mc = item["metascore"]
                                .as_str()
                                .and_then(|s| s.parse::<i64>().ok())
                                .or_else(|| item["metascore"].as_i64())
                                .unwrap_or(0);
                            let mut overview = item["short_description"].as_str().unwrap_or("").trim().to_string();
                            let mut genres: Vec<String> = Vec::new();

                            if idx == 0 && !app_id.is_empty() {
                                if let Some(details) = enrich_steam_appdetails(&app_id) {
                                    if dev.is_empty() {
                                        dev = details["developers"]
                                            .as_array()
                                            .and_then(|a| a.first())
                                            .and_then(|v| v.as_str())
                                            .unwrap_or("")
                                            .to_string();
                                    }
                                    if pub_name.is_empty() {
                                        pub_name = details["publishers"]
                                            .as_array()
                                            .and_then(|a| a.first())
                                            .and_then(|v| v.as_str())
                                            .unwrap_or("")
                                            .to_string();
                                    }
                                    if overview.is_empty() {
                                        overview = strip_html_to_plain_text(
                                            details["short_description"].as_str().unwrap_or(""),
                                        );
                                    }
                                    if mc == 0 {
                                        mc = details["metacritic"]["score"].as_i64().unwrap_or(0);
                                    }
                                    if year.is_empty() {
                                        if let Some(rd) = details["release_date"]["date"].as_str() {
                                            if let Some(y4) = rd.split(|c: char| !c.is_ascii_digit()).find(|seg| seg.len() == 4) {
                                                year = y4.to_string();
                                            }
                                        }
                                    }
                                    if let Some(ga) = details["genres"].as_array() {
                                        genres = ga
                                            .iter()
                                            .filter_map(|g| g["description"].as_str().map(|s| s.to_string()))
                                            .collect();
                                    }
                                }
                            }

                            let mut fm = serde_json::Map::new();
                            fm.insert("title".into(), json!(title));
                            if !app_id.is_empty() { fm.insert("steamappid".into(), json!(app_id)); }
                            if !cover.is_empty() { fm.insert("cover".into(), json!(cover)); }
                            if !backdrop.is_empty() { fm.insert("backdrop".into(), json!(backdrop)); }
                            if !dev.is_empty() { fm.insert("developer".into(), json!(dev)); }
                            if !pub_name.is_empty() { fm.insert("publisher".into(), json!(pub_name)); }
                            if !year.is_empty() { fm.insert("release_year".into(), json!(year)); }
                            if mc > 0 { fm.insert("metacritic".into(), json!(mc)); }
                            if !overview.is_empty() { fm.insert("description".into(), json!(overview)); }
                            if !platforms.is_empty() { fm.insert("platform".into(), json!(platforms)); }
                            if !genres.is_empty() { fm.insert("genre".into(), json!(genres)); }
                            fm.insert("tags".into(), json!(["Game"]));
                            let subtitle = [year.as_str(), dev.as_str()]
                                .iter()
                                .filter(|s| !s.is_empty())
                                .copied()
                                .collect::<Vec<_>>()
                                .join(" · ");
                            out.push(json!({
                                "id": app_id,
                                "title": title,
                                "year": year,
                                "creator": dev,
                                "subtitle": if subtitle.is_empty() { "Steam".to_string() } else { subtitle },
                                "cover": cover,
                                "rating": if mc > 0 { mc.to_string() } else { String::new() },
                                "overview": overview,
                                "source": "Steam",
                                "frontmatter": fm,
                                "body_sections": {}
                            }));
                        }
                    }
                }
            }
        }
        "recipe" => {
            let meal_resp = if let Some(ref mv) = mock_opt {
                Some(mv.clone())
            } else if !offline_mock_mode {
                let url = format!(
                    "https://www.themealdb.com/api/json/v1/1/search.php?s={}",
                    url_encode_simple(q)
                );
                run_curl_json(&url)
            } else {
                None
            };
            if let Some(resp) = meal_resp {
                if let Some(meals) = resp["meals"].as_array() {
                    for meal in meals.iter().take(limit) {
                        let title = meal["strMeal"].as_str().unwrap_or("").trim().to_string();
                        if title.is_empty() { continue; }
                        let id = meal["idMeal"].as_str().unwrap_or("").trim().to_string();
                        let category = meal["strCategory"].as_str().unwrap_or("").trim().to_string();
                        let cuisine = meal["strArea"].as_str().unwrap_or("").trim().to_string();
                        let cover = meal["strMealThumb"].as_str().unwrap_or("").trim().to_string();
                        let source_url = meal["strSource"]
                            .as_str()
                            .filter(|s| !s.trim().is_empty())
                            .or_else(|| meal["strYoutube"].as_str().filter(|s| !s.trim().is_empty()))
                            .unwrap_or("")
                            .trim()
                            .to_string();
                        let (ingredients, instructions) = extract_meal_ingredients_and_steps(meal);
                        let overview = instructions.first().cloned().unwrap_or_default();
                        let creator = [cuisine.as_str(), category.as_str()]
                            .iter()
                            .filter(|s| !s.is_empty())
                            .copied()
                            .collect::<Vec<_>>()
                            .join(" · ");
                        let mut fm = serde_json::Map::new();
                        fm.insert("categories".into(), json!(["[[Recipes]]"]));
                        fm.insert("title".into(), json!(title));
                        if !id.is_empty() { fm.insert("meal_id".into(), json!(id)); }
                        if !cover.is_empty() { fm.insert("cover".into(), json!(cover)); }
                        if !category.is_empty() { fm.insert("recipe_category".into(), json!(category)); }
                        if !cuisine.is_empty() { fm.insert("cuisine".into(), json!(cuisine)); }
                        if !source_url.is_empty() { fm.insert("source_url".into(), json!(source_url)); }
                        fm.insert("source".into(), json!("TheMealDB"));
                        if !overview.is_empty() { fm.insert("description".into(), json!(overview)); }
                        if !ingredients.is_empty() { fm.insert("ingredients".into(), json!(ingredients)); }
                        if !instructions.is_empty() { fm.insert("instructions".into(), json!(instructions)); }
                        out.push(json!({
                            "id": id,
                            "title": title,
                            "year": "",
                            "creator": creator,
                            "subtitle": creator,
                            "cover": cover,
                            "rating": "",
                            "overview": overview,
                            "source": "TheMealDB",
                            "frontmatter": fm,
                            "body_sections": {
                                "ingredients": ingredients,
                                "instructions": instructions
                            }
                        }));
                    }
                }
            }
        }
        "place" => {
            let nom_resp = if let Some(ref mv) = mock_opt {
                Some(mv.clone())
            } else if !offline_mock_mode {
                let url = format!(
                    "https://nominatim.openstreetmap.org/search?format=jsonv2&addressdetails=1&extratags=1&limit={}&q={}",
                    limit,
                    url_encode_simple(q)
                );
                let headers = [
                    ("User-Agent", "AlisNexus/1.0 (Linux; Quickshell)"),
                    ("Accept-Language", "en"),
                ];
                run_curl_json_with_headers(&url, &headers)
            } else {
                None
            };
            if let Some(resp) = nom_resp {
                let list_opt = resp.as_array().or_else(|| resp["results"].as_array());
                if let Some(arr) = list_opt {
                    for (idx, item) in arr.iter().take(limit).enumerate() {
                        let disp = item["display_name"].as_str().unwrap_or("").trim().to_string();
                        let name = item["name"]
                            .as_str()
                            .filter(|s| !s.trim().is_empty())
                            .map(|s| s.trim().to_string())
                            .unwrap_or_else(|| disp.split(',').next().unwrap_or("").trim().to_string());
                        if name.is_empty() { continue; }
                        let id = item["place_id"]
                            .as_i64()
                            .map(|n| n.to_string())
                            .or_else(|| item["osm_id"].as_i64().map(|n| n.to_string()))
                            .unwrap_or_default();
                        let lat = item["lat"].as_str().unwrap_or("").trim().to_string();
                        let lon = item["lon"].as_str().unwrap_or("").trim().to_string();
                        let coords = if !lat.is_empty() && !lon.is_empty() {
                            format!("{}, {}", lat, lon)
                        } else {
                            String::new()
                        };
                        let addr_obj = &item["address"];
                        let country = addr_obj["country"]
                            .as_str()
                            .or_else(|| item["country"].as_str())
                            .unwrap_or("")
                            .trim()
                            .to_string();
                        let city = addr_obj["city"]
                            .as_str()
                            .or_else(|| addr_obj["town"].as_str())
                            .or_else(|| addr_obj["village"].as_str())
                            .or_else(|| addr_obj["state"].as_str())
                            .or_else(|| item["city"].as_str())
                            .unwrap_or("")
                            .trim()
                            .to_string();
                        let raw_type = item["type"]
                            .as_str()
                            .or_else(|| item["category"].as_str())
                            .unwrap_or("tourist")
                            .trim()
                            .to_ascii_lowercase();
                        let place_type = if raw_type.contains("restaurant") || raw_type.contains("food") {
                            "restaurant"
                        } else if raw_type.contains("cafe") || raw_type.contains("coffee") {
                            "cafe"
                        } else if raw_type.contains("bar") || raw_type.contains("pub") {
                            "bar"
                        } else {
                            "tourist"
                        };
                        let mut cover = item["cover"].as_str().unwrap_or("").to_string();
                        let mut overview = item["overview"]
                            .as_str()
                            .or_else(|| item["description"].as_str())
                            .unwrap_or("")
                            .to_string();
                        if idx < 2 && (cover.is_empty() || overview.is_empty()) {
                            let wiki_hint = item["extratags"]["wikipedia"]
                                .as_str()
                                .filter(|s| !s.trim().is_empty())
                                .unwrap_or(&name);
                            let (w_cover, w_ext) = fetch_wikipedia_place_summary(wiki_hint);
                            if cover.is_empty() && !w_cover.is_empty() {
                                cover = w_cover;
                            }
                            if overview.is_empty() && !w_ext.is_empty() {
                                overview = w_ext;
                            }
                        }
                        if overview.is_empty() {
                            overview = disp.clone();
                        }
                        let subtitle = [city.as_str(), country.as_str()]
                            .iter()
                            .filter(|s| !s.is_empty())
                            .copied()
                            .collect::<Vec<_>>()
                            .join(", ");
                        let mut fm = serde_json::Map::new();
                        fm.insert("categories".into(), json!(["[[Places]]"]));
                        fm.insert("title".into(), json!(name));
                        if !cover.is_empty() { fm.insert("cover".into(), json!(cover)); }
                        if !disp.is_empty() { fm.insert("address".into(), json!(disp)); }
                        if !city.is_empty() { fm.insert("city".into(), json!(city)); }
                        if !country.is_empty() { fm.insert("country".into(), json!(country)); }
                        if !coords.is_empty() { fm.insert("coordinates".into(), json!(coords)); }
                        fm.insert("place_type".into(), json!(place_type));
                        if !overview.is_empty() { fm.insert("description".into(), json!(overview)); }
                        fm.insert("tags".into(), json!(["place"]));
                        out.push(json!({
                            "id": id,
                            "title": name,
                            "year": "",
                            "creator": subtitle,
                            "subtitle": subtitle,
                            "cover": cover,
                            "rating": "",
                            "overview": overview,
                            "source": "OSM",
                            "frontmatter": fm,
                            "body_sections": {}
                        }));
                    }
                }
            }
        }
        _ => {}
    }

    out
}

pub fn cmd_search_api(vault_str: &str, kind: &str, query: &str, limit: usize) -> Result<Value, String> {
    let settings_props = if vault_str.trim().is_empty() {
        BTreeMap::new()
    } else if let Ok(vault_canon) = resolve_vault_root(vault_str) {
        read_vault_api_settings(&vault_canon)
    } else {
        BTreeMap::new()
    };
    let results = search_api_candidates_internal(kind, query, limit, &settings_props, "search");
    Ok(json!({
        "ok": true,
        "kind": kind,
        "query": query,
        "results": results,
    }))
}

fn url_encode_simple(s: &str) -> String {
    let mut out = String::new();
    for b in s.as_bytes() {
        match *b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(*b as char);
            }
            b' ' => out.push_str("%20"),
            other => out.push_str(&format!("%{:02X}", other)),
        }
    }
    out
}

pub fn cmd_sync_api(vault_str: &str, rel_str: &str, api_kind: &str) -> Result<Value, String> {
    let vault_canon = resolve_vault_root(vault_str)?;
    let (target_path, rel_norm) = resolve_inside_vault(&vault_canon, rel_str, true)?;
    let raw = fs::read_to_string(&target_path)
        .map_err(|e| format!("Cannot read '{}': {}", rel_norm, e))?;
    let lines: Vec<String> = raw.lines().map(|s| s.to_string()).collect();
    let (frontmatter, _, _, _) = parse_frontmatter(&lines);
    let stem = target_path
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default();
    let title = frontmatter
        .get("title")
        .or_else(|| frontmatter.get("name"))
        .cloned()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| stem.clone());

    let settings_props = read_vault_api_settings(&vault_canon);

    let mut updates = serde_json::Map::new();
    let mut recipe_sections: Option<(Vec<String>, Vec<String>)> = None;
    let kind_lower = api_kind.trim().to_ascii_lowercase();

    // User-owned personal fields that sync-api MUST NEVER overwrite when non-empty
    let protected_user_keys: &[&str] = &[
        "rating",
        "status",
        "watched",
        "visited",
        "want_to_visit",
        "favorite",
        "bookmarked",
        "hours_played",
        "currentpage",
        "current_page",
        "datestarted",
        "datefinished",
        "ingredients_done",
        "instruction_done",
        "steps_progress",
    ];

    let merge_candidate_into_updates = |cand: &Value, dst: &mut serde_json::Map<String, Value>| {
        if let Some(fm_obj) = cand.get("frontmatter").and_then(|v| v.as_object()) {
            for (k, v) in fm_obj {
                let kl = k.to_ascii_lowercase();
                if kl == "categories" || kl == "tags" || kl == "title" {
                    if frontmatter.get(&kl).map(|s| s.trim().is_empty()).unwrap_or(true) {
                        dst.insert(k.clone(), v.clone());
                    }
                    continue;
                }
                if kl == "ingredients" || kl == "instructions" {
                    continue;
                }
                if protected_user_keys.iter().any(|p| *p == kl) {
                    if frontmatter.get(&kl).map(|s| s.trim().is_empty()).unwrap_or(true) {
                        dst.insert(k.clone(), v.clone());
                    }
                    continue;
                }
                let is_empty_val = match v {
                    Value::Null => true,
                    Value::String(s) => s.trim().is_empty(),
                    Value::Array(a) => a.is_empty(),
                    _ => false,
                };
                if !is_empty_val {
                    dst.insert(k.clone(), v.clone());
                }
            }
        }
    };

    match kind_lower.as_str() {
        "quote" => {
            let nanos = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.subsec_nanos() as usize)
                .unwrap_or(17);
            let (q, a) = pick_vault_quote_for_seed(&vault_canon, nanos);
            updates.insert("quote".to_string(), Value::String(q));
            updates.insert("quote_author".to_string(), Value::String(a));
        }
        "weather" => {
            let owm_key = settings_props
                .get("openweathermap_key")
                .cloned()
                .unwrap_or_default();
            let city = frontmatter
                .get("city")
                .cloned()
                .filter(|s| !s.is_empty())
                .or_else(|| settings_props.get("openweathermap_city").cloned())
                .unwrap_or_else(|| "Can Tho, VN".to_string());
            let coords = frontmatter.get("coordinates").cloned().unwrap_or_default();
            let mut weather_summary = String::new();
            let offline_mock_mode = env::var("ALIS_NEXUS_MOCK_API_DIR")
                .ok()
                .filter(|s| !s.trim().is_empty())
                .is_some();
            if let Some(mock_w) = read_mock_api_json("weather", "sync") {
                if let Some(ws) = mock_w["weather"].as_str().filter(|s| !s.is_empty()) {
                    weather_summary = ws.to_string();
                }
            }
            if weather_summary.is_empty() && !offline_mock_mode && !owm_key.is_empty() {
                let url = if let Some((la, lo)) = coords.split_once(',') {
                    format!(
                        "https://api.openweathermap.org/data/2.5/weather?lat={}&lon={}&units=metric&appid={}",
                        la.trim(),
                        lo.trim(),
                        owm_key.trim()
                    )
                } else {
                    format!(
                        "https://api.openweathermap.org/data/2.5/weather?q={}&units=metric&appid={}",
                        url_encode_simple(&city),
                        owm_key.trim()
                    )
                };
                if let Some(resp) = run_curl_json(&url) {
                    if let Some(temp) = resp["main"]["temp"].as_f64() {
                        let desc = resp["weather"]
                            .as_array()
                            .and_then(|a| a.first())
                            .and_then(|w| w["description"].as_str())
                            .unwrap_or("Clear");
                        let hum = resp["main"]["humidity"].as_i64().unwrap_or(0);
                        weather_summary = format!("{:.0}°C · {} ({}% RH)", temp, desc, hum);
                    }
                }
            }
            if weather_summary.is_empty() && !offline_mock_mode {
                let wttr_url = format!("https://wttr.in/{}?format=j1", url_encode_simple(&city));
                if let Some(resp) = run_curl_json(&wttr_url) {
                    if let Some(cur) = resp["current_condition"].as_array().and_then(|a| a.first()) {
                        let temp = cur["temp_C"].as_str().unwrap_or("28");
                        let desc = cur["weatherDesc"]
                            .as_array()
                            .and_then(|a| a.first())
                            .and_then(|w| w["value"].as_str())
                            .unwrap_or("Partly cloudy");
                        weather_summary = format!("{}°C · {}", temp, desc);
                    }
                }
            }
            if !weather_summary.is_empty() {
                updates.insert("weather".to_string(), Value::String(weather_summary));
            }
        }
        "tmdb" | "movie" | "tv" | "tvseries" | "media" => {
            let is_tv = kind_lower == "tv"
                || kind_lower == "tvseries"
                || rel_norm.to_ascii_lowercase().contains("tv_series")
                || frontmatter
                    .get("categories")
                    .map(|c| c.to_ascii_lowercase().contains("tv"))
                    .unwrap_or(false);
            let search_kind = if is_tv { "tv" } else { "movie" };
            if let Some(cand) = search_api_candidates_internal(search_kind, &title, 1, &settings_props, "sync").first() {
                merge_candidate_into_updates(cand, &mut updates);
            }
        }
        "book" | "books" => {
            if let Some(cand) = search_api_candidates_internal("book", &title, 1, &settings_props, "sync").first() {
                merge_candidate_into_updates(cand, &mut updates);
            }
        }
        "steam" | "game" | "games" => {
            let mut app_id = frontmatter
                .get("steamappid")
                .or_else(|| frontmatter.get("steam_id"))
                .cloned()
                .unwrap_or_default();
            if app_id.trim().is_empty() {
                if let Some(cand) = search_api_candidates_internal("game", &title, 1, &settings_props, "sync").first() {
                    merge_candidate_into_updates(cand, &mut updates);
                    if let Some(found_id) = cand["id"].as_str().filter(|s| !s.is_empty()) {
                        if cand["source"].as_str() == Some("Steam") {
                            app_id = found_id.to_string();
                        }
                    }
                }
            }
            if !app_id.trim().is_empty() {
                if let Some(data) = enrich_steam_appdetails(&app_id) {
                    let cover = format!(
                        "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/{}/library_600x900.jpg",
                        app_id.trim()
                    );
                    let backdrop = format!(
                        "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/{}/header.jpg",
                        app_id.trim()
                    );
                    if frontmatter.get("cover").map(|s| s.trim().is_empty()).unwrap_or(true) {
                        updates.insert("cover".to_string(), Value::String(cover));
                    }
                    if frontmatter.get("backdrop").map(|s| s.trim().is_empty()).unwrap_or(true) {
                        updates.insert("backdrop".to_string(), Value::String(backdrop));
                    }
                    if let Some(desc) = data["short_description"].as_str() {
                        let clean_desc = strip_html_to_plain_text(desc);
                        if !clean_desc.is_empty() {
                            updates.insert("description".to_string(), Value::String(clean_desc));
                        }
                    }
                    if let Some(devs) = data["developers"].as_array().and_then(|a| a.first()).and_then(|v| v.as_str()) {
                        updates.insert("developer".to_string(), Value::String(devs.to_string()));
                    }
                    if let Some(pubs) = data["publishers"].as_array().and_then(|a| a.first()).and_then(|v| v.as_str()) {
                        updates.insert("publisher".to_string(), Value::String(pubs.to_string()));
                    }
                    if let Some(mc) = data["metacritic"]["score"].as_i64() {
                        updates.insert("metacritic".to_string(), Value::Number(mc.into()));
                    }
                    if let Some(rd) = data["release_date"]["date"].as_str() {
                        if let Some(y4) = rd.split(|c: char| !c.is_ascii_digit()).find(|seg| seg.len() == 4) {
                            updates.insert("release_year".to_string(), Value::String(y4.to_string()));
                        }
                    }
                }
            }
        }
        "recipe" | "recipes" => {
            let meal_id = frontmatter.get("meal_id").cloned().unwrap_or_default();
            let offline_mock_mode = env::var("ALIS_NEXUS_MOCK_API_DIR")
                .ok()
                .filter(|s| !s.trim().is_empty())
                .is_some();
            let mut matched_cand: Option<Value> = None;
            if !meal_id.trim().is_empty() && !offline_mock_mode {
                let lookup_url = format!(
                    "https://www.themealdb.com/api/json/v1/1/lookup.php?i={}",
                    url_encode_simple(meal_id.trim())
                );
                if let Some(resp) = run_curl_json(&lookup_url) {
                    if let Some(meal) = resp["meals"].as_array().and_then(|a| a.first()) {
                        let (ings, ins) = extract_meal_ingredients_and_steps(meal);
                        let mut fm = serde_json::Map::new();
                        if let Some(c) = meal["strMealThumb"].as_str().filter(|s| !s.is_empty()) {
                            fm.insert("cover".into(), json!(c));
                        }
                        if let Some(cat) = meal["strCategory"].as_str().filter(|s| !s.is_empty()) {
                            fm.insert("recipe_category".into(), json!(cat));
                        }
                        if let Some(area) = meal["strArea"].as_str().filter(|s| !s.is_empty()) {
                            fm.insert("cuisine".into(), json!(area));
                        }
                        if let Some(src) = meal["strSource"].as_str().filter(|s| !s.is_empty()) {
                            fm.insert("source_url".into(), json!(src));
                        }
                        matched_cand = Some(json!({
                            "frontmatter": fm,
                            "body_sections": {
                                "ingredients": ings,
                                "instructions": ins
                            }
                        }));
                    }
                }
            }
            if matched_cand.is_none() {
                matched_cand = search_api_candidates_internal("recipe", &title, 1, &settings_props, "sync")
                    .into_iter()
                    .next();
            }
            if let Some(cand) = matched_cand {
                merge_candidate_into_updates(&cand, &mut updates);
                let ings: Vec<String> = cand["body_sections"]["ingredients"]
                    .as_array()
                    .map(|a| a.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect())
                    .unwrap_or_default();
                let ins: Vec<String> = cand["body_sections"]["instructions"]
                    .as_array()
                    .map(|a| a.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect())
                    .unwrap_or_default();
                if !ings.is_empty() && !note_has_user_recipe_section(&raw, "ingredients") && frontmatter.contains_key("ingredients") {
                    updates.insert("ingredients".to_string(), json!(ings));
                }
                if !ins.is_empty() && !note_has_user_recipe_section(&raw, "instructions") && frontmatter.contains_key("instructions") {
                    updates.insert("instructions".to_string(), json!(ins));
                }
                recipe_sections = Some((ings, ins));
            }
        }
        "place" | "places" => {
            if let Some(cand) = search_api_candidates_internal("place", &title, 1, &settings_props, "sync").first() {
                merge_candidate_into_updates(cand, &mut updates);
            }
        }
        _ => {}
    }

    let mut updated = if !updates.is_empty() {
        if kind_lower == "weather" {
            apply_check_in_updates(&raw, &updates)
        } else {
            apply_frontmatter_updates_to_content(&raw, &updates)
        }
    } else {
        raw.clone()
    };
    if let Some((ings, ins)) = recipe_sections {
        updated = inject_recipe_markdown_sections_if_missing(&updated, &ings, &ins);
    }
    if updated != raw {
        atomic_write_inside_vault(&vault_canon, &rel_norm, &updated)?;
    }
    cmd_read(vault_str, &rel_norm)
}

pub fn cmd_finance_add(
    vault_str: &str,
    record_type: &str,
    title: &str,
    amount: f64,
    tx_type: &str,
    category: &str,
    account: &str,
) -> Result<Value, String> {
    let vault_canon = resolve_vault_root(vault_str)?;
    let now_secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let (y, m, d) = civil_from_days((now_secs / 86400) as i64);
    let date_str = format!("{:04}-{:02}-{:02}", y, m, d);
    let clean_title: String = title
        .trim()
        .chars()
        .map(|c| if c == '/' || c == '\\' || c == ':' { '-' } else { c })
        .collect();
    let safe_title = if clean_title.is_empty() {
        "Record".to_string()
    } else {
        clean_title
    };

    let (rel_path, content) = match record_type.trim().to_ascii_lowercase().as_str() {
        "account" => (
            format!("20_Personal_Life/22_Finance/Records/Accounts/{}.md", safe_title),
            format!(
                "---\nRecordType: account\nFinanceSchema: 1\nFinanceBook: default\nAccountId: \"{}\"\nAccountType: checking\nInstitution: \"{}\"\nCurrency: VND\nOpeningBalance: {:.0}\nOpeningDate: {}\nStatus: active\ncreated: {}\ntags:\n  - finance/account\n---\n\n## Notes\n\n- \n",
                safe_title.to_ascii_lowercase().replace(' ', "-"),
                if category.is_empty() { "Bank" } else { category },
                amount,
                date_str,
                date_str
            ),
        ),
        "subscription" => (
            format!("20_Personal_Life/22_Finance/Records/Subscription/{}.md", safe_title),
            format!(
                "---\nRecordType: subscription\nFinanceSchema: 1\nFinanceBook: default\nAmount: {:.0}\nCurrency: VND\nBillingCycle: monthly\nNextBillingDate: {}\nAccount: \"[[{}]]\"\nCategory: \"{}\"\nStatus: active\ncreated: {}\ntags:\n  - finance/subscription\n---\n\n## Notes\n\n- \n",
                amount,
                date_str,
                if account.is_empty() { "Default" } else { account },
                if category.is_empty() { "Subscriptions" } else { category },
                date_str
            ),
        ),
        _ => (
            format!(
                "20_Personal_Life/22_Finance/Records/Transactions/{} - {}.md",
                date_str, safe_title
            ),
            format!(
                "---\nRecordType: transaction\nFinanceSchema: 1\nFinanceBook: default\nDate: {}\nTransactionType: {}\nAmount: {:.0}\nCurrency: VND\nAccount: \"[[{}]]\"\nCategory: \"{}\"\nMerchant: \"{}\"\nStatus: cleared\ncreated: {}\ntags:\n  - finance/transaction\n---\n\n## Notes\n\n- \n",
                date_str,
                if tx_type.is_empty() { "expense" } else { tx_type },
                amount,
                if account.is_empty() { "Cash" } else { account },
                if category.is_empty() { "General" } else { category },
                safe_title,
                date_str
            ),
        ),
    };

    let (_, saved_rel) = atomic_write_inside_vault(&vault_canon, &rel_path, &content)?;
    cmd_read(vault_str, &saved_rel)
}

fn parse_flag<'a>(args: &'a [String], flag: &str) -> Option<&'a str> {
    for i in 0..args.len() {
        if args[i] == flag && i + 1 < args.len() {
            return Some(args[i + 1].as_str());
        }
    }
    None
}

fn run_cli() -> Result<Value, String> {
    let args: Vec<String> = env::args().skip(1).collect();
    let Some(cmd) = args.first().map(|s| s.as_str()) else {
        return Err("Usage: alis-nexus <scan|read|write|create|daily|calendar|toggle-todo|update-block|link-mention|search|delete|trash|rename|hotkeys|set-frontmatter|journal-weather|search-api|sync-api|finance-add> [--vault <path>] ...".to_string());
    };
    if cmd == "search-api" {
        let vault_opt = parse_flag(&args, "--vault").unwrap_or("");
        let kind = parse_flag(&args, "--kind")
            .or_else(|| parse_flag(&args, "--type"))
            .unwrap_or("movie");
        let query = parse_flag(&args, "--query")
            .or_else(|| parse_flag(&args, "--q"))
            .unwrap_or("");
        let limit = parse_flag(&args, "--limit")
            .and_then(|s| s.parse::<usize>().ok())
            .unwrap_or(8);
        return cmd_search_api(vault_opt, kind, query, limit);
    }
    let vault = parse_flag(&args, "--vault").ok_or_else(|| "Missing --vault <path>".to_string())?;

    match cmd {
        "scan" => cmd_scan_for_date_with_cache_opts(
            vault,
            parse_flag(&args, "--date"),
            parse_flag(&args, "--cache-file"),
            args.iter().any(|arg| arg == "--skip-if-unchanged"),
        ),
        "journal-weather" => {
            let path = parse_flag(&args, "--path").ok_or_else(|| "Missing --path <rel_path>".to_string())?;
            let summary = parse_flag(&args, "--summary").ok_or_else(|| "Missing --summary <weather>".to_string())?;
            cmd_journal_weather(vault, path, summary, args.iter().any(|arg| arg == "--replace"))
        }
        "read" => {
            let path = parse_flag(&args, "--path").ok_or_else(|| "Missing --path <rel_path>".to_string())?;
            cmd_read(vault, path)
        }
        "write" => {
            let path = parse_flag(&args, "--path").ok_or_else(|| "Missing --path <rel_path>".to_string())?;
            let content = if let Some(c) = parse_flag(&args, "--content") {
                c.to_string()
            } else {
                let mut buf = String::new();
                std::io::stdin()
                    .read_to_string(&mut buf)
                    .map_err(|e| format!("Failed to read stdin: {}", e))?;
                buf
            };
            cmd_write(vault, path, &content)
        }
        "create" => {
            let path = parse_flag(&args, "--path").ok_or_else(|| "Missing --path <rel_path>".to_string())?;
            let title = parse_flag(&args, "--title");
            let template = parse_flag(&args, "--template")
                .or_else(|| parse_flag(&args, "--kind"))
                .unwrap_or("standard");
            let candidate_json = parse_flag(&args, "--candidate-json");
            cmd_create_with_candidate(vault, path, title, template, candidate_json)
        }
        "create-folder" => {
            let path = parse_flag(&args, "--path").ok_or_else(|| "Missing --path <rel_path>".to_string())?;
            cmd_create_folder(vault, path)
        }
        "daily" => {
            let date = parse_flag(&args, "--date");
            let folder = parse_flag(&args, "--folder");
            let format = parse_flag(&args, "--format");
            let mood = parse_flag(&args, "--mood");
            let energy = parse_flag(&args, "--energy");
            let weight = parse_flag(&args, "--weight");
            cmd_daily_with_check_in(vault, date, folder, format, mood, energy, weight)
        }
        "calendar" => {
            let now_secs = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0);
            let (cur_y, cur_m, _) = civil_from_days((now_secs / 86400) as i64);
            let year = parse_flag(&args, "--year")
                .and_then(|s| s.parse::<i32>().ok())
                .unwrap_or(cur_y);
            let month = parse_flag(&args, "--month")
                .and_then(|s| s.parse::<u32>().ok())
                .unwrap_or(cur_m);
            let today_opt = parse_flag(&args, "--today").or_else(|| parse_flag(&args, "--date"));
            cmd_calendar_with_today(vault, year, month, today_opt)
        }
        "toggle-todo" => {
            let path = parse_flag(&args, "--path").ok_or_else(|| "Missing --path <rel_path>".to_string())?;
            let line = parse_flag(&args, "--line")
                .and_then(|s| s.parse::<usize>().ok())
                .ok_or_else(|| "Missing or invalid --line <1-indexed>".to_string())?;
            cmd_toggle_todo(vault, path, line)
        }
        "update-block" => {
            let path = parse_flag(&args, "--path").ok_or_else(|| "Missing --path <rel_path>".to_string())?;
            let start = parse_flag(&args, "--start")
                .and_then(|s| s.parse::<usize>().ok())
                .ok_or_else(|| "Missing or invalid --start <1-indexed>".to_string())?;
            let end = parse_flag(&args, "--end")
                .and_then(|s| s.parse::<usize>().ok())
                .unwrap_or(start);
            let content = parse_flag(&args, "--content").unwrap_or("");
            cmd_update_block(vault, path, start, end, content)
        }
        "journal-save-log" => {
            let path = parse_flag(&args, "--path").ok_or_else(|| "Missing --path <rel_path>".to_string())?;
            let content = parse_flag(&args, "--content").unwrap_or("");
            let doc = cmd_read(vault, path)?;
            let start = doc["journalView"]["dailyLogLineStart"]
                .as_u64()
                .unwrap_or(1) as usize;
            let end = doc["journalView"]["dailyLogLineEnd"]
                .as_u64()
                .unwrap_or(start as u64) as usize;
            cmd_update_block(vault, path, start, end.max(start), content)
        }
        "link-mention" => {
            let source = parse_flag(&args, "--source").ok_or_else(|| "Missing --source <rel_path>".to_string())?;
            let line = parse_flag(&args, "--line")
                .and_then(|s| s.parse::<usize>().ok())
                .ok_or_else(|| "Missing or invalid --line <1-indexed>".to_string())?;
            let target = parse_flag(&args, "--target").ok_or_else(|| "Missing --target <title>".to_string())?;
            cmd_link_mention(vault, source, line, target)
        }
        "search" => {
            let query = parse_flag(&args, "--query").unwrap_or("");
            cmd_search(vault, query)
        }
        "delete" | "trash" => {
            let path = parse_flag(&args, "--path").ok_or_else(|| "Missing --path <rel_path>".to_string())?;
            cmd_delete_with_cache(vault, path, parse_flag(&args, "--cache-file"))
        }
        "rename" => {
            let old_path = parse_flag(&args, "--from")
                .or_else(|| parse_flag(&args, "--old"))
                .or_else(|| parse_flag(&args, "--path"))
                .ok_or_else(|| "Missing --from <old_path>".to_string())?;
            let new_path = parse_flag(&args, "--to")
                .or_else(|| parse_flag(&args, "--new"))
                .ok_or_else(|| "Missing --to <new_path>".to_string())?;
            cmd_rename(vault, old_path, new_path)
        }
        "duplicate" => {
            let path = parse_flag(&args, "--path").ok_or_else(|| "Missing --path <rel_path>".to_string())?;
            cmd_duplicate(vault, path)
        }
        "hotkeys" => cmd_hotkeys(vault),
        "set-frontmatter" => {
            let path = parse_flag(&args, "--path").ok_or_else(|| "Missing --path <rel_path>".to_string())?;
            if let Some(updates) = parse_flag(&args, "--updates").or_else(|| parse_flag(&args, "--json")) {
                cmd_set_frontmatter(vault, path, updates)
            } else {
                let mut map = serde_json::Map::new();
                for i in 0..args.len() {
                    if args[i] == "--set" && i + 1 < args.len() {
                        if let Some((k, v)) = args[i + 1].split_once('=') {
                            map.insert(k.trim().to_string(), Value::String(v.to_string()));
                        }
                    }
                }
                if map.is_empty() {
                    return Err("Missing --updates <json> or --set <k=v>".to_string());
                }
                let json_str = Value::Object(map).to_string();
                cmd_set_frontmatter(vault, path, &json_str)
            }
        }
        "search-api" => {
            let kind = parse_flag(&args, "--kind")
                .or_else(|| parse_flag(&args, "--type"))
                .unwrap_or("movie");
            let query = parse_flag(&args, "--query")
                .or_else(|| parse_flag(&args, "--q"))
                .unwrap_or("");
            let limit = parse_flag(&args, "--limit")
                .and_then(|s| s.parse::<usize>().ok())
                .unwrap_or(8);
            cmd_search_api(vault, kind, query, limit)
        }
        "sync-api" => {
            let path = parse_flag(&args, "--path").ok_or_else(|| "Missing --path <rel_path>".to_string())?;
            let kind = parse_flag(&args, "--kind")
                .or_else(|| parse_flag(&args, "--api"))
                .or_else(|| parse_flag(&args, "--source"))
                .unwrap_or("quote");
            cmd_sync_api(vault, path, kind)
        }
        "finance-add" => {
            let record_type = parse_flag(&args, "--record-type").unwrap_or("transaction");
            let title = parse_flag(&args, "--title")
                .or_else(|| parse_flag(&args, "--description"))
                .unwrap_or("Expense");
            let amount = parse_flag(&args, "--amount")
                .and_then(|s| s.parse::<f64>().ok())
                .unwrap_or(0.0);
            let tx_type = parse_flag(&args, "--tx-type")
                .or_else(|| parse_flag(&args, "--kind"))
                .unwrap_or("expense");
            let category = parse_flag(&args, "--category").unwrap_or("General");
            let account = parse_flag(&args, "--account").unwrap_or("Cash");
            cmd_finance_add(vault, record_type, title, amount, tx_type, category, account)
        }
        "tag-rename" | "tag-merge" => {
            let from_tag = parse_flag(&args, "--from")
                .or_else(|| parse_flag(&args, "--old"))
                .ok_or_else(|| "Missing --from <tag>".to_string())?;
            let to_tag = parse_flag(&args, "--to")
                .or_else(|| parse_flag(&args, "--new"))
                .ok_or_else(|| "Missing --to <tag>".to_string())?;
            let include_subtags = parse_flag(&args, "--include-subtags")
                .map(|s| !s.eq_ignore_ascii_case("false") && s != "0")
                .unwrap_or(true);
            cmd_tag_rename(vault, from_tag, to_tag, include_subtags)
        }
        "tag-remove" => {
            let tag = parse_flag(&args, "--tag")
                .ok_or_else(|| "Missing --tag <tag>".to_string())?;
            let path_opt = parse_flag(&args, "--path");
            let include_subtags = parse_flag(&args, "--include-subtags")
                .map(|s| !s.eq_ignore_ascii_case("false") && s != "0")
                .unwrap_or(false);
            cmd_tag_remove(vault, tag, path_opt, include_subtags)
        }
        "tag-page" => {
            let tag = parse_flag(&args, "--tag")
                .ok_or_else(|| "Missing --tag <tag>".to_string())?;
            let folder_opt = parse_flag(&args, "--folder");
            cmd_tag_page(vault, tag, folder_opt)
        }
        other => Err(format!("Unknown command '{}'", other)),
    }
}

fn normalize_tag_arg(raw: &str) -> Result<String, String> {
    let cleaned = raw.trim().trim_start_matches('#').trim_matches('/').trim();
    if cleaned.is_empty() {
        return Err("Tag name cannot be empty".to_string());
    }
    if cleaned.chars().any(|c| c.is_whitespace() || matches!(c, '#' | '[' | ']' | '{' | '}' | '"' | '\'' | '\\')) {
        return Err(format!("Invalid tag name '{}'", raw));
    }
    Ok(cleaned.to_string())
}

fn is_tag_body_char(c: char) -> bool {
    c.is_alphanumeric() || matches!(c, '_' | '-' | '/')
}

fn rewrite_tag_token(token: &str, from_lower: &str, to_clean: Option<&str>, include_subtags: bool) -> (Option<String>, bool) {
    let stripped = token.trim().trim_start_matches('#');
    let lower = stripped.to_lowercase();
    if lower == from_lower {
        return (to_clean.map(|t| t.to_string()), true);
    }
    if include_subtags {
        let from_segs: Vec<&str> = from_lower.split('/').collect();
        let orig_segs: Vec<&str> = stripped.split('/').collect();
        if orig_segs.len() > from_segs.len()
            && orig_segs
                .iter()
                .zip(from_segs.iter())
                .all(|(o, f)| o.to_lowercase() == *f)
        {
            let suffix = orig_segs[from_segs.len()..].join("/");
            let mapped = to_clean.map(|t| format!("{}/{}", t, suffix));
            return (mapped, true);
        }
    }
    (Some(stripped.to_string()), false)
}

fn rewrite_markdown_tags(
    raw: &str,
    from_clean: &str,
    to_clean: Option<&str>,
    include_subtags: bool,
) -> (String, usize) {
    let eol = if raw.contains("\r\n") { "\r\n" } else { "\n" };
    let trailing_eol = raw.ends_with('\n');
    let from_lower = from_clean.to_lowercase();
    let src_lines: Vec<&str> = raw.split('\n').map(|l| l.strip_suffix('\r').unwrap_or(l)).collect();
    let total = src_lines.len();
    let mut out_lines: Vec<String> = Vec::with_capacity(total);
    let mut replacements = 0usize;

    let mut idx = 0usize;
    // 1. Optional YAML frontmatter block
    if total >= 2 && src_lines[0].trim() == "---" {
        let mut fm_end: Option<usize> = None;
        for (i, line) in src_lines.iter().enumerate().skip(1) {
            let tr = line.trim();
            if tr == "---" || tr == "..." {
                fm_end = Some(i);
                break;
            }
        }
        if let Some(end_i) = fm_end {
            out_lines.push(src_lines[0].to_string());
            let mut in_tags_list = false;
            let mut seen_fm_tags: HashSet<String> = HashSet::new();
            for line in src_lines.iter().take(end_i).skip(1) {
                let trimmed = line.trim();
                let is_indented = line.starts_with(' ') || line.starts_with('\t');
                let is_list_item = trimmed.starts_with("- ") || trimmed == "-";
                if !is_indented && !(in_tags_list && (is_list_item || trimmed.is_empty() || trimmed.starts_with('#'))) {
                    in_tags_list = false;
                    if let Some((k, rest)) = line.split_once(':') {
                        let key_lower = k.trim().to_ascii_lowercase();
                        if key_lower == "tags" || key_lower == "tag" {
                            let val_trim = rest.trim();
                            if val_trim.is_empty() {
                                in_tags_list = true;
                                out_lines.push((*line).to_string());
                                continue;
                            }
                            if val_trim.starts_with('[') && val_trim.ends_with(']') {
                                let inner = &val_trim[1..val_trim.len() - 1];
                                let mut new_items: Vec<String> = Vec::new();
                                let mut line_changed = false;
                                for part in inner.split(',') {
                                    let p_trim = part.trim();
                                    if p_trim.is_empty() {
                                        continue;
                                    }
                                    let quote = if (p_trim.starts_with('"') && p_trim.ends_with('"') && p_trim.len() >= 2)
                                        || (p_trim.starts_with('\'') && p_trim.ends_with('\'') && p_trim.len() >= 2)
                                    {
                                        Some(&p_trim[..1])
                                    } else {
                                        None
                                    };
                                    let unq = if quote.is_some() { &p_trim[1..p_trim.len() - 1] } else { p_trim };
                                    let had_hash = unq.trim_start().starts_with('#');
                                    let (mapped_opt, changed) = rewrite_tag_token(unq, &from_lower, to_clean, include_subtags);
                                    if changed {
                                        line_changed = true;
                                        replacements += 1;
                                    }
                                    if let Some(mapped) = mapped_opt {
                                        let dedup_key = mapped.to_lowercase();
                                        if seen_fm_tags.insert(dedup_key) {
                                            let formatted = if had_hash { format!("#{}", mapped) } else { mapped };
                                            if let Some(q) = quote {
                                                new_items.push(format!("{}{}{}", q, formatted, q));
                                            } else {
                                                new_items.push(formatted);
                                            }
                                        }
                                    }
                                }
                                if line_changed {
                                    out_lines.push(format!("{}: [{}]", k, new_items.join(", ")));
                                } else {
                                    out_lines.push((*line).to_string());
                                }
                                continue;
                            }
                            // Single inline scalar `tags: Books` or comma-separated `tags: Books, Fiction`
                            let mut new_items: Vec<String> = Vec::new();
                            let mut line_changed = false;
                            for part in val_trim.split(',') {
                                let p_trim = part.trim();
                                if p_trim.is_empty() {
                                    continue;
                                }
                                let unq = p_trim.trim_matches('"').trim_matches('\'');
                                let (mapped_opt, changed) = rewrite_tag_token(unq, &from_lower, to_clean, include_subtags);
                                if changed {
                                    line_changed = true;
                                    replacements += 1;
                                }
                                if let Some(mapped) = mapped_opt {
                                    if seen_fm_tags.insert(mapped.to_lowercase()) {
                                        new_items.push(mapped);
                                    }
                                }
                            }
                            if line_changed {
                                out_lines.push(format!("{}: {}", k, new_items.join(", ")));
                            } else {
                                out_lines.push((*line).to_string());
                            }
                            continue;
                        }
                    }
                    out_lines.push((*line).to_string());
                    continue;
                }
                if in_tags_list && is_list_item {
                    let prefix_len = line.find('-').unwrap_or(0) + 1;
                    let after_dash = &line[prefix_len..];
                    let leading_ws: String = after_dash.chars().take_while(|c| c.is_whitespace()).collect();
                    let val_trim = after_dash.trim();
                    let quote = if (val_trim.starts_with('"') && val_trim.ends_with('"') && val_trim.len() >= 2)
                        || (val_trim.starts_with('\'') && val_trim.ends_with('\'') && val_trim.len() >= 2)
                    {
                        Some(&val_trim[..1])
                    } else {
                        None
                    };
                    let unq = if quote.is_some() { &val_trim[1..val_trim.len() - 1] } else { val_trim };
                    let had_hash = unq.trim_start().starts_with('#');
                    let (mapped_opt, changed) = rewrite_tag_token(unq, &from_lower, to_clean, include_subtags);
                    if changed {
                        replacements += 1;
                        if let Some(mapped) = mapped_opt {
                            if seen_fm_tags.insert(mapped.to_lowercase()) {
                                let formatted = if had_hash { format!("#{}", mapped) } else { mapped };
                                let rendered = if let Some(q) = quote {
                                    format!("{}{}{}", q, formatted, q)
                                } else {
                                    formatted
                                };
                                out_lines.push(format!("{}{}{}", &line[..prefix_len], leading_ws, rendered));
                            }
                        }
                        // else: deleted (removed or deduplicated)
                    } else {
                        let keep_key = unq.trim_start_matches('#').to_lowercase();
                        // Deduplicate when an earlier tag in this list was merged into this tag.
                        if seen_fm_tags.insert(keep_key) || replacements == 0 {
                            out_lines.push((*line).to_string());
                        }
                    }
                } else {
                    out_lines.push((*line).to_string());
                }
            }
            out_lines.push(src_lines[end_i].to_string());
            idx = end_i + 1;
        }
    }

    // 2. Markdown body inline `#tag` tokens (skipping fenced code blocks and inline code spans)
    let mut in_fence = false;
    while idx < total {
        let line = src_lines[idx];
        idx += 1;
        let trimmed = line.trim();
        if trimmed.starts_with("```") || trimmed.starts_with("~~~") {
            in_fence = !in_fence;
            out_lines.push(line.to_string());
            continue;
        }
        if in_fence || !line.contains('#') {
            out_lines.push(line.to_string());
            continue;
        }
        let chars: Vec<char> = line.chars().collect();
        let mut rebuilt = String::with_capacity(line.len());
        let mut i = 0usize;
        let mut in_inline_code = false;
        while i < chars.len() {
            let ch = chars[i];
            if ch == '`' {
                in_inline_code = !in_inline_code;
                rebuilt.push(ch);
                i += 1;
                continue;
            }
            if !in_inline_code && ch == '#' {
                let prev_ok = i == 0 || (!chars[i - 1].is_alphanumeric() && chars[i - 1] != '&' && chars[i - 1] != '/' && chars[i - 1] != '#');
                if prev_ok && i + 1 < chars.len() && is_tag_body_char(chars[i + 1]) {
                    let mut j = i + 1;
                    while j < chars.len() && is_tag_body_char(chars[j]) {
                        j += 1;
                    }
                    let token: String = chars[i + 1..j].iter().collect();
                    // Obsidian allows numeric-prefix tags like #2026/goals or #100days,
                    // while rejecting pure numbers like #123.
                    let valid_tag = !token.is_empty()
                        && !token.starts_with('/')
                        && !token.ends_with('/')
                        && !token.contains("//")
                        && !token.chars().all(|c| c.is_ascii_digit());
                    if valid_tag {
                        let (mapped_opt, changed) = rewrite_tag_token(&token, &from_lower, to_clean, include_subtags);
                        if changed {
                            replacements += 1;
                            if let Some(mapped) = mapped_opt {
                                rebuilt.push('#');
                                rebuilt.push_str(&mapped);
                            } else if rebuilt.ends_with(' ') && j < chars.len() && chars[j] == ' ' {
                                // avoid leaving double spaces on tag removal
                                rebuilt.pop();
                            }
                            i = j;
                            continue;
                        }
                    }
                }
            }
            rebuilt.push(ch);
            i += 1;
        }
        out_lines.push(rebuilt);
    }

    let mut joined = out_lines.join(eol);
    if trailing_eol && !joined.ends_with('\n') {
        joined.push_str(eol);
    }
    (joined, replacements)
}

fn collect_vault_markdown_files_for_tags(vault_canon: &Path, dir: &Path, out: &mut Vec<(PathBuf, String)>) {
    let Ok(entries) = fs::read_dir(dir) else { return };
    let mut collected: Vec<_> = entries.flatten().collect();
    collected.sort_by_key(|e| e.file_name());
    for entry in collected {
        let fname = entry.file_name().to_string_lossy().to_string();
        if should_skip_entry(&fname) {
            continue;
        }
        let Ok(ft) = entry.file_type() else { continue };
        if ft.is_symlink() {
            continue;
        }
        let full = entry.path();
        if ft.is_dir() {
            if full != vault_canon && full.join(".git").exists() {
                continue;
            }
            collect_vault_markdown_files_for_tags(vault_canon, &full, out);
        } else if ft.is_file() {
            let ext = full.extension().map(|s| s.to_string_lossy().to_string()).unwrap_or_default();
            if classify_extension(&ext).0 == FileCategory::Markdown {
                let rel = full
                    .strip_prefix(vault_canon)
                    .map(|p| p.to_string_lossy().replace('\\', "/"))
                    .unwrap_or_default();
                out.push((full, rel));
            }
        }
    }
}

fn atomic_write_text(path: &Path, content: &str) -> Result<(), String> {
    let parent = path.parent().ok_or_else(|| "Invalid target parent".to_string())?;
    let fname = path.file_name().map(|s| s.to_string_lossy().to_string()).unwrap_or_else(|| "note.md".to_string());
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let tmp = parent.join(format!(".{}.tmp.{}.{}", fname, std::process::id(), nanos));
    fs::write(&tmp, content.as_bytes()).map_err(|e| format!("Failed writing temp file: {}", e))?;
    if let Err(e) = fs::rename(&tmp, path) {
        let _ = fs::remove_file(&tmp);
        return Err(format!("Failed committing atomic rename: {}", e));
    }
    Ok(())
}

pub fn cmd_tag_rename(
    vault_str: &str,
    from_raw: &str,
    to_raw: &str,
    include_subtags: bool,
) -> Result<Value, String> {
    let from_clean = normalize_tag_arg(from_raw)?;
    let to_clean = normalize_tag_arg(to_raw)?;
    if from_clean.eq_ignore_ascii_case(&to_clean) && from_clean == to_clean {
        return Ok(json!({
            "ok": true,
            "action": "tag-rename",
            "from": from_clean,
            "to": to_clean,
            "filesScanned": 0,
            "filesUpdated": 0,
            "occurrencesReplaced": 0,
            "updatedPaths": [],
        }));
    }
    let vault_canon = resolve_vault_root(vault_str)?;
    let mut files: Vec<(PathBuf, String)> = Vec::new();
    collect_vault_markdown_files_for_tags(&vault_canon, &vault_canon, &mut files);
    let files_scanned = files.len();
    let mut updated_paths: Vec<String> = Vec::new();
    let mut total_replaced = 0usize;

    for (full, rel) in files {
        let Ok(meta) = fs::metadata(&full) else { continue };
        if meta.len() > 4 * 1024 * 1024 {
            continue;
        }
        let Ok(raw) = fs::read_to_string(&full) else { continue };
        let (rewritten, count) = rewrite_markdown_tags(&raw, &from_clean, Some(&to_clean), include_subtags);
        if count > 0 && rewritten != raw {
            atomic_write_text(&full, &rewritten)?;
            total_replaced += count;
            updated_paths.push(rel);
        }
    }

    Ok(json!({
        "ok": true,
        "action": "tag-rename",
        "from": from_clean,
        "to": to_clean,
        "includeSubtags": include_subtags,
        "filesScanned": files_scanned,
        "filesUpdated": updated_paths.len(),
        "occurrencesReplaced": total_replaced,
        "updatedPaths": updated_paths,
    }))
}

pub fn cmd_tag_remove(
    vault_str: &str,
    tag_raw: &str,
    path_opt: Option<&str>,
    include_subtags: bool,
) -> Result<Value, String> {
    let tag_clean = normalize_tag_arg(tag_raw)?;
    let vault_canon = resolve_vault_root(vault_str)?;
    let mut targets: Vec<(PathBuf, String)> = Vec::new();
    if let Some(rel_req) = path_opt.filter(|s| !s.trim().is_empty()) {
        let (full, rel_norm) = resolve_inside_vault(&vault_canon, rel_req, true)?;
        targets.push((full, rel_norm));
    } else {
        collect_vault_markdown_files_for_tags(&vault_canon, &vault_canon, &mut targets);
    }
    let files_scanned = targets.len();
    let mut updated_paths: Vec<String> = Vec::new();
    let mut total_removed = 0usize;
    for (full, rel) in targets {
        let Ok(raw) = fs::read_to_string(&full) else { continue };
        let (rewritten, count) = rewrite_markdown_tags(&raw, &tag_clean, None, include_subtags);
        if count > 0 && rewritten != raw {
            atomic_write_text(&full, &rewritten)?;
            total_removed += count;
            updated_paths.push(rel);
        }
    }
    Ok(json!({
        "ok": true,
        "action": "tag-remove",
        "tag": tag_clean,
        "filesScanned": files_scanned,
        "filesUpdated": updated_paths.len(),
        "occurrencesRemoved": total_removed,
        "updatedPaths": updated_paths,
    }))
}

pub fn cmd_tag_page(
    vault_str: &str,
    tag_raw: &str,
    folder_opt: Option<&str>,
) -> Result<Value, String> {
    let tag_clean = normalize_tag_arg(tag_raw)?;
    let vault_canon = resolve_vault_root(vault_str)?;
    let safe_stem = tag_clean.replace('/', " - ");
    let base_folder = folder_opt
        .map(|s| s.trim().trim_matches('/'))
        .filter(|s| !s.is_empty())
        .unwrap_or("Tags");
    let candidate_rel = format!("{}/{}.md", base_folder, safe_stem);
    let (target_path, rel_norm) = resolve_inside_vault(&vault_canon, &candidate_rel, false)?;
    let created = if !target_path.exists() {
        if let Some(parent) = target_path.parent() {
            fs::create_dir_all(parent).map_err(|e| format!("Cannot create folder: {}", e))?;
        }
        let body = format!(
            "---\ntitle: \"#{}\"\ntags:\n  - {}\naliases:\n  - \"{}\"\n---\n\n# #{}\n\n> Tag page managed by Nexus Tag Wrangler.\n\n## Notes\n",
            tag_clean, tag_clean, tag_clean, tag_clean
        );
        atomic_write_text(&target_path, &body)?;
        true
    } else {
        false
    };
    Ok(json!({
        "ok": true,
        "action": "tag-page",
        "tag": tag_clean,
        "relPath": rel_norm,
        "created": created,
    }))
}

fn main() {
    match run_cli() {
        Ok(payload) => {
            println!("{}", payload);
        }
        Err(err) => {
            let out = json!({
                "ok": false,
                "error": err,
            });
            println!("{}", out);
            std::process::exit(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_temp_vault(prefix: &str) -> PathBuf {
        let dir = env::temp_dir().join(format!(
            "alis-nexus-test-{}-{}-{}",
            prefix,
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_nanos())
                .unwrap_or(0)
        ));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn test_delete_preserves_collisions_and_restorable_file_bytes() {
        let vault = make_temp_vault("trash-file-collisions");
        let trash = vault.join(".trash");
        fs::create_dir(&trash).unwrap();
        fs::write(trash.join("Repeated.md"), b"previous file\0\xff").unwrap();
        fs::create_dir(trash.join("1-Repeated.md")).unwrap();
        fs::write(trash.join("1-Repeated.md/keep.bin"), b"previous directory").unwrap();
        fs::write(trash.join("2-Repeated.md"), b"previous suffix").unwrap();
        let mut destinations = HashSet::new();
        let mut deleted = Vec::new();
        for index in 0..4_u8 {
            let bytes = vec![0, index, 255, 13, 10];
            fs::write(vault.join("Repeated.md"), &bytes).unwrap();
            let receipt = cmd_delete(vault.to_str().unwrap(), "Repeated.md").unwrap();
            let destination = receipt["trashPath"].as_str().unwrap();
            assert!(destinations.insert(destination.to_string()));
            let trashed = vault.join(destination);
            assert_eq!(fs::read(&trashed).unwrap(), bytes);
            deleted.push((trashed, bytes));
        }
        for (index, (trashed, bytes)) in deleted.into_iter().enumerate() {
            let restored = vault.join(format!("Restored-{}.md", index));
            fs::rename(&trashed, &restored).unwrap();
            assert_eq!(fs::read(restored).unwrap(), bytes);
        }
        assert_eq!(fs::read(trash.join("Repeated.md")).unwrap(), b"previous file\0\xff");
        assert_eq!(fs::read(trash.join("1-Repeated.md/keep.bin")).unwrap(), b"previous directory");
        assert_eq!(fs::read(trash.join("2-Repeated.md")).unwrap(), b"previous suffix");
        fs::remove_dir_all(vault).unwrap();
    }

    #[test]
    fn test_delete_preserves_collisions_and_restorable_folder_bytes() {
        let vault = make_temp_vault("trash-folder-collisions");
        let trash = vault.join(".trash");
        fs::create_dir(&trash).unwrap();
        fs::write(trash.join("Collection"), b"previous file").unwrap();
        fs::create_dir(trash.join("1-Collection")).unwrap();
        fs::create_dir(trash.join("2-Collection")).unwrap();
        fs::write(trash.join("2-Collection/keep.md"), b"previous folder").unwrap();
        let mut deleted = Vec::new();
        for index in 0..3_u8 {
            let source = vault.join("Collection");
            fs::create_dir_all(source.join("Nested")).unwrap();
            let bytes = vec![index, 0, 255];
            fs::write(source.join("Nested/note.md"), &bytes).unwrap();
            let receipt = cmd_delete(vault.to_str().unwrap(), "Collection").unwrap();
            let trashed = vault.join(receipt["trashPath"].as_str().unwrap());
            deleted.push((trashed, bytes));
        }
        for (index, (trashed, bytes)) in deleted.into_iter().enumerate() {
            let restored = vault.join(format!("Restored-{}", index));
            fs::rename(trashed, &restored).unwrap();
            assert_eq!(fs::read(restored.join("Nested/note.md")).unwrap(), bytes);
        }
        assert_eq!(fs::read(trash.join("Collection")).unwrap(), b"previous file");
        assert!(trash.join("1-Collection").is_dir());
        assert_eq!(fs::read(trash.join("2-Collection/keep.md")).unwrap(), b"previous folder");
        fs::remove_dir_all(vault).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn test_delete_preserves_dangling_trash_symlink_and_vault_boundaries() {
        use std::os::unix::fs::symlink;
        let vault = make_temp_vault("trash-symlink");
        let outside = make_temp_vault("trash-outside");
        fs::create_dir(vault.join(".trash")).unwrap();
        symlink("missing-target", vault.join(".trash/Repeated.md")).unwrap();
        fs::write(vault.join("Repeated.md"), b"original bytes").unwrap();
        let receipt = cmd_delete(vault.to_str().unwrap(), "Repeated.md").unwrap();
        assert_eq!(fs::read(vault.join(receipt["trashPath"].as_str().unwrap())).unwrap(), b"original bytes");
        assert_eq!(fs::read_link(vault.join(".trash/Repeated.md")).unwrap(), PathBuf::from("missing-target"));
        fs::write(outside.join("Outside.md"), b"outside bytes").unwrap();
        symlink(&outside, vault.join("Escape")).unwrap();
        assert!(cmd_delete(vault.to_str().unwrap(), "Escape/Outside.md").is_err());
        fs::remove_dir_all(vault.join(".trash")).unwrap();
        symlink(&outside, vault.join(".trash")).unwrap();
        fs::write(vault.join("Keep.md"), b"keep bytes").unwrap();
        assert!(cmd_delete(vault.to_str().unwrap(), "Keep.md").is_err());
        assert_eq!(fs::read(vault.join("Keep.md")).unwrap(), b"keep bytes");
        assert_eq!(fs::read(outside.join("Outside.md")).unwrap(), b"outside bytes");
        assert!(!outside.join("Keep.md").exists());
        fs::remove_dir_all(vault).unwrap();
        fs::remove_dir_all(outside).unwrap();
    }

    #[test]
    fn test_delete_concurrent_same_name_files_and_folders_never_overwrite() {
        let vault = make_temp_vault("trash-concurrent");
        fs::create_dir(vault.join(".trash")).unwrap();
        fs::write(vault.join(".trash/Entry"), b"previous trash entry").unwrap();
        let mut jobs = Vec::new();
        for index in 0..16_u8 {
            let rel = format!("Source-{}/Entry", index);
            let source = vault.join(&rel);
            let bytes = vec![index, 255, 0];
            let is_folder = index % 2 == 0;
            if is_folder {
                fs::create_dir_all(&source).unwrap();
                fs::write(source.join("note.bin"), &bytes).unwrap();
            } else {
                fs::create_dir_all(source.parent().unwrap()).unwrap();
                fs::write(&source, &bytes).unwrap();
            }
            let vault_name = vault.to_str().unwrap().to_string();
            jobs.push(std::thread::spawn(move || {
                let receipt = cmd_delete(&vault_name, &rel).unwrap();
                (receipt["trashPath"].as_str().unwrap().to_string(), bytes, is_folder)
            }));
        }
        let mut destinations = HashSet::new();
        for job in jobs {
            let (destination, bytes, is_folder) = job.join().unwrap();
            assert!(destinations.insert(destination.clone()));
            let path = vault.join(destination);
            assert_eq!(fs::read(if is_folder { path.join("note.bin") } else { path }).unwrap(), bytes);
        }
        assert_eq!(destinations.len(), 16);
        assert_eq!(fs::read(vault.join(".trash/Entry")).unwrap(), b"previous trash entry");
        fs::remove_dir_all(vault).unwrap();
    }

    #[test]
    fn test_check_in_clear_preserves_legacy_journal_bytes_and_omitted_fields() {
        let vault = make_temp_vault("checkin-legacy");
        let rel = "Journal/10-11-2026-Tuesday.md";
        fs::create_dir(vault.join("Journal")).unwrap();
        let raw = "---\r\njournal: Daily Notes\r\nMood: great\r\n  # Keep this comment\r\nenergy: high\r\ncreated: 2020-01-02T03:04:05\r\ncustom:\r\n  - keep me\r\n...\r\n\r\n## Daily Log\r\nPrivate fixture thoughts.\r\n```dataviewjs\r\nconst x = 'unchanged';\r\n```";
        fs::write(vault.join(rel), raw).unwrap();
        let v = vault.to_str().unwrap();
        let unchanged = cmd_daily_with_check_in(v, Some("2026-11-10"), None, None, None, None, None).unwrap();
        assert_eq!(unchanged["relPath"], rel);
        assert_eq!(fs::read_to_string(vault.join(rel)).unwrap(), raw);
        let cleared = cmd_daily_with_check_in(v, Some("2026-11-10"), None, None, Some(""), None, None).unwrap();
        assert_eq!(cleared["journalView"]["mood"], "");
        assert_eq!(cleared["journalView"]["energy"], "high");
        let one_cleared = raw.replace("Mood: great", "Mood: \"\"");
        assert_eq!(fs::read_to_string(vault.join(rel)).unwrap(), one_cleared);
        cmd_daily_with_check_in(v, Some("2026-11-10"), None, None, Some(""), None, None).unwrap();
        assert_eq!(fs::read_to_string(vault.join(rel)).unwrap(), one_cleared);
        let both = cmd_daily_with_check_in(v, Some("2026-11-10"), None, None, Some(""), Some(" "), None).unwrap();
        assert_eq!(both["journalView"]["energy"], "");
        let both_cleared = one_cleared.replace("energy: high", "energy: \"\"");
        assert_eq!(fs::read_to_string(vault.join(rel)).unwrap(), both_cleared);
        assert_eq!(cmd_read(v, rel).unwrap()["journalView"]["mood"], "");
        assert!(cmd_daily_with_check_in(v, Some("invalid"), None, None, Some("good"), None, None).is_err());
        assert_eq!(fs::read_to_string(vault.join(rel)).unwrap(), both_cleared);
        let retry = cmd_daily_with_check_in(v, Some("2026-11-10"), None, None, Some("good"), None, None).unwrap();
        assert_eq!(retry["journalView"]["mood"], "good");
        assert_eq!(retry["journalView"]["energy"], "");
        assert_eq!(fs::read_to_string(vault.join(rel)).unwrap(), both_cleared.replace("Mood: \"\"", "Mood: good"));
        fs::remove_dir_all(vault).unwrap();
    }

    #[test]
    fn test_check_in_new_mixed_dates_and_explicit_empty_are_independent() {
        let vault = make_temp_vault("checkin-mixed");
        let v = vault.to_str().unwrap();
        let old = cmd_daily_with_check_in(v, Some("2026-11-09"), None, None, Some("great"), Some("high"), None).unwrap();
        let old_path = vault.join(old["relPath"].as_str().unwrap());
        let old_bytes = fs::read(&old_path).unwrap();
        let new = cmd_daily_with_check_in(v, Some("2026-11-10"), None, None, Some(""), Some("medium"), None).unwrap();
        let new_rel = new["relPath"].as_str().unwrap();
        assert_eq!(new["journalView"]["mood"], "");
        assert_eq!(new["journalView"]["energy"], "medium");
        cmd_daily_with_check_in(v, Some("2026-11-10"), None, None, Some("good"), None, None).unwrap();
        assert_eq!(cmd_read(v, new_rel).unwrap()["journalView"]["energy"], "medium");
        let clear = cmd_daily_with_check_in(v, Some("2026-11-10"), None, None, None, Some(""), None).unwrap();
        assert_eq!(clear["journalView"]["mood"], "good");
        assert_eq!(clear["journalView"]["energy"], "");
        assert_eq!(fs::read(old_path).unwrap(), old_bytes);
        let local_today = cmd_scan_for_date(v, Some("2026-11-10")).unwrap();
        assert_eq!(local_today["todayJournal"]["date"], "2026-11-10");
        assert_eq!(local_today["todayJournal"]["relPath"], new_rel);
        assert_eq!(local_today["todayJournal"]["mood"], "good");
        let previous_day = cmd_scan_for_date(v, Some("2026-11-09")).unwrap();
        assert_eq!(previous_day["todayJournal"]["mood"], "great");
        assert!(cmd_scan_for_date(v, Some("2026-02-30")).is_err());
        fs::remove_dir_all(vault).unwrap();
    }

    #[test]
    fn test_check_in_weight_preserves_legacy_bytes_and_scan() {
        let vault = make_temp_vault("checkin-weight");
        let rel = "Journal/11-11-2026-Wednesday.md";
        fs::create_dir(vault.join("Journal")).unwrap();
        let raw = "---\r\njournal: Daily Notes\r\nmood: good\r\nweight: 64.2\r\ncustom:\r\n  - untouched\r\n...\r\n\r\nBody stays intact.\r\n";
        fs::write(vault.join(rel), raw).unwrap();
        let v = vault.to_str().unwrap();
        let res = cmd_daily_with_check_in(v, Some("2026-11-11"), None, None, None, None, Some("65.5")).unwrap();
        assert_eq!(res["journalView"]["weight"], "65.5");
        assert_eq!(res["journalView"]["hasWeight"], true);
        assert_eq!(res["journalView"]["mood"], "good");
        let saved = fs::read_to_string(vault.join(rel)).unwrap();
        assert_eq!(saved, raw.replace("weight: 64.2", "weight: 65.5"));
        let scanned = cmd_scan_for_date(v, Some("2026-11-11")).unwrap();
        assert_eq!(scanned["todayJournal"]["weight"], "65.5");
        assert_eq!(scanned["todayJournal"]["hasWeight"], true);
        fs::remove_dir_all(vault).unwrap();
    }

    #[test]
    fn test_journal_weather_missing_preserved_replace_and_legacy_bytes() {
        let vault = make_temp_vault("weather-legacy");
        fs::create_dir(vault.join("Journal")).unwrap();
        let rel = "Journal/10-11-2026-Tuesday.md";
        let raw = "---\r\njournal: Daily Notes\r\nMood: good\r\ncreated: 2020-01-02T03:04:05\r\n# Owner comment\r\n...\r\n\r\n## Daily Log\r\nUnchanged thoughts.\r\n```dataviewjs\r\nkeep()\r\n```";
        fs::write(vault.join(rel), raw).unwrap();
        let v = vault.to_str().unwrap();
        let initial = cmd_journal_weather(v, rel, "Initial, 21°C", false).unwrap();
        assert_eq!(initial["weatherWriteApplied"], true);
        assert_eq!(initial["journalView"]["weather"], "Initial, 21°C");
        let saved = fs::read_to_string(vault.join(rel)).unwrap();
        assert!(saved.starts_with(raw.split("...\r\n").next().unwrap()));
        assert_eq!(saved.split("...\r\n").nth(1), raw.split("...\r\n").nth(1));
        let preserved = cmd_journal_weather(v, rel, "Later, 26°C", false).unwrap();
        assert_eq!(preserved["weatherWriteApplied"], false);
        assert_eq!(preserved["journalView"]["weather"], "Initial, 21°C");
        assert_eq!(fs::read_to_string(vault.join(rel)).unwrap(), saved);
        assert!(cmd_journal_weather(v, "../outside.md", "Later", false).is_err());
        assert_eq!(fs::read_to_string(vault.join(rel)).unwrap(), saved);
        let explicit = cmd_journal_weather(v, rel, "Later, 26°C", true).unwrap();
        assert_eq!(explicit["weatherWriteApplied"], true);
        assert_eq!(explicit["journalView"]["weather"], "Later, 26°C");
        assert_eq!(fs::read_to_string(vault.join(rel)).unwrap(), saved.replace("Initial, 21°C", "Later, 26°C"));
        fs::write(vault.join("ordinary.md"), "# ordinary\nKeep this.").unwrap();
        assert!(cmd_journal_weather(v, "ordinary.md", "Later", false).is_err());
        assert_eq!(fs::read_to_string(vault.join("ordinary.md")).unwrap(), "# ordinary\nKeep this.");
        fs::remove_dir_all(vault).unwrap();
    }

    #[test]
    fn test_file_classification() {
        assert_eq!(classify_extension("md").0, FileCategory::Markdown);
        assert_eq!(classify_extension(".rs").0, FileCategory::Code);
        assert_eq!(classify_extension("qml").0, FileCategory::Code);
        assert_eq!(classify_extension("png").0, FileCategory::Image);
        assert_eq!(classify_extension("webp").0, FileCategory::Image);
        assert_eq!(classify_extension("pdf").0, FileCategory::External);
        assert_eq!(classify_extension("docx").0, FileCategory::External);
        assert_eq!(classify_extension("mp4").0, FileCategory::External);
    }

    #[test]
    fn test_path_traversal_rejected() {
        let vault = make_temp_vault("traversal");
        let canon = resolve_vault_root(vault.to_str().unwrap()).unwrap();
        assert!(resolve_inside_vault(&canon, "../outside.md", false).is_err());
        assert!(resolve_inside_vault(&canon, "/etc/passwd", false).is_err());
        assert!(resolve_inside_vault(&canon, "a/../../outside.md", false).is_err());
        let _ = fs::remove_dir_all(&vault);
    }

    #[test]
    fn test_multibyte_vietnamese_filename_and_submodule_skip() {
        let vault = make_temp_vault("utf8");
        let v_str = vault.to_str().unwrap();

        // Multi-byte UTF-8 stem that previously triggered a byte-slice panic in detect_journal_date_from_path
        cmd_write(
            v_str,
            "60_Digital_Library/Sự_im_lặng.md",
            "---\ntitle: \"Sự im lặng của bầy cừu\"\ntags: [Book]\n---\n# Sự im lặng\nNội dung tiếng Việt.\n",
        )
        .unwrap();

        // Nested git submodule inside vault should be skipped during scan
        let sub_dir = vault.join("10_Projects/SubRepo");
        fs::create_dir_all(&sub_dir).unwrap();
        fs::write(sub_dir.join(".git"), "gitdir: ../../.git/modules/SubRepo\n").unwrap();
        fs::write(sub_dir.join("README.md"), "# Should be skipped\n").unwrap();

        // .obsidian/hotkeys.json
        let obs_dir = vault.join(".obsidian");
        fs::create_dir_all(&obs_dir).unwrap();
        fs::write(
            obs_dir.join("hotkeys.json"),
            r#"{"command-palette:open":[{"modifiers":["Alt"],"key":"Enter"}],"zk-prefixer":[{"modifiers":["Mod"],"key":"N"}]}"#,
        )
        .unwrap();

        let scan = cmd_scan(v_str).unwrap();
        assert_eq!(scan["stats"]["noteCount"], 1);
        assert_eq!(scan["stats"]["bookCount"], 1);
        assert_eq!(scan["vaultHotkeys"]["command-palette:open"]["primary"], "Alt+Enter");
        assert_eq!(scan["vaultHotkeys"]["zk-prefixer"]["primary"], "Ctrl+N");

        let del = cmd_delete(v_str, "60_Digital_Library/Sự_im_lặng.md").unwrap();
        assert_eq!(del["ok"], true);
        assert!(vault.join(".trash/Sự_im_lặng.md").exists());

        let _ = fs::remove_dir_all(&vault);
    }

    #[test]
    fn test_hybrid_parser_and_block_folding() {
        let content = "---\ntitle: \"Nexus Architecture\"\ntags: [rust, graph]\naliases: [NexusDoc]\n---\n\n# Overview\n- Parent bullet with [[Second Note|Second]] and #knowledge\n  - Child bullet 1\n  - [ ] Child task open\n- [x] Top done task\n\n> [!NOTE] Important Callout\n> Callout body line\n\n| Feature | Status |\n| --- | --- |\n| Vim | Ready |\n\n```rust\nfn main() {}\n```\n";
        let lines: Vec<String> = content.lines().map(|s| s.to_string()).collect();
        let (fm, tags, aliases, body_start) = parse_frontmatter(&lines);
        assert_eq!(fm.get("title").map(|s| s.as_str()), Some("Nexus Architecture"));
        assert_eq!(tags, vec!["rust".to_string(), "graph".to_string()]);
        assert_eq!(aliases, vec!["NexusDoc".to_string()]);

        let (blocks, outline, _, open_tasks, done_tasks) = parse_blocks(&lines, body_start);
        assert_eq!(outline.len(), 1);
        assert_eq!(outline[0].text, "Overview");
        assert_eq!(open_tasks, 1);
        assert_eq!(done_tasks, 1);

        // Heading block should be foldable across the entire section
        assert_eq!(blocks[0].kind, "heading");
        assert!(blocks[0].foldable);
        // Parent bullet should be foldable over its 2 indented children
        assert_eq!(blocks[1].kind, "bullet");
        assert!(blocks[1].foldable);
        assert_eq!(blocks[1].wikilinks, vec!["Second Note".to_string()]);
        assert_eq!(blocks[1].tags, vec!["knowledge".to_string()]);
        // Callout, table, code
        assert!(blocks.iter().any(|b| b.kind == "callout" && b.callout_type == "NOTE"));
        assert!(blocks.iter().any(|b| b.kind == "table" && b.table_rows.len() == 1));
        assert!(blocks.iter().any(|b| b.kind == "code" && b.lang == "rust"));
    }

    #[test]
    fn test_vault_scan_graph_backlinks_and_daily() {
        let vault = make_temp_vault("graph");
        let v_str = vault.to_str().unwrap();

        cmd_write(
            v_str,
            "10_Projects/Alpha.md",
            "---\ntitle: Alpha\ntags: [core]\n---\n# Alpha\nLinks to [[Beta]] and has\n- [ ] Task one\n",
        )
        .unwrap();
        cmd_write(
            v_str,
            "10_Projects/Beta.md",
            "# Beta\nBacklink to [[Alpha]] here.\n",
        )
        .unwrap();
        cmd_write(
            v_str,
            "20_Notes/Gamma.md",
            "# Gamma\nThis note mentions Alpha without wikilink.\n",
        )
        .unwrap();

        let scan_res = cmd_scan(v_str).unwrap();
        assert_eq!(scan_res["stats"]["noteCount"], 3);
        assert_eq!(scan_res["stats"]["openTasks"], 1);
        assert_eq!(scan_res["graph"]["edges"].as_array().unwrap().len(), 2);

        let alpha = cmd_read(v_str, "10_Projects/Alpha.md").unwrap();
        assert_eq!(alpha["backlinks"].as_array().unwrap().len(), 1);
        assert_eq!(alpha["backlinks"][0]["relPath"], "10_Projects/Beta.md");
        assert_eq!(alpha["unlinkedMentions"].as_array().unwrap().len(), 1);
        assert_eq!(alpha["unlinkedMentions"][0]["relPath"], "20_Notes/Gamma.md");

        // Link the unlinked mention in Gamma.md
        let mention_line = alpha["unlinkedMentions"][0]["line"].as_u64().unwrap() as usize;
        cmd_link_mention(v_str, "20_Notes/Gamma.md", mention_line, "Alpha").unwrap();
        let alpha_after = cmd_read(v_str, "10_Projects/Alpha.md").unwrap();
        assert_eq!(alpha_after["backlinks"].as_array().unwrap().len(), 2);

        // Toggle task in Alpha.md
        let toggled = cmd_toggle_todo(v_str, "10_Projects/Alpha.md", 7).unwrap();
        assert_eq!(toggled["openTasks"], 0);
        assert_eq!(toggled["doneTasks"], 1);

        // Daily note creation and calendar check
        let daily = cmd_daily(v_str, Some("2026-11-07"), None, None).unwrap();
        assert_eq!(daily["category"], "markdown");
        assert!(daily["relPath"].as_str().unwrap().contains("2026"));

        let cal = cmd_calendar(v_str, 2026, 11).unwrap();
        let cells = cal["cells"].as_array().unwrap();
        assert_eq!(cells.len(), 42);
        assert!(cells.iter().any(|c| c["dateStr"] == "2026-11-07" && c["hasJournal"] == true));

        let _ = fs::remove_dir_all(&vault);
    }

    #[test]
    fn test_title_extraction_and_custom_views_and_tag_clusters() {
        let vault = make_temp_vault("custom_views");
        let v_str = vault.to_str().unwrap();

        // 1. Journal note without frontmatter title and starting with `## Day Planner` must use filename stem as title
        cmd_write(
            v_str,
            "00_Capture/01_Journal/2026/August/01-08-2026-Saturday.md",
            "## Day Planner\n- [ ] 06:00 - 06:15 Wake up\n\n---\n#Daily-notes\n",
        )
        .unwrap();
        cmd_write(
            v_str,
            "00_Capture/01_Journal/2026/August/02-08-2026-Sunday.md",
            "## Day Planner\n- [x] 07:00 - 08:00 Run\n\n---\n#Daily-notes\n",
        )
        .unwrap();

        let j_doc = cmd_read(v_str, "00_Capture/01_Journal/2026/August/01-08-2026-Saturday.md").unwrap();
        assert_eq!(j_doc["title"], "01-08-2026-Saturday");
        assert_eq!(j_doc["noteKind"], "journal");

        // 2. Frontmatter-only Movie note with multi-line YAML lists
        cmd_write(
            v_str,
            "20_Personal_Life/25_Media_Tracker/Movies/Inception.md",
            "---\ncategories:\n  - \"[[Movies]]\"\ntitle: \"Inception\"\nyear: 2010\nscoreImdb: 8.8\nstatus: \"Watched\"\nwatched: true\nfavorite: true\ngenre:\n  - \"[[Action]]\"\n  - \"[[Sci-Fi]]\"\ndirector:\n  - \"[[Christopher Nolan]]\"\nplot: \"A thief who steals corporate secrets.\"\n---\n",
        )
        .unwrap();
        let m_doc = cmd_read(v_str, "20_Personal_Life/25_Media_Tracker/Movies/Inception.md").unwrap();
        assert_eq!(m_doc["noteKind"], "movie");
        assert_eq!(m_doc["dossier"]["genre"], "Action, Sci-Fi");
        assert_eq!(m_doc["dossier"]["director"], "Christopher Nolan");
        assert!(!m_doc["blocks"].as_array().unwrap().is_empty());

        // 3. Cornell note with Marginalia markers
        cmd_write(
            v_str,
            "00_Capture/02_Cornell/Sample.md",
            "---\ncourse: \"[[Biology]]\"\ntopic: \"Photosynthesis\"\ntags:\n  - cornell-notes\n---\n\n## Photosynthesis\n\n### ?\nWhat is photosynthesis?\n\n### Summary\n> [!SUMMARY] Summary\n> Light to chemical energy.\n",
        )
        .unwrap();
        let c_doc = cmd_read(v_str, "00_Capture/02_Cornell/Sample.md").unwrap();
        assert_eq!(c_doc["title"], "Sample");
        assert_eq!(c_doc["noteKind"], "cornell");
        assert_eq!(c_doc["dossier"]["course"], "Biology");
        assert!(c_doc["blocks"].as_array().unwrap().iter().any(|b| b["calloutType"] == "CORNELL_QUESTION"));

        // 4. Template exclusion, Onion site url_onion/FOR category, and incomplete H1 Zettelkasten stem fallback
        cmd_write(
            v_str,
            "90_System/91_Templates/Zettelkasten_Template.md",
            "---\ntags:\n  - zettelkasten\n---\n# <% noteTitle %>\n",
        )
        .unwrap();
        cmd_write(
            v_str,
            "70_Interests_&_Research/78_Onion_Sites/FOR/Dread.md",
            "---\ncategory: FOR\nstatus: Active\ntags: OnionSite\ntitle: Dread\nurl_onion: dready.onion\n---\n",
        )
        .unwrap();
        cmd_write(
            v_str,
            "99_Archives/Zettlekasten_Archives/202607131817 - Assignment on Wednesday.md",
            "---\ntype:\n  - Permanent\n---\n# 202607131817 -\nBody text.\n",
        )
        .unwrap();

        let z_doc = cmd_read(v_str, "99_Archives/Zettlekasten_Archives/202607131817 - Assignment on Wednesday.md").unwrap();
        assert_eq!(z_doc["title"], "202607131817 - Assignment on Wednesday");
        assert_eq!(z_doc["noteKind"], "zettelkasten");

        let scan = cmd_scan(v_str).unwrap();
        assert_eq!(scan["collections"]["movies"].as_array().unwrap().len(), 1);
        assert_eq!(scan["collections"]["cornell"].as_array().unwrap().len(), 1);
        assert_eq!(scan["collections"]["websites"].as_array().unwrap().len(), 1);
        assert_eq!(scan["collections"]["websites"][0]["url"], "dready.onion");
        assert_eq!(scan["collections"]["websites"][0]["category"], "Forums & Communities");
        assert_eq!(scan["collections"]["zettelkasten"].as_array().unwrap().len(), 1);
        assert!(!scan["graph"]["edges"].as_array().unwrap().is_empty());

        let _ = fs::remove_dir_all(&vault);
    }

    #[test]
    fn test_folder_colors_set_frontmatter_finance_and_all_custom_views() {
        let vault = make_temp_vault("all_cv");
        let v_str = vault.to_str().unwrap();

        // Setup .obsidian/plugins/obsidian-icon-folder/data.json
        let icon_dir = vault.join(".obsidian/plugins/obsidian-icon-folder");
        fs::create_dir_all(&icon_dir).unwrap();
        fs::write(
            icon_dir.join("data.json"),
            r#"{"00_Capture":"LiInbox","20_Personal_Life":"LiHeart"}"#,
        )
        .unwrap();

        // Journal note with mood/energy updates via cmd_set_frontmatter and `## Daily Log` section
        cmd_write(
            v_str,
            "00_Capture/01_Journal/2026/November/06-11-2026-Friday.md",
            "---\njournal: Daily Notes\nmood: Good\nenergy: 7\n---\n\n---\n\n## Day Planner\n- [ ] 08:00 Work\n\n---\n\n## Daily Log\n\n---\n\nBody Pic:\nLogged thoughts today.\n",
        )
        .unwrap();
        let updated_j = cmd_set_frontmatter(
            v_str,
            "00_Capture/01_Journal/2026/November/06-11-2026-Friday.md",
            r#"{"mood":"Great","energy":9,"weather":"28°C · Clear","weight":"65.5"}"#,
        )
        .unwrap();
        assert_eq!(updated_j["noteKind"], "journal");
        assert_eq!(updated_j["journalView"]["mood"], "Great");
        assert_eq!(updated_j["journalView"]["energy"], "9");
        assert_eq!(updated_j["journalView"]["weather"], "28°C · Clear");
        assert_eq!(updated_j["journalView"]["weight"], "65.5");
        let log_txt = updated_j["journalView"]["dailyLogText"].as_str().unwrap();
        assert!(log_txt.starts_with("Body Pic:"));
        assert!(log_txt.contains("Logged thoughts today."));
        assert!(!log_txt.contains("Day Planner"));

        // Cornell note with H3 cue titles (`### ? Title`) and body notes
        cmd_write(
            v_str,
            "00_Capture/02_Cornell/Sample — Quang hợp.md",
            "---\ncategories:\n  - \"[[Cornell Notes]]\"\ncourse: \"[[Sinh học]]\"\ntopic: \"Quang hợp\"\n---\n\n## Learning Objectives\n- [x] Hiểu pha sáng\n\n## Notes\n\n### ? Quang hợp là gì?\nQuá trình chuyển đổi năng lượng ánh sáng.\n\n### ! Key Concept\nDiệp lục hấp thụ ánh sáng đỏ và xanh.\n\n## Summary\nTổng kết quang hợp.\n",
        )
        .unwrap();
        let c_rich = cmd_read(v_str, "00_Capture/02_Cornell/Sample — Quang hợp.md").unwrap();
        assert_eq!(c_rich["noteKind"], "cornell");
        assert_eq!(c_rich["cornellView"]["cueCount"], 2);
        assert_eq!(c_rich["cornellView"]["cues"][0]["cue"], "Quang hợp là gì?");
        assert!(c_rich["cornellView"]["cues"][0]["notes"]
            .as_str()
            .unwrap()
            .contains("chuyển đổi năng lượng"));

        // Recipe note with YAML lists + full frontmatter state roundtrip
        cmd_write(
            v_str,
            "20_Personal_Life/26_Food_&_Drinks/Recipes/Beef pho.md",
            "---\ncategories:\n  - \"[[Recipes]]\"\nrecipe_category: Beef\ncuisine: Vietnamese\ndifficulty: Medium\nprep_time: 45\ncook_time: 180\ncalories: 620 kcal\nrating: 9\nsource: Family Recipe\nrecipe_description: Aromatic beef noodle soup.\nservings: 2\ningredients:\n  - Beef Stock | 1 L\n  - Rice Noodles | 200 g\ninstructions:\n  - Simmer stock, onion, and ginger.\n  - Slice beef and serve.\ntips:\n  - Char the ginger and onion first.\npairs_well_with:\n  - Thai basil and lime wedges\n---\n\n## Personal Notes\nDelicious.\n",
        )
        .unwrap();
        let r_doc = cmd_read(v_str, "20_Personal_Life/26_Food_&_Drinks/Recipes/Beef pho.md").unwrap();
        assert_eq!(r_doc["noteKind"], "recipe");
        assert_eq!(r_doc["recipeView"]["ingredients"].as_array().unwrap().len(), 2);
        assert_eq!(r_doc["recipeView"]["instructions"].as_array().unwrap().len(), 2);
        assert_eq!(r_doc["recipeView"]["tips"].as_array().unwrap().len(), 1);
        assert_eq!(r_doc["recipeView"]["pairings"].as_array().unwrap().len(), 1);
        assert_eq!(r_doc["recipeView"]["difficulty"], "Medium");
        assert_eq!(r_doc["recipeView"]["prepTime"], "45");
        assert_eq!(r_doc["recipeView"]["cookTime"], "180");
        assert_eq!(r_doc["recipeView"]["calories"], "620 kcal");
        assert_eq!(r_doc["recipeView"]["rating"], "9");
        assert_eq!(r_doc["recipeView"]["source"], "Family Recipe");
        assert_eq!(r_doc["recipeView"]["description"], "Aromatic beef noodle soup.");
        assert_eq!(r_doc["recipeView"]["personalNotes"], "Delicious.");

        let r_updated = cmd_set_frontmatter(
            v_str,
            "20_Personal_Life/26_Food_&_Drinks/Recipes/Beef pho.md",
            r#"{"ingredients_done":[0],"steps_progress":1}"#,
        )
        .unwrap();
        assert_eq!(r_updated["recipeView"]["ingredientsDone"], serde_json::json!([0]));
        assert_eq!(r_updated["recipeView"]["stepsProgress"], 1);

        // Recipe note with Markdown section fallbacks (`## Ingredients`, `## Instructions`, `## Tips`, `## Pairs Well With`)
        cmd_write(
            v_str,
            "20_Personal_Life/26_Food_&_Drinks/Recipes/Markdown Recipe.md",
            "---\ncategories:\n  - \"[[Recipes]]\"\ncuisine: Italian\n---\n\n## Ingredients\n- [ ] Spaghetti | 200 g\n- Guanciale | 100 g\n\n## Instructions\n1. Boil pasta in salted water.\n2. Crisp guanciale and toss with egg mixture.\n\n## Tips\n- Remove pan from heat before adding eggs.\n\n## Pairs Well With\n- Crisp white wine\n\n## Personal Notes\nUse Pecorino Romano.\n",
        )
        .unwrap();
        let r_md = cmd_read(v_str, "20_Personal_Life/26_Food_&_Drinks/Recipes/Markdown Recipe.md").unwrap();
        assert_eq!(r_md["noteKind"], "recipe");
        assert_eq!(
            r_md["recipeView"]["ingredients"],
            serde_json::json!(["Spaghetti | 200 g", "Guanciale | 100 g"])
        );
        assert_eq!(
            r_md["recipeView"]["instructions"],
            serde_json::json!([
                "Boil pasta in salted water.",
                "Crisp guanciale and toss with egg mixture."
            ])
        );
        assert_eq!(
            r_md["recipeView"]["tips"],
            serde_json::json!(["Remove pan from heat before adding eggs."])
        );
        assert_eq!(
            r_md["recipeView"]["pairings"],
            serde_json::json!(["Crisp white wine"])
        );
        assert_eq!(r_md["recipeView"]["personalNotes"], "Use Pecorino Romano.");

        // Book note with star-emoji rating
        cmd_write(
            v_str,
            "20_Personal_Life/24_Book_Tracker/Books/SampleBook.md",
            "---\nTitle: Sample Book\nAuthor: Jules Verne\nCurrentPage: 160\nTotalPages: 320\nRating: ⭐⭐⭐⭐\n---\n",
        )
        .unwrap();
        let b_doc = cmd_read(v_str, "20_Personal_Life/24_Book_Tracker/Books/SampleBook.md").unwrap();
        assert_eq!(b_doc["noteKind"], "book");
        assert_eq!(b_doc["dossier"]["rating"], "8");
        assert_eq!(b_doc["dossier"]["currentPage"], "160");
        assert_eq!(b_doc["dossier"]["pages"], "320");

        // Exercise note with `name:` frontmatter and `## How to Perform` steps
        cmd_write(
            v_str,
            "20_Personal_Life/33_Bodybuilding/Gym_n_Calisthenics_Exercises/PushUp.md",
            "---\nname: Push-Up\nlevel: beginner\nforce: push\nmechanic: compound\nprimaryMuscles:\n  - chest\n---\n\n## How to Perform\n1. Plank position.\n2. Lower chest to floor.\n",
        )
        .unwrap();
        let e_doc = cmd_read(
            v_str,
            "20_Personal_Life/33_Bodybuilding/Gym_n_Calisthenics_Exercises/PushUp.md",
        )
        .unwrap();
        assert_eq!(e_doc["noteKind"], "exercise");
        assert_eq!(e_doc["title"], "Push-Up");
        assert_eq!(e_doc["dossier"]["muscleGroup"], "chest");
        assert_eq!(e_doc["exerciseView"]["steps"].as_array().unwrap().len(), 2);

        // Finance add + Finance Report
        cmd_finance_add(v_str, "transaction", "Coffee", 45000.0, "expense", "Food", "Cash").unwrap();
        cmd_finance_add(v_str, "transaction", "Salary", 15000000.0, "income", "Salary", "Bank").unwrap();
        cmd_write(
            v_str,
            "20_Personal_Life/22_Finance/Finance Report.md",
            "---\ncategories:\n  - \"[[Finance Report]]\"\n---\n",
        )
        .unwrap();
        let f_doc = cmd_read(v_str, "20_Personal_Life/22_Finance/Finance Report.md").unwrap();
        assert_eq!(f_doc["noteKind"], "finance");
        assert_eq!(f_doc["financeSummary"]["totalExpense"], 45000.0);
        assert_eq!(f_doc["financeSummary"]["totalIncome"], 15000000.0);
        assert_eq!(f_doc["financeSummary"]["categories"].as_array().unwrap().len(), 1);
        assert_eq!(f_doc["financeSummary"]["categories"][0]["category"], "Food");
        assert_eq!(f_doc["financeSummary"]["categories"][0]["amount"], 45000.0);

        // Journal note with `## Notes & Log\n-` must strip `## Notes & Log` from dailyLogText/dailyLogRichHtml
        cmd_write(
            v_str,
            "00_Capture/01_Journal/2026/November/08-11-2026-Sunday.md",
            "---\njournal: Daily Notes\n---\n\n## Day Planner\n- [x] 06:00 - 07:00 Run 5km\n\n---\n\n## Notes & Log\n-\n",
        )
        .unwrap();
        let j_sun = cmd_read(v_str, "00_Capture/01_Journal/2026/November/08-11-2026-Sunday.md").unwrap();
        assert_eq!(j_sun["noteKind"], "journal");
        assert_eq!(j_sun["journalView"]["dailyLogText"], "-");
        assert!(
            !j_sun["journalView"]["dailyLogRichHtml"]
                .as_str()
                .unwrap()
                .contains("Notes &amp; Log")
        );

        // Real-vault Cornell template (`## Session Metadata` / `### ! Session Metadata` / bulleted `- **Course:** [[hdh]]` / `## Next Review` / `### V- Review Schedule`)
        cmd_write(
            v_str,
            "00_Capture/02_Cornell/shda.md",
            "---\ncssclasses:\n  - cornell-note\n---\n\n![[90_System/93_Configuration/Custom_Views/Cornell/Cornell.html]]\n\n## Session Metadata\n### ! Session Metadata\n- **Course:** [[hdh]]\n- **Topic:** Process Scheduling\n- **Date:** 2026-04-16\n- **Source:** Chapter 5\n- **Status:** #status/draft\n\n---\n\n## Learning Objectives\n### . Learning Goals\n- [ ] Understand preemptive scheduling\n\n---\n\n## Main Notes\n### ? Main Question\n- **Key concept:** Context switch overhead\n- **Related note:** [[ ]]\n\n---\n\n## Summary\n### * Feynman Summary\n- CPU scheduler selects from ready queue.\n\n---\n\n## Active Recall\n### ? Self-Test\n1. What is convoy effect?\n\n---\n\n## Next Review\n### V- Review Schedule\n- **Review 1 (1 day):** 2026-04-17\n",
        )
        .unwrap();
        let c_shda = cmd_read(v_str, "00_Capture/02_Cornell/shda.md").unwrap();
        assert_eq!(c_shda["noteKind"], "cornell");
        assert_eq!(c_shda["cornellView"]["course"], "hdh");
        assert_eq!(c_shda["cornellView"]["topic"], "Process Scheduling");
        assert_eq!(c_shda["cornellView"]["date"], "2026-04-16");
        assert_eq!(c_shda["cornellView"]["source"], "Chapter 5");
        assert_eq!(c_shda["cornellView"]["cueCount"], 1);
        assert_eq!(c_shda["cornellView"]["cues"][0]["cue"], "Main Question");
        assert!(c_shda["cornellView"]["cues"][0]["richHtml"]
            .as_str()
            .unwrap()
            .contains("Related note"));
        assert!(!c_shda["cornellView"]["summary"]
            .as_str()
            .unwrap()
            .contains("Feynman Summary"));
        assert_eq!(
            c_shda["cornellView"]["objectives"],
            serde_json::json!(["Understand preemptive scheduling"])
        );
        assert_eq!(
            c_shda["cornellView"]["recallQuestions"],
            serde_json::json!(["What is convoy effect?"])
        );

        // Real-vault Zettelkasten note with cluster headings (`## CỤM 6: NỘI DUNG GIÁO DỤC...`), `_italic_`, and `[[01:06](url)]`
        cmd_write(
            v_str,
            "99_Archives/Zettlekasten_Archives/202608071114 - Quick Note.md",
            "---\nid: 202608071114\ntitle: 202608071114 - Quick Note\ntype:\n  - Permanent\n  - Literature\n  - Fleeting\ncssclasses:\n  - zettelkasten-note\n---\n\n![[90_System/93_Configuration/Custom_Views/Zettelkasten/Zettelkasten.html]]\n# 202608071114 - Quick Note\n\n# CỤM KIẾN THỨC ÔN THI TỰ LUẬN MỞ\n\n## HỌC PHẦN: HOẠT ĐỘNG TRẢI NGHIỆM (2 TÍN CHỈ)\n\n_(Nguồn: Tài liệu tìm hiểu chương trình HĐTN, 2019)_\n\n## CỤM 1: VỊ TRÍ, ĐẶC ĐIỂM MÔN HỌC\n\n- _Giáo dục cơ bản_: định hướng [[Alpha]] và [[01:06](https://youtu.be/demo)].\n\n## CỤM 6: NỘI DUNG GIÁO DỤC — 4 MẠCH NỘI DUNG HOẠT ĐỘNG\n\n- Hoạt động hướng vào bản thân.\n\n<center>End</center>\n",
        )
        .unwrap();
        let zk_doc = cmd_read(
            v_str,
            "99_Archives/Zettlekasten_Archives/202608071114 - Quick Note.md",
        )
        .unwrap();
        assert_eq!(zk_doc["noteKind"], "zettelkasten");
        assert_eq!(zk_doc["zettelkastenView"]["zettelType"], "Permanent");
        assert_eq!(zk_doc["zettelkastenView"]["connectionCount"], 2);
        let zk_core = zk_doc["zettelkastenView"]["coreIdea"].as_str().unwrap();
        let zk_content = zk_doc["zettelkastenView"]["contentSection"].as_str().unwrap();
        let zk_content_html = zk_doc["zettelkastenView"]["contentRichHtml"].as_str().unwrap();
        assert!(zk_core.contains("CỤM KIẾN THỨC ÔN THI TỰ LUẬN MỞ"));
        assert!(zk_core.contains("HỌC PHẦN: HOẠT ĐỘNG TRẢI NGHIỆM"));
        assert!(!zk_content.contains("HỌC PHẦN: HOẠT ĐỘNG TRẢI NGHIỆM"));
        assert!(zk_content.contains("## CỤM 1: VỊ TRÍ, ĐẶC ĐIỂM MÔN HỌC"));
        assert!(zk_content.contains("## CỤM 6: NỘI DUNG GIÁO DỤC — 4 MẠCH NỘI DUNG HOẠT ĐỘNG"));
        assert!(zk_content_html.contains("<i>Giáo dục cơ bản</i>"));
        assert!(zk_content_html.contains("href=\"https://youtu.be/demo\""));

        let scan = cmd_scan(v_str).unwrap();
        let top = scan["topFolders"].as_array().unwrap();
        let cap_folder = top.iter().find(|f| f["name"] == "00_Capture").unwrap();
        assert_eq!(cap_folder["colorHex"], "#82c2cf");
        assert_eq!(cap_folder["iconName"], "inbox");

        let _ = fs::remove_dir_all(&vault);
    }

    #[test]
    fn test_incremental_scan_cache_hits_invalidation_and_delete_pruning() {
        let vault = make_temp_vault("incremental-cache");
        let cache_dir = make_temp_vault("incremental-cache-file");
        let cache_file = cache_dir.join("vault-scan-cache.json");
        let v_str = vault.to_str().unwrap();
        let c_str = cache_file.to_str().unwrap();

        cmd_write(v_str, "Notes/Alpha.md", "---\ntitle: Alpha\ntags: [one]\n---\nAlpha body\n").unwrap();
        cmd_write(v_str, "Movies/Inception.md", "---\ncategories:\n  - \"[[Movies]]\"\ntitle: Inception\nyear: 2010\n---\n").unwrap();
        cmd_write(
            v_str,
            "Finance Report.md",
            "---\ncategories:\n  - Finance Report\n---\n## Income\n| Date | Source | Category | Amount |\n| --- | --- | --- | --- |\n| 2026-11-01 | Salary | Work | 10000000 |\n",
        )
        .unwrap();

        let scan1 = cmd_scan_for_date_with_cache(v_str, Some("2026-11-11"), Some(c_str)).unwrap();
        assert_eq!(scan1["stats"]["cacheHits"], 0);
        assert_eq!(scan1["stats"]["parsedNotes"], 3);
        assert!(scan1.get("_cachedEntries").is_none());
        assert_eq!(scan1["financeSummary"]["totalIncome"], 10000000.0);

        let scan2 = cmd_scan_for_date_with_cache(v_str, Some("2026-11-11"), Some(c_str)).unwrap();
        assert_eq!(scan2["stats"]["cacheHits"], 3);
        assert_eq!(scan2["stats"]["parsedNotes"], 0);
        assert_eq!(scan2["financeSummary"]["totalIncome"], 10000000.0);
        assert_eq!(scan2["collections"]["movies"].as_array().unwrap().len(), 1);

        // Modify Alpha.md with distinct size so mtime/size changes deterministically
        cmd_write(v_str, "Notes/Alpha.md", "---\ntitle: Alpha Updated\ntags: [one, two]\n---\nAlpha body with extra bytes\n").unwrap();
        let scan3 = cmd_scan_for_date_with_cache(v_str, Some("2026-11-11"), Some(c_str)).unwrap();
        assert_eq!(scan3["stats"]["cacheHits"], 2);
        assert_eq!(scan3["stats"]["parsedNotes"], 1);

        // Delete Movies/Inception.md with --cache-file and verify cache file is pruned immediately
        cmd_delete_with_cache(v_str, "Movies/Inception.md", Some(c_str)).unwrap();
        let cached_after_del: Value = serde_json::from_str(&fs::read_to_string(&cache_file).unwrap()).unwrap();
        assert!(!cached_after_del["_cachedEntries"].as_object().unwrap().contains_key("Movies/Inception.md"));
        assert!(cached_after_del["collections"]["movies"].as_array().unwrap().is_empty());

        let _ = fs::remove_dir_all(&vault);
        let _ = fs::remove_dir_all(&cache_dir);
    }

    #[test]
    fn test_skip_if_unchanged_and_ui_sidecar_cache() {
        let vault = make_temp_vault("skip-unchanged");
        let cache_dir = make_temp_vault("skip-unchanged-cache");
        let cache_file = cache_dir.join("vault-cache.json");
        let ui_sidecar = PathBuf::from(format!("{}.ui.json", cache_file.to_str().unwrap()));
        let v_str = vault.to_str().unwrap();
        let c_str = cache_file.to_str().unwrap();

        cmd_write(
            v_str,
            "Notes/Alpha.md",
            "---\ntitle: Alpha\ntags: [one]\n---\nAlpha body\n",
        )
        .unwrap();
        cmd_write(
            v_str,
            "Journal/2026-10-18.md",
            "---\nmood: calm\n---\nJournal body\n",
        )
        .unwrap();

        // a) First scan builds full cache + slim .ui.json sidecar without _cachedEntries
        let first = cmd_scan_for_date_with_cache_opts(v_str, Some("2026-10-18"), Some(c_str), true).unwrap();
        assert_eq!(first["ok"], true);
        assert!(first.get("unchanged").is_none());
        assert_eq!(first["todayJournal"]["date"], "2026-10-18");
        assert!(cache_file.is_file());
        assert!(ui_sidecar.is_file());

        let raw_full: Value = serde_json::from_str(&fs::read_to_string(&cache_file).unwrap()).unwrap();
        assert!(raw_full.get("_cachedEntries").is_some());
        assert!(raw_full.get("_scanSignature").and_then(|v| v.as_str()).is_some());

        let raw_ui: Value = serde_json::from_str(&fs::read_to_string(&ui_sidecar).unwrap()).unwrap();
        assert_eq!(raw_ui["ok"], true);
        assert!(raw_ui.get("_cachedEntries").is_none());
        assert!(raw_ui.get("_scanSignature").is_none());

        // b) Second scan with --skip-if-unchanged on same date returns unchanged: true
        let second = cmd_scan_for_date_with_cache_opts(v_str, Some("2026-10-18"), Some(c_str), true).unwrap();
        assert_eq!(second["ok"], true);
        assert_eq!(second["unchanged"], Value::Bool(true));
        assert_eq!(second["stats"]["parsedNotes"], 0);

        // c) Date rollover invalidates scan signature and refreshes todayJournal
        let next_day = cmd_scan_for_date_with_cache_opts(v_str, Some("2026-10-19"), Some(c_str), true).unwrap();
        assert_eq!(next_day["ok"], true);
        assert!(next_day.get("unchanged").is_none());
        assert_eq!(next_day["todayJournal"]["date"], "2026-10-19");

        // d) Delete prunes both cache files and removes _scanSignature so next scan rebuilds cleanly
        cmd_delete_with_cache(v_str, "Notes/Alpha.md", Some(c_str)).unwrap();
        let after_del_full: Value = serde_json::from_str(&fs::read_to_string(&cache_file).unwrap()).unwrap();
        assert!(after_del_full.get("_scanSignature").is_none());
        assert!(!after_del_full["_cachedEntries"].as_object().unwrap().contains_key("Notes/Alpha.md"));
        let after_del_ui: Value = serde_json::from_str(&fs::read_to_string(&ui_sidecar).unwrap()).unwrap();
        assert!(!after_del_ui["files"]
            .as_array()
            .unwrap()
            .iter()
            .any(|f| f["relPath"] == "Notes/Alpha.md"));

        let rebuilt = cmd_scan_for_date_with_cache_opts(v_str, Some("2026-10-19"), Some(c_str), true).unwrap();
        assert!(rebuilt.get("unchanged").is_none());
        assert!(!rebuilt["files"]
            .as_array()
            .unwrap()
            .iter()
            .any(|f| f["relPath"] == "Notes/Alpha.md"));

        let _ = fs::remove_dir_all(&vault);
        let _ = fs::remove_dir_all(&cache_dir);
    }

    #[test]
    fn test_mock_api_search_create_and_sync_all_six_kinds_preserving_user_data() {
        let vault = make_temp_vault("mock-api-six");
        let mock_dir = make_temp_vault("mock-api-fixtures");
        let v_str = vault.to_str().unwrap();

        fs::write(
            mock_dir.join("movie_search.json"),
            r#"{"results":[{"trackId":101,"trackName":"Arrival","releaseDate":"2016-11-11T08:00:00Z","artistName":"Denis Villeneuve","primaryGenreName":"Sci-Fi","artworkUrl100":"https://img.example/100x100bb.jpg","trackTimeMillis":6960000,"longDescription":"Linguist communicates with heptapods."}]}"#,
        ).unwrap();
        fs::write(
            mock_dir.join("tv_search.json"),
            r#"[{"show":{"id":202,"name":"Severance","premiered":"2022-02-18","status":"Running","runtime":55,"genres":["Drama","Sci-Fi"],"rating":{"average":8.7},"network":{"name":"Apple TV+"},"image":{"original":"https://img.example/sev.jpg"},"summary":"<p>Work and personal <b>memories</b> are surgically divided.</p>"}}]"#,
        ).unwrap();
        fs::write(
            mock_dir.join("book_search.json"),
            r#"{"docs":[{"key":"/works/OL1W","title":"Dune","author_name":["Frank Herbert"],"first_publish_year":1965,"cover_i":999,"number_of_pages_median":412,"isbn":["9780441172719"],"subject":["Science Fiction"],"first_sentence":["In the week before their departure to Arrakis."]}]}"#,
        ).unwrap();
        fs::write(
            mock_dir.join("game_search.json"),
            r#"{"items":[{"id":1145360,"name":"Hades","platforms":{"windows":true,"mac":true,"linux":false},"metascore":"93"}]}"#,
        ).unwrap();
        fs::write(
            mock_dir.join("game_sync.json"),
            r#"{"1145360":{"data":{"developers":["Supergiant Games"],"publishers":["Supergiant Games"],"short_description":"Defy the god of the dead.","metacritic":{"score":93},"release_date":{"date":"Sep 17, 2020"},"genres":[{"description":"Action"},{"description":"Indie"}]}}}"#,
        ).unwrap();
        fs::write(
            mock_dir.join("recipe_search.json"),
            r#"{"meals":[{"idMeal":"52772","strMeal":"Teriyaki Chicken","strCategory":"Chicken","strArea":"Japanese","strMealThumb":"https://img.example/teriyaki.jpg","strSource":"https://recipes.example/teriyaki","strIngredient1":"Soy Sauce","strMeasure1":"3 tbsp","strIngredient2":"Chicken Thighs","strMeasure2":"500g","strInstructions":"1. Mix soy sauce and mirin.\n2. Glaze chicken in pan."}]}"#,
        ).unwrap();
        fs::write(
            mock_dir.join("place_search.json"),
            r#"[{"place_id":777,"name":"Kyoto Imperial Palace","display_name":"Kyoto Imperial Palace, Kamigyo Ward, Kyoto, Japan","lat":"35.0254","lon":"135.7621","type":"attraction","address":{"city":"Kyoto","country":"Japan"},"extratags":{"wikipedia":"en:Kyoto Imperial Palace"}}]"#,
        ).unwrap();
        fs::write(
            mock_dir.join("place_wiki.json"),
            r#"{"originalimage":{"source":"https://img.example/kyoto.jpg"},"extract":"Historic imperial residence in Kyoto."}"#,
        ).unwrap();

        unsafe {
            env::set_var("ALIS_NEXUS_MOCK_API_DIR", mock_dir.to_str().unwrap());
        }

        let m_res = cmd_search_api(v_str, "movie", "Arrival", 5).unwrap();
        let m_cand = &m_res["results"][0];
        assert_eq!(m_cand["cover"], "https://img.example/600x600bb.jpg");
        let m_doc = cmd_create_with_candidate(v_str, "Movies/Arrival.md", Some("Arrival"), "movie", Some(&m_cand.to_string())).unwrap();
        assert_eq!(m_doc["dossier"]["director"], "Denis Villeneuve");
        assert_eq!(m_doc["dossier"]["runtime"], "116 min");

        let tv_res = cmd_search_api(v_str, "tv", "Severance", 5).unwrap();
        assert_eq!(tv_res["results"][0]["overview"], "Work and personal memories are surgically divided.");

        // Book sync must NOT hit weather, and must preserve user Rating/Status + body notes
        cmd_write(
            v_str,
            "Books/Dune.md",
            "---\nTitle: Dune\nStatus: Reading\nRating: ⭐⭐⭐⭐⭐\n---\n\n## Notes & Takeaways\nMy personal Arrakis reflection.\n",
        ).unwrap();
        let b_synced = cmd_sync_api(v_str, "Books/Dune.md", "book").unwrap();
        assert_eq!(b_synced["dossier"]["author"], "Frank Herbert");
        assert_eq!(b_synced["dossier"]["pages"], "412");
        assert_eq!(b_synced["dossier"]["status"], "Reading");
        assert_eq!(b_synced["dossier"]["ratingRaw"], "⭐⭐⭐⭐⭐");
        assert!(b_synced["content"].as_str().unwrap().contains("My personal Arrakis reflection."));
        assert!(b_synced["frontmatter"].get("weather").is_none());

        // Game sync WITHOUT existing steamappid resolves via title search + appdetails
        cmd_write(v_str, "Games/Hades.md", "---\ntitle: Hades\nstatus: Completed\nrating: 10\ntags:\n  - Game\n---\n\nMy run log.\n").unwrap();
        let g_synced = cmd_sync_api(v_str, "Games/Hades.md", "game").unwrap();
        assert_eq!(g_synced["dossier"]["developer"], "Supergiant Games");
        assert_eq!(g_synced["dossier"]["steamId"], "1145360");
        assert_eq!(g_synced["dossier"]["status"], "Completed");
        assert_eq!(g_synced["dossier"]["rating"], "10");

        // Recipe sync populates ingredients/instructions when absent, and preserves user ingredients when present
        cmd_write(v_str, "Recipes/Teriyaki Chicken.md", "---\ncategories:\n  - \"[[Recipes]]\"\ntitle: Teriyaki Chicken\n---\n\n## Personal Notes\nExtra ginger!\n").unwrap();
        let r_synced = cmd_sync_api(v_str, "Recipes/Teriyaki Chicken.md", "recipe").unwrap();
        assert_eq!(r_synced["recipeView"]["cuisine"], "Japanese");
        assert_eq!(r_synced["recipeView"]["ingredients"].as_array().unwrap().len(), 2);
        assert_eq!(r_synced["recipeView"]["personalNotes"], "Extra ginger!");

        // Place sync resolves coordinates + Wikipedia cover/extract
        cmd_write(v_str, "Places/Kyoto Imperial Palace.md", "---\ncategories:\n  - \"[[Places]]\"\ntitle: Kyoto Imperial Palace\nvisited: true\n---\n").unwrap();
        let p_synced = cmd_sync_api(v_str, "Places/Kyoto Imperial Palace.md", "place").unwrap();
        assert_eq!(p_synced["dossier"]["country"], "Japan");
        assert_eq!(p_synced["dossier"]["visited"], true);
        assert_eq!(p_synced["dossier"]["posterUrl"], "https://img.example/kyoto.jpg");

        unsafe {
            env::remove_var("ALIS_NEXUS_MOCK_API_DIR");
        }
        let _ = fs::remove_dir_all(&vault);
        let _ = fs::remove_dir_all(&mock_dir);
    }

    #[test]
    fn test_vault_graph_virtual_tag_hubs_clusters_and_orphans() {
        let vault = make_temp_vault("virtual_tag_hub");
        let v_str = vault.to_str().unwrap();

        // Three notes sharing tag `Books` (NO note named Books.md exists)
        cmd_write(v_str, "Library/Dune.md", "---\ntags: [Books]\n---\n# Dune\nSci-fi classic.\n").unwrap();
        cmd_write(v_str, "Library/Foundation.md", "---\ntags: [Books]\n---\n# Foundation\nAsimov.\n").unwrap();
        cmd_write(v_str, "Library/Hyperion.md", "---\ntags: [Books]\n---\n# Hyperion\nDan Simmons.\n").unwrap();
        // True orphan note with no tags and no links
        cmd_write(v_str, "Scratch/Lonely.md", "# Lonely\nStandalone thought.\n").unwrap();

        let scan = cmd_scan(v_str).unwrap();
        let nodes = scan["graph"]["nodes"].as_array().unwrap();
        let edges = scan["graph"]["edges"].as_array().unwrap();

        let books_hub = nodes
            .iter()
            .find(|n| n["isTagNode"] == true && n["tagName"] == "Books")
            .expect("Expected virtual #Books tag hub node");
        assert_eq!(books_hub["isVirtual"], true);
        assert_eq!(books_hub["isHub"], true);
        assert_eq!(books_hub["isOrphan"], false);
        assert_eq!(books_hub["degree"], 3);
        assert!(books_hub["z"].as_f64().is_some());

        let lonely = nodes
            .iter()
            .find(|n| n["relPath"] == "Scratch/Lonely.md")
            .expect("Expected Lonely orphan node");
        assert_eq!(lonely["isOrphan"], true);
        assert_eq!(lonely["clusterId"], -1);
        assert_eq!(lonely["degree"], 0);

        // Every book note connects directly to the virtual #Books hub, NOT to another random book
        assert_eq!(edges.len(), 3);
        assert!(edges.iter().all(|e| e["source"] == "tag:books"));

        let _ = fs::remove_dir_all(&vault);
    }

    #[test]
    fn test_calendar_obsidian_plugin_dual_indicators_and_words_per_dot() {
        let vault = make_temp_vault("cal_dual_dots");
        let v_str = vault.to_str().unwrap();
        let cal_cfg = vault.join(".obsidian/plugins/calendar");
        fs::create_dir_all(&cal_cfg).unwrap();
        fs::write(cal_cfg.join("data.json"), r#"{"wordsPerDot": 10, "showWeeklyNote": true}"#).unwrap();

        // Day with ~35 words and 1 open task -> solidDots=3, hasOpenTasks=true
        let body_35: String = (0..35).map(|i| format!("word{}", i)).collect::<Vec<_>>().join(" ");
        cmd_write(
            v_str,
            "00_Capture/01_Journal/2026/November/05-11-2026-Thursday.md",
            &format!("---\nmood: Good\n---\n{}\n- [ ] Finish calendar parity\n", body_35),
        )
        .unwrap();
        // Day with 3 words and only completed tasks -> solidDots=1 (min 1 when note exists), hasOpenTasks=false
        cmd_write(
            v_str,
            "00_Capture/01_Journal/2026/November/06-11-2026-Friday.md",
            "Short note\n- [x] All done\n",
        )
        .unwrap();

        let cal = cmd_calendar_with_today(v_str, 2026, 11, Some("2026-11-05")).unwrap();
        assert_eq!(cal["wordsPerDot"], 10);
        assert_eq!(cal["showWeeklyNote"], true);
        let cells = cal["cells"].as_array().unwrap();
        let d5 = cells.iter().find(|c| c["dateStr"] == "2026-11-05").unwrap();
        assert_eq!(d5["isToday"], true);
        assert_eq!(d5["hasJournal"], true);
        assert_eq!(d5["solidDots"], 3);
        assert_eq!(d5["hasOpenTasks"], true);
        assert_eq!(d5["openTasks"], 1);
        assert!(d5["weekNumber"].as_u64().unwrap() >= 1);

        let d6 = cells.iter().find(|c| c["dateStr"] == "2026-11-06").unwrap();
        assert_eq!(d6["isToday"], false);
        assert_eq!(d6["solidDots"], 1);
        assert_eq!(d6["hasOpenTasks"], false);

        let d7 = cells.iter().find(|c| c["dateStr"] == "2026-11-07").unwrap();
        assert_eq!(d7["hasJournal"], false);
        assert_eq!(d7["solidDots"], 0);
        assert_eq!(d7["hasOpenTasks"], false);

        let _ = fs::remove_dir_all(&vault);
    }

    #[test]
    fn test_tag_wrangler_rename_merge_remove_and_page_preserve_unrelated_bytes() {
        let vault = make_temp_vault("tag_wrangler");
        let v_str = vault.to_str().unwrap();

        let note_a = "---\r\ntitle: Note A\r\ntags:\r\n  - Books\r\n  - Books/SciFi\r\n  - Reading\r\n---\r\nBody #Books and #Books/SciFi and `#Books` in code.\r\n```\r\n#Books inside fence stays untouched\r\n```\r\nLink https://example.com/#Books stays untouched.\r\n";
        fs::write(vault.join("NoteA.md"), note_a).unwrap();
        let note_b = "---\ntags: [Books, Reading]\n---\nInline #Books mention.\n";
        fs::write(vault.join("NoteB.md"), note_b).unwrap();

        // Rename Books -> Literature (with subtags)
        let ren = cmd_tag_rename(v_str, "Books", "Literature", true).unwrap();
        assert_eq!(ren["ok"], true);
        assert_eq!(ren["filesUpdated"], 2);

        let after_a = fs::read_to_string(vault.join("NoteA.md")).unwrap();
        assert!(after_a.contains("\r\n"));
        assert!(after_a.contains("  - Literature\r\n"));
        assert!(after_a.contains("  - Literature/SciFi\r\n"));
        assert!(after_a.contains("Body #Literature and #Literature/SciFi and `#Books` in code."));
        assert!(after_a.contains("#Books inside fence stays untouched"));
        assert!(after_a.contains("https://example.com/#Books stays untouched."));

        // Merge Literature -> Reading (must deduplicate frontmatter tags in BOTH NoteA block list and NoteB inline array!)
        let merged = cmd_tag_rename(v_str, "Literature", "Reading", false).unwrap();
        assert_eq!(merged["ok"], true);
        let after_a_merged = fs::read_to_string(vault.join("NoteA.md")).unwrap();
        assert_eq!(
            after_a_merged.matches("  - Reading\r\n").count(),
            1,
            "Block YAML list merge must deduplicate when merged tag precedes existing target tag:\n{}",
            after_a_merged
        );
        let after_b = fs::read_to_string(vault.join("NoteB.md")).unwrap();
        assert!(after_b.contains("tags: [Reading]\n"));
        assert!(after_b.contains("Inline #Reading mention."));

        // Remove tag from single note
        let rem = cmd_tag_remove(v_str, "Reading", Some("NoteB.md"), false).unwrap();
        assert_eq!(rem["filesUpdated"], 1);
        let after_rem = fs::read_to_string(vault.join("NoteB.md")).unwrap();
        assert!(!after_rem.contains("#Reading"));
        assert!(after_rem.contains("tags: []\n"));

        // Create Tag Page MOC
        let page = cmd_tag_page(v_str, "Literature/SciFi", None).unwrap();
        assert_eq!(page["created"], true);
        assert_eq!(page["relPath"], "Tags/Literature - SciFi.md");
        assert!(vault.join("Tags/Literature - SciFi.md").exists());
        let page2 = cmd_tag_page(v_str, "Literature/SciFi", None).unwrap();
        assert_eq!(page2["created"], false);

        let _ = fs::remove_dir_all(&vault);
    }

    #[test]
    fn test_tag_wrangler_unicode_zero_indent_yaml_and_numeric_prefix_tags() {
        let vault = make_temp_vault("tag_wrangler_edge");
        let v_str = vault.to_str().unwrap();

        // Zero-indent YAML tag list + Vietnamese Unicode tag + numeric-prefix tag + pure number
        let note = "---\ntags:\n- Sách/Tâm-Lý\n- 2026/goals\n---\nĐọc #sách/Tâm-Lý và #2026/goals nhưng giữ nguyên #123.\n";
        fs::write(vault.join("Edge.md"), note).unwrap();

        let r1 = cmd_tag_rename(v_str, "Sách", "Thư-Viện", true).unwrap();
        assert_eq!(r1["filesUpdated"], 1);
        let r2 = cmd_tag_rename(v_str, "2026", "Year2026", true).unwrap();
        assert_eq!(r2["filesUpdated"], 1);

        let after = fs::read_to_string(vault.join("Edge.md")).unwrap();
        assert!(after.contains("- Thư-Viện/Tâm-Lý\n"), "Zero-indent YAML + Unicode subtag failed:\n{}", after);
        assert!(after.contains("- Year2026/goals\n"), "Zero-indent numeric tag failed:\n{}", after);
        assert!(after.contains("#Thư-Viện/Tâm-Lý"), "Inline Unicode case-insensitive match failed:\n{}", after);
        assert!(after.contains("#Year2026/goals"), "Inline numeric-prefix tag failed:\n{}", after);
        assert!(after.contains("#123"), "Pure numeric token #123 must remain untouched:\n{}", after);

        // Calendar weekStart=sunday check
        let cal_cfg = vault.join(".obsidian/plugins/calendar");
        fs::create_dir_all(&cal_cfg).unwrap();
        fs::write(cal_cfg.join("data.json"), r#"{"weekStart": "sunday", "wordsPerDot": 250}"#).unwrap();
        // Nov 1, 2026 is a Sunday -> with weekStart=sunday, cell[0] must be 2026-11-01!
        let cal = cmd_calendar_with_today(v_str, 2026, 11, Some("2026-11-01")).unwrap();
        assert_eq!(cal["weekStart"], "sunday");
        let cells = cal["cells"].as_array().unwrap();
        assert_eq!(cells[0]["dateStr"], "2026-11-01");

        let _ = fs::remove_dir_all(&vault);
    }
}

