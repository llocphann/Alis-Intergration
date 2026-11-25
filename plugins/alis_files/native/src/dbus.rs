use gtk4::gio;
use gtk4::glib;
use std::path::{Path, PathBuf};

pub const FILE_MANAGER1_BUS_NAME: &str = "org.freedesktop.FileManager1";
pub const FILE_MANAGER1_OBJECT_PATH: &str = "/org/freedesktop/FileManager1";

const INTROSPECTION_XML: &str = r#"
<node>
  <interface name="org.freedesktop.FileManager1">
    <method name="ShowFolders">
      <arg type="as" name="URIs" direction="in"/>
      <arg type="s" name="StartupId" direction="in"/>
    </method>
    <method name="ShowItems">
      <arg type="as" name="URIs" direction="in"/>
      <arg type="s" name="StartupId" direction="in"/>
    </method>
    <method name="ShowItemProperties">
      <arg type="as" name="URIs" direction="in"/>
      <arg type="s" name="StartupId" direction="in"/>
    </method>
  </interface>
</node>
"#;

#[derive(Debug, Clone)]
#[allow(clippy::enum_variant_names)]
pub enum FileManagerRequest {
    ShowFolders(Vec<PathBuf>),
    ShowItems(Vec<PathBuf>),
    ShowItemProperties(Vec<PathBuf>),
}

pub struct FileManager1Registration {
    _owner_id: gio::OwnerId,
}

/// Register the `org.freedesktop.FileManager1` D-Bus service on the session bus
/// directly inside GLib's main loop so external apps' "Show in Folder" calls
/// open and highlight items inside Alis Files.
pub fn register_file_manager1<F>(handler: F) -> Option<FileManager1Registration>
where
    F: Fn(FileManagerRequest) + 'static,
{
    let node_info = gio::DBusNodeInfo::for_xml(INTROSPECTION_XML).ok()?;
    let iface_info = node_info.lookup_interface(FILE_MANAGER1_BUS_NAME)?;
    let handler_rc = std::rc::Rc::new(handler);

    let owner_id = gio::bus_own_name(
        gio::BusType::Session,
        FILE_MANAGER1_BUS_NAME,
        gio::BusNameOwnerFlags::ALLOW_REPLACEMENT | gio::BusNameOwnerFlags::REPLACE,
        move |conn, _name| {
            let h = handler_rc.clone();
            let _ = conn
                .register_object(FILE_MANAGER1_OBJECT_PATH, &iface_info)
                .method_call(move |_conn, _sender, _obj, _iface, method, params, invocation| {
                    let uris: Vec<String> = params
                        .child_value(0)
                        .get::<Vec<String>>()
                        .unwrap_or_default();
                    let paths: Vec<PathBuf> = uris.iter().filter_map(|u| uri_to_path(u)).collect();
                    match method {
                        "ShowFolders" => {
                            h(FileManagerRequest::ShowFolders(paths));
                            invocation.return_value(None);
                        }
                        "ShowItems" => {
                            h(FileManagerRequest::ShowItems(paths));
                            invocation.return_value(None);
                        }
                        "ShowItemProperties" => {
                            h(FileManagerRequest::ShowItemProperties(paths));
                            invocation.return_value(None);
                        }
                        _ => {
                            invocation.return_error(
                                gio::DBusError::UnknownMethod,
                                &format!("Unknown method {method}"),
                            );
                        }
                    }
                })
                .build();
        },
        |_conn, _name| {},
        |_conn, _name| {},
    );

    Some(FileManager1Registration {
        _owner_id: owner_id,
    })
}

pub fn uri_to_path(raw: &str) -> Option<PathBuf> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }
    if let Some(rest) = trimmed.strip_prefix("file://") {
        let stripped = if let Some(after_host) = rest.strip_prefix("localhost/") {
            format!("/{after_host}")
        } else if rest.starts_with('/') {
            rest.to_string()
        } else if let Some(idx) = rest.find('/') {
            rest[idx..].to_string()
        } else {
            return None;
        };
        return Some(PathBuf::from(percent_decode(&stripped)));
    }
    if trimmed.starts_with('/') {
        return Some(PathBuf::from(trimmed));
    }
    None
}

pub fn path_to_file_uri(path: &Path) -> String {
    glib::filename_to_uri(path, None)
        .map(|s| s.to_string())
        .unwrap_or_else(|_| format!("file://{}", path.display()))
}

pub fn paths_to_uri_list(paths: &[PathBuf]) -> String {
    paths
        .iter()
        .map(|p| path_to_file_uri(p))
        .collect::<Vec<_>>()
        .join("\r\n")
}

pub fn parse_uri_list(text: &str) -> Vec<PathBuf> {
    text.lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .filter_map(uri_to_path)
        .collect()
}

pub fn percent_decode(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%'
            && i + 2 < bytes.len()
            && let (Some(hi), Some(lo)) = (hex_val(bytes[i + 1]), hex_val(bytes[i + 2]))
        {
            out.push((hi << 4) | lo);
            i += 3;
            continue;
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn hex_val(b: u8) -> Option<u8> {
    match b {
        b'0'..=b'9' => Some(b - b'0'),
        b'a'..=b'f' => Some(b - b'a' + 10),
        b'A'..=b'F' => Some(b - b'A' + 10),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uri_decoding_and_uri_list_roundtrip() {
        assert_eq!(
            uri_to_path("file:///home/user/My%20Pictures/a%231.png"),
            Some(PathBuf::from("/home/user/My Pictures/a#1.png"))
        );
        assert_eq!(
            uri_to_path("file://localhost/tmp/test%20file.txt"),
            Some(PathBuf::from("/tmp/test file.txt"))
        );
        assert_eq!(uri_to_path("/var/tmp"), Some(PathBuf::from("/var/tmp")));
        assert_eq!(uri_to_path("https://example.com"), None);

        let parsed = parse_uri_list("# comment\r\nfile:///tmp/one.txt\r\nfile:///tmp/two%20b.txt\r\n");
        assert_eq!(
            parsed,
            vec![PathBuf::from("/tmp/one.txt"), PathBuf::from("/tmp/two b.txt")]
        );
    }
}
