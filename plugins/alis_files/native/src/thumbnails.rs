use crate::model::FileKind;
use gtk4::gdk;
use gtk4::gdk_pixbuf::Pixbuf;
use gtk4::prelude::Cast;
use std::collections::{HashMap, VecDeque};
use std::fs;
use std::hash::Hash;
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex, OnceLock, mpsc};
use std::time::{SystemTime, UNIX_EPOCH};

pub const TEXTURE_LRU_CAPACITY: usize = 512;

const FNV1A_64_OFFSET_BASIS: u64 = 0xcbf2_9ce4_8422_2325;
const FNV1A_64_PRIME: u64 = 0x0000_0100_0000_01b3;

struct Fnv1a64 {
    state: u64,
}

impl Fnv1a64 {
    fn new() -> Self {
        Self {
            state: FNV1A_64_OFFSET_BASIS,
        }
    }

    fn update(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.state ^= u64::from(b);
            self.state = self.state.wrapping_mul(FNV1A_64_PRIME);
        }
    }

    fn update_u8(&mut self, v: u8) {
        self.update(&[v]);
    }

    fn update_u32(&mut self, v: u32) {
        self.update(&v.to_le_bytes());
    }

    fn update_i32(&mut self, v: i32) {
        self.update(&v.to_le_bytes());
    }

    fn update_u64(&mut self, v: u64) {
        self.update(&v.to_le_bytes());
    }

    fn finish(self) -> u64 {
        self.state
    }
}

/// Deterministic 64-bit FNV-1a hash for thumbnail cache keys.
/// Stable across Rust compiler upgrades and platforms.
pub fn stable_thumb_hash(
    path_bytes: &[u8],
    max_dim: i32,
    page: Option<u32>,
    file_len: Option<u64>,
    mtime: Option<SystemTime>,
) -> u64 {
    let mut h = Fnv1a64::new();
    h.update_u64(path_bytes.len() as u64);
    h.update(path_bytes);
    h.update_i32(max_dim);
    match page {
        Some(p) => {
            h.update_u8(1);
            h.update_u32(p);
        }
        None => h.update_u8(0),
    }
    match file_len {
        Some(len) => {
            h.update_u8(1);
            h.update_u64(len);
        }
        None => h.update_u8(0),
    }
    match mtime {
        Some(ts) => match ts.duration_since(UNIX_EPOCH) {
            Ok(d) => {
                h.update_u8(1);
                h.update_u64(d.as_secs());
                h.update_u32(d.subsec_nanos());
            }
            Err(err) => {
                let d = err.duration();
                h.update_u8(2);
                h.update_u64(d.as_secs());
                h.update_u32(d.subsec_nanos());
            }
        },
        None => h.update_u8(0),
    }
    h.finish()
}

pub fn thumb_cache_dir() -> PathBuf {
    let dir = crate::config::cache_dir().join("alis/files-thumbnails");
    let _ = fs::create_dir_all(&dir);
    dir
}

fn cache_key_path_in(dir: &Path, path: &Path, size: i32) -> PathBuf {
    let meta = fs::metadata(path).ok();
    let len = meta.as_ref().map(|m| m.len());
    let mtime = meta.as_ref().and_then(|m| m.modified().ok());
    let hash = stable_thumb_hash(path.as_os_str().as_bytes(), size, None, len, mtime);
    dir.join(format!("{hash:016x}.png"))
}

fn cache_key_path(path: &Path, size: i32) -> PathBuf {
    cache_key_path_in(&thumb_cache_dir(), path, size)
}

/// Generate (or load from disk cache) a scaled thumbnail file path for an image, PDF, or video.
/// Safe to invoke from a background worker thread; returns the PNG path to load as a `gdk::Texture` on the UI thread.
pub fn ensure_thumbnail_file(path: &Path, kind: FileKind, max_dim: i32) -> Option<PathBuf> {
    match kind {
        FileKind::Image => ensure_image_thumb(path, max_dim),
        FileKind::Pdf => ensure_pdf_thumb(path, max_dim),
        FileKind::Video => ensure_video_thumb(path, max_dim),
        _ => None,
    }
}

static TMP_SEQ: AtomicU64 = AtomicU64::new(1);

fn unique_tmp_path(cached: &Path, ext: &str) -> PathBuf {
    let seq = TMP_SEQ.fetch_add(1, Ordering::Relaxed);
    let pid = std::process::id();
    let stem = cached
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| "thumb".into());
    cached
        .parent()
        .unwrap_or_else(|| Path::new("/tmp"))
        .join(format!(".{stem}-{pid}-{seq}.{ext}"))
}

fn is_non_empty_file(path: &Path) -> bool {
    fs::metadata(path)
        .map(|m| m.is_file() && m.len() > 0)
        .unwrap_or(false)
}

fn commit_tmp_file(tmp: &Path, dest: &Path) -> Option<PathBuf> {
    if !is_non_empty_file(tmp) {
        let _ = fs::remove_file(tmp);
        return None;
    }
    if fs::rename(tmp, dest).is_ok() {
        Some(dest.to_path_buf())
    } else {
        let _ = fs::remove_file(tmp);
        if is_non_empty_file(dest) {
            Some(dest.to_path_buf())
        } else {
            None
        }
    }
}

fn ensure_image_thumb(path: &Path, max_dim: i32) -> Option<PathBuf> {
    let cached = cache_key_path(path, max_dim);
    if is_non_empty_file(&cached) {
        return Some(cached);
    }
    let raw_pixbuf = Pixbuf::from_file_at_scale(path, max_dim, max_dim, true).ok()?;
    let pixbuf = raw_pixbuf.apply_embedded_orientation().unwrap_or(raw_pixbuf);
    let tmp = unique_tmp_path(&cached, "png");
    if pixbuf.savev(&tmp, "png", &[]).is_ok() {
        return commit_tmp_file(&tmp, &cached);
    }
    let _ = fs::remove_file(&tmp);
    None
}

/// Decoded RGBA image payload safe to build on a background worker thread and turn into a
/// `gdk::MemoryTexture` on the GTK main thread without blocking or decoding huge 100MP images.
pub struct ScaledImageBuffer {
    pub bytes: Vec<u8>,
    pub width: i32,
    pub height: i32,
    pub rowstride: usize,
    pub has_alpha: bool,
}

pub fn decode_scaled_image_buffer(path: &Path, max_dim: i32) -> Option<ScaledImageBuffer> {
    let raw_pixbuf = Pixbuf::from_file_at_scale(path, max_dim, max_dim, true).ok()?;
    let pixbuf = raw_pixbuf.apply_embedded_orientation().unwrap_or(raw_pixbuf);
    let width = pixbuf.width();
    let height = pixbuf.height();
    let rowstride = pixbuf.rowstride().max(0) as usize;
    let has_alpha = pixbuf.has_alpha();
    // Safety copy of pixels as Vec<u8> for cross-thread transport
    let bytes = pixbuf.read_pixel_bytes().to_vec();
    Some(ScaledImageBuffer {
        bytes,
        width,
        height,
        rowstride,
        has_alpha,
    })
}

pub fn texture_from_scaled_buffer(buf: ScaledImageBuffer) -> gdk::Texture {
    let format = if buf.has_alpha {
        gdk::MemoryFormat::R8g8b8a8
    } else {
        gdk::MemoryFormat::R8g8b8
    };
    let gbytes = gtk4::glib::Bytes::from_owned(buf.bytes);
    gdk::MemoryTexture::new(buf.width, buf.height, format, &gbytes, buf.rowstride).upcast()
}

fn ensure_pdf_thumb_in(cache_dir: &Path, path: &Path, max_dim: i32) -> Option<PathBuf> {
    let cached = cache_key_path_in(cache_dir, path, max_dim);
    if is_non_empty_file(&cached) {
        return Some(cached);
    }
    let tmp_png = unique_tmp_path(&cached, "png");
    let tmp_prefix = tmp_png.with_extension("");
    let out = Command::new("pdftoppm")
        .stdin(Stdio::null())
        .args(["-png", "-f", "1", "-l", "1", "-singlefile", "-scale-to"])
        .arg(max_dim.to_string())
        .arg(path)
        .arg(&tmp_prefix)
        .output();
    match out {
        Ok(o) if o.status.success() => commit_tmp_file(&tmp_png, &cached),
        _ => {
            let _ = fs::remove_file(&tmp_png);
            None
        }
    }
}

fn ensure_pdf_thumb(path: &Path, max_dim: i32) -> Option<PathBuf> {
    ensure_pdf_thumb_in(&thumb_cache_dir(), path, max_dim)
}

fn ensure_video_thumb(path: &Path, max_dim: i32) -> Option<PathBuf> {
    let cached = cache_key_path(path, max_dim);
    if is_non_empty_file(&cached) {
        return Some(cached);
    }
    let tmp = unique_tmp_path(&cached, "png");
    let vf = format!("scale={max_dim}:{max_dim}:force_original_aspect_ratio=decrease");
    let out = Command::new("ffmpeg")
        .stdin(Stdio::null())
        .args(["-y", "-loglevel", "error", "-ss", "00:00:01.000", "-i"])
        .arg(path)
        .args(["-vframes", "1", "-vf", &vf])
        .arg(&tmp)
        .output();
    if let Ok(o) = out
        && o.status.success()
        && let Some(done) = commit_tmp_file(&tmp, &cached)
    {
        return Some(done);
    }
    let _ = fs::remove_file(&tmp);

    // Retry at frame 0 for very short clips
    let tmp0 = unique_tmp_path(&cached, "png");
    let out0 = Command::new("ffmpeg")
        .stdin(Stdio::null())
        .args(["-y", "-loglevel", "error", "-i"])
        .arg(path)
        .args(["-vframes", "1", "-vf", &vf])
        .arg(&tmp0)
        .output();
    match out0 {
        Ok(o) if o.status.success() => commit_tmp_file(&tmp0, &cached),
        _ => {
            let _ = fs::remove_file(&tmp0);
            None
        }
    }
}

pub fn load_texture_from_path(path: &Path) -> Option<gdk::Texture> {
    let gfile = gtk4::gio::File::for_path(path);
    gdk::Texture::from_file(&gfile).ok()
}

fn render_pdf_page_in(cache_dir: &Path, path: &Path, page: u32, max_dim: i32) -> Option<PathBuf> {
    let meta = fs::metadata(path).ok();
    let len = meta.as_ref().map(|m| m.len());
    let mtime = meta.as_ref().and_then(|m| m.modified().ok());
    let hash = stable_thumb_hash(path.as_os_str().as_bytes(), max_dim, Some(page), len, mtime);
    let expected = cache_dir.join(format!("pdf-{hash:016x}-p{page}.png"));
    if is_non_empty_file(&expected) {
        return Some(expected);
    }
    let tmp_png = unique_tmp_path(&expected, "png");
    let tmp_prefix = tmp_png.with_extension("");
    let out = Command::new("pdftoppm")
        .stdin(Stdio::null())
        .args([
            "-png",
            "-f",
            &page.to_string(),
            "-l",
            &page.to_string(),
            "-singlefile",
            "-scale-to",
            &max_dim.to_string(),
        ])
        .arg(path)
        .arg(&tmp_prefix)
        .output();
    match out {
        Ok(o) if o.status.success() => commit_tmp_file(&tmp_png, &expected),
        _ => {
            let _ = fs::remove_file(&tmp_png);
            None
        }
    }
}

pub fn render_pdf_page(path: &Path, page: u32, max_dim: i32) -> Option<PathBuf> {
    render_pdf_page_in(&thumb_cache_dir(), path, page, max_dim)
}

pub fn pdf_page_count(path: &Path) -> Option<u32> {
    let out = Command::new("pdfinfo")
        .stdin(Stdio::null())
        .arg(path)
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    for line in String::from_utf8_lossy(&out.stdout).lines() {
        if let Some(rest) = line.strip_prefix("Pages:")
            && let Ok(n) = rest.trim().parse::<u32>()
        {
            return Some(n);
        }
    }
    None
}

// ── Bounded O(1) In-Memory LRU Cache ─────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct ThumbCacheKey {
    pub path: PathBuf,
    pub max_dim: i32,
    pub size: u64,
    pub modified: Option<SystemTime>,
}

struct LruNode<K, V> {
    key: K,
    value: V,
    prev: Option<usize>,
    next: Option<usize>,
}

/// Bounded O(1) Least-Recently-Used cache (zero `unsafe`).
pub struct LruCache<K, V> {
    capacity: usize,
    map: HashMap<K, usize>,
    nodes: Vec<Option<LruNode<K, V>>>,
    free: Vec<usize>,
    head: Option<usize>,
    tail: Option<usize>,
}

impl<K: Eq + Hash + Clone, V> LruCache<K, V> {
    pub fn new(capacity: usize) -> Self {
        Self {
            capacity,
            map: HashMap::with_capacity(capacity.min(1024)),
            nodes: Vec::with_capacity(capacity.min(1024)),
            free: Vec::new(),
            head: None,
            tail: None,
        }
    }

    #[allow(dead_code)]
    pub fn len(&self) -> usize {
        self.map.len()
    }

    #[allow(dead_code)]
    pub fn is_empty(&self) -> bool {
        self.map.is_empty()
    }

    #[allow(dead_code)]
    pub fn capacity(&self) -> usize {
        self.capacity
    }

    pub fn get(&mut self, key: &K) -> Option<&V> {
        let idx = *self.map.get(key)?;
        self.move_to_front(idx);
        self.nodes[idx].as_ref().map(|n| &n.value)
    }

    pub fn insert(&mut self, key: K, value: V) {
        if self.capacity == 0 {
            return;
        }
        if let Some(&idx) = self.map.get(&key) {
            if let Some(node) = self.nodes[idx].as_mut() {
                node.value = value;
            }
            self.move_to_front(idx);
            return;
        }
        if self.map.len() >= self.capacity {
            self.evict_tail();
        }
        let idx = if let Some(slot) = self.free.pop() {
            self.nodes[slot] = Some(LruNode {
                key: key.clone(),
                value,
                prev: None,
                next: self.head,
            });
            slot
        } else {
            let slot = self.nodes.len();
            self.nodes.push(Some(LruNode {
                key: key.clone(),
                value,
                prev: None,
                next: self.head,
            }));
            slot
        };
        if let Some(old_head) = self.head
            && let Some(node) = self.nodes[old_head].as_mut()
        {
            node.prev = Some(idx);
        }
        self.head = Some(idx);
        if self.tail.is_none() {
            self.tail = Some(idx);
        }
        self.map.insert(key, idx);
    }

    #[allow(dead_code)]
    pub fn clear(&mut self) {
        self.map.clear();
        self.nodes.clear();
        self.free.clear();
        self.head = None;
        self.tail = None;
    }

    fn detach(&mut self, idx: usize) {
        let (prev, next) = match self.nodes[idx].as_ref() {
            Some(n) => (n.prev, n.next),
            None => return,
        };
        if let Some(p) = prev {
            if let Some(pn) = self.nodes[p].as_mut() {
                pn.next = next;
            }
        } else {
            self.head = next;
        }
        if let Some(n) = next {
            if let Some(nn) = self.nodes[n].as_mut() {
                nn.prev = prev;
            }
        } else {
            self.tail = prev;
        }
        if let Some(node) = self.nodes[idx].as_mut() {
            node.prev = None;
            node.next = None;
        }
    }

    fn move_to_front(&mut self, idx: usize) {
        if self.head == Some(idx) {
            return;
        }
        self.detach(idx);
        let old_head = self.head;
        if let Some(node) = self.nodes[idx].as_mut() {
            node.prev = None;
            node.next = old_head;
        }
        if let Some(oh) = old_head
            && let Some(oh_node) = self.nodes[oh].as_mut()
        {
            oh_node.prev = Some(idx);
        }
        self.head = Some(idx);
        if self.tail.is_none() {
            self.tail = Some(idx);
        }
    }

    fn evict_tail(&mut self) {
        let Some(tail_idx) = self.tail else {
            return;
        };
        self.detach(tail_idx);
        if let Some(node) = self.nodes[tail_idx].take() {
            self.map.remove(&node.key);
            self.free.push(tail_idx);
        }
    }
}

// ── Bounded Parallel On-Demand Thumbnail Worker Pool ─────────────────────────

pub struct ThumbJob {
    pub job_id: u64,
    pub key: ThumbCacheKey,
    pub kind: FileKind,
    pub cancel: Arc<AtomicBool>,
    pub tx: mpsc::Sender<ThumbResult>,
}

pub struct ThumbResult {
    pub job_id: u64,
    pub key: ThumbCacheKey,
    pub png_path: Option<PathBuf>,
}

pub struct ThumbWorkerPool {
    shared: Arc<(Mutex<VecDeque<ThumbJob>>, Condvar)>,
}

impl ThumbWorkerPool {
    pub fn global() -> &'static Self {
        static POOL: OnceLock<ThumbWorkerPool> = OnceLock::new();
        POOL.get_or_init(|| {
            let workers = std::thread::available_parallelism()
                .map(|n| n.get().clamp(2, 4))
                .unwrap_or(3);
            let shared = Arc::new((Mutex::new(VecDeque::<ThumbJob>::new()), Condvar::new()));
            for idx in 0..workers {
                let s = shared.clone();
                let _ = std::thread::Builder::new()
                    .name(format!("alis-thumb-{idx}"))
                    .spawn(move || worker_loop(s));
            }
            ThumbWorkerPool { shared }
        })
    }

    pub fn submit(&self, job: ThumbJob) {
        let (lock, cvar) = &*self.shared;
        if let Ok(mut queue) = lock.lock() {
            // Prune cancelled entries under fast scrolling so the queue stays tight.
            if queue.len() >= 64 {
                queue.retain(|j| !j.cancel.load(Ordering::Relaxed));
            }
            queue.push_back(job);
            cvar.notify_one();
        }
    }
}

fn worker_loop(shared: Arc<(Mutex<VecDeque<ThumbJob>>, Condvar)>) {
    let (lock, cvar) = &*shared;
    loop {
        let job = {
            let mut queue = match lock.lock() {
                Ok(g) => g,
                Err(poisoned) => poisoned.into_inner(),
            };
            while queue.is_empty() {
                queue = match cvar.wait(queue) {
                    Ok(g) => g,
                    Err(poisoned) => poisoned.into_inner(),
                };
            }
            // LIFO pop prioritizes the most recently bound (currently visible) items.
            queue.pop_back()
        };
        let Some(job) = job else {
            continue;
        };
        if job.cancel.load(Ordering::Relaxed) {
            continue;
        }
        let png_path = ensure_thumbnail_file(&job.key.path, job.kind, job.key.max_dim);
        if !job.cancel.load(Ordering::Relaxed) {
            let _ = job.tx.send(ThumbResult {
                job_id: job.job_id,
                key: job.key,
                png_path,
            });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn stable_thumb_hash_is_deterministic_and_sensitive() {
        // Verify FNV-1a 64-bit implementation against standard reference test vectors.
        let mut fnv = Fnv1a64::new();
        fnv.update(b"");
        assert_eq!(fnv.finish(), 0xcbf2_9ce4_8422_2325);
        let mut fnv_foobar = Fnv1a64::new();
        fnv_foobar.update(b"foobar");
        assert_eq!(fnv_foobar.finish(), 0x8594_4171_f739_67e8);

        let t1 = UNIX_EPOCH + Duration::new(1_700_000_000, 123_456_789);
        let t2 = UNIX_EPOCH + Duration::new(1_700_000_001, 123_456_789);

        let h1 = stable_thumb_hash(b"/home/user/wall.png", 168, None, Some(4096), Some(t1));
        let h1_repeat = stable_thumb_hash(b"/home/user/wall.png", 168, None, Some(4096), Some(t1));
        assert_eq!(h1, h1_repeat);
        // Pin exact FNV-1a value for empty inputs (15 zero bytes) independently verified against FNV-1a 64-bit.
        let h_empty = stable_thumb_hash(b"", 0, None, None, None);
        assert_eq!(h_empty, 0x2eb0_9ce4_c432_0587);

        // Sensitivity to every input component
        assert_ne!(
            h1,
            stable_thumb_hash(b"/home/user/other.png", 168, None, Some(4096), Some(t1))
        );
        assert_ne!(
            h1,
            stable_thumb_hash(b"/home/user/wall.png", 256, None, Some(4096), Some(t1))
        );
        assert_ne!(
            h1,
            stable_thumb_hash(b"/home/user/wall.png", 168, Some(1), Some(4096), Some(t1))
        );
        assert_ne!(
            h1,
            stable_thumb_hash(b"/home/user/wall.png", 168, None, Some(4097), Some(t1))
        );
        assert_ne!(
            h1,
            stable_thumb_hash(b"/home/user/wall.png", 168, None, Some(4096), Some(t2))
        );
    }

    #[test]
    fn lru_cache_eviction_and_promotion_order() {
        let mut zero = LruCache::<&str, i32>::new(0);
        zero.insert("a", 1);
        assert!(zero.is_empty());
        assert_eq!(zero.get(&"a"), None);

        let mut single = LruCache::<&str, i32>::new(1);
        single.insert("a", 1);
        assert_eq!(single.get(&"a"), Some(&1));
        single.insert("b", 2);
        assert_eq!(single.len(), 1);
        assert_eq!(single.get(&"a"), None);
        assert_eq!(single.get(&"b"), Some(&2));

        let mut lru = LruCache::<String, usize>::new(3);
        lru.insert("a".into(), 1);
        lru.insert("b".into(), 2);
        lru.insert("c".into(), 3);
        assert_eq!(lru.len(), 3);

        // Touching "a" promotes it to MRU so "b" becomes LRU.
        assert_eq!(lru.get(&"a".into()), Some(&1));
        lru.insert("d".into(), 4);
        assert_eq!(lru.len(), 3);
        assert_eq!(lru.get(&"b".into()), None);
        assert_eq!(lru.get(&"a".into()), Some(&1));
        assert_eq!(lru.get(&"c".into()), Some(&3));
        assert_eq!(lru.get(&"d".into()), Some(&4));

        // Updating an existing key promotes it without growing len.
        lru.insert("a".into(), 10);
        assert_eq!(lru.len(), 3);
        lru.insert("e".into(), 5);
        assert_eq!(lru.get(&"c".into()), None);
        assert_eq!(lru.get(&"a".into()), Some(&10));
        assert_eq!(lru.get(&"d".into()), Some(&4));
        assert_eq!(lru.get(&"e".into()), Some(&5));

        lru.clear();
        assert!(lru.is_empty());
        assert_eq!(lru.get(&"a".into()), None);
    }

    #[test]
    fn pdf_thumb_atomic_writes_leave_no_temp_or_corrupt_files_on_error() {
        let base = std::env::temp_dir().join(format!("alis-files-pdf-atomic-{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        let cache = base.join("cache");
        fs::create_dir_all(&cache).unwrap();
        let bad_pdf = base.join("corrupt.pdf");
        fs::write(&bad_pdf, b"not a valid pdf file").unwrap();

        assert!(ensure_pdf_thumb_in(&cache, &bad_pdf, 128).is_none());
        assert!(render_pdf_page_in(&cache, &bad_pdf, 1, 256).is_none());

        // Zero-byte temp files must never be committed into the cache.
        let empty_tmp = cache.join(".empty-tmp.png");
        let empty_dest = cache.join("should-not-exist.png");
        fs::write(&empty_tmp, b"").unwrap();
        assert!(commit_tmp_file(&empty_tmp, &empty_dest).is_none());
        assert!(!empty_tmp.exists());
        assert!(!empty_dest.exists());

        let remaining: Vec<_> = fs::read_dir(&cache).unwrap().flatten().collect();
        assert!(
            remaining.is_empty(),
            "cache dir should have no partial/temp files after failed PDF render, found: {remaining:?}"
        );
        let _ = fs::remove_dir_all(&base);
    }

    #[test]
    fn pdf_thumb_and_page_render_valid_pdf_atomically_and_hit_cache() {
        if Command::new("pdftoppm").arg("-v").output().is_err() {
            return;
        }
        let base =
            std::env::temp_dir().join(format!("alis-files-pdf-valid-{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        let cache = base.join("cache");
        fs::create_dir_all(&cache).unwrap();

        // Build a minimal standards-compliant 2-page PDF with valid xref offsets.
        let mut pdf = Vec::<u8>::new();
        pdf.extend_from_slice(b"%PDF-1.4\n");
        let mut offsets = Vec::new();
        let objs: &[&[u8]] = &[
            b"1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n",
            b"2 0 obj\n<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>\nendobj\n",
            b"3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] >>\nendobj\n",
            b"4 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] >>\nendobj\n",
        ];
        for o in objs {
            offsets.push(pdf.len());
            pdf.extend_from_slice(o);
        }
        let xref_pos = pdf.len();
        pdf.extend_from_slice(format!("xref\n0 {}\n0000000000 65535 f \n", objs.len() + 1).as_bytes());
        for off in offsets {
            pdf.extend_from_slice(format!("{off:010} 00000 n \n").as_bytes());
        }
        pdf.extend_from_slice(
            format!(
                "trailer\n<< /Size {} /Root 1 0 R >>\nstartxref\n{xref_pos}\n%%EOF\n",
                objs.len() + 1
            )
            .as_bytes(),
        );
        let pdf_path = base.join("sample.pdf");
        fs::write(&pdf_path, &pdf).unwrap();

        let thumb1 = ensure_pdf_thumb_in(&cache, &pdf_path, 96).expect("valid pdf thumb");
        assert!(is_non_empty_file(&thumb1));
        assert!(fs::read(&thumb1).unwrap().starts_with(b"\x89PNG\r\n\x1a\n"));
        // Repeat call hits the exact cached file.
        let thumb2 = ensure_pdf_thumb_in(&cache, &pdf_path, 96).expect("cached pdf thumb");
        assert_eq!(thumb1, thumb2);

        let page2 = render_pdf_page_in(&cache, &pdf_path, 2, 128).expect("valid page 2 render");
        assert!(is_non_empty_file(&page2));
        assert!(fs::read(&page2).unwrap().starts_with(b"\x89PNG\r\n\x1a\n"));

        // Verify zero hidden temp files remain in cache dir.
        for entry in fs::read_dir(&cache).unwrap().flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            assert!(!name.starts_with('.'), "leftover temp file in cache: {name}");
        }
        let _ = fs::remove_dir_all(&base);
    }
}
