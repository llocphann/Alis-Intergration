mod alis_actions;
mod archive;
mod config;
mod dbus;
mod disk_usage;
mod fs_ops;
mod git;
mod model;
mod mounts;
mod overlay_daemon;
mod properties;
mod search;
mod theme;
mod thumbnails;
mod ui;

use crate::config::{AppConfig, home_dir};
use crate::dbus::{FileManagerRequest, register_file_manager1, uri_to_path};
use crate::theme::LiveThemeHandle;
use crate::ui::SharedState;
use crate::ui::window::AlisFilesWindow;
use gtk4::gio;
use gtk4::glib;
use gtk4::prelude::*;
use std::cell::RefCell;
use std::path::PathBuf;
use std::rc::Rc;

pub const APP_ID: &str = "org.alis.Files";

#[derive(Debug, Default, PartialEq, Eq)]
struct ParsedArgs {
    help: bool,
    version: bool,
    overlay_daemon: bool,
    new_window: bool,
    dbus_service: bool,
    select_path: Option<PathBuf>,
    properties_path: Option<PathBuf>,
    paths: Vec<PathBuf>,
}

fn parse_cli_args(args: &[String], cwd: Option<&std::path::Path>) -> ParsedArgs {
    let mut parsed = ParsedArgs::default();
    let mut i = 1usize; // skip argv[0]
    while i < args.len() {
        match args[i].as_str() {
            "--help" | "-h" => parsed.help = true,
            "--version" | "-V" => parsed.version = true,
            "--overlay-daemon" => parsed.overlay_daemon = true,
            "--new" | "--new-window" | "-n" => parsed.new_window = true,
            "--dbus-service" | "--gapplication-service" => parsed.dbus_service = true,
            "--select" => {
                if let Some(next) = args.get(i + 1) {
                    parsed.select_path = resolve_arg_path(next, cwd);
                    i += 1;
                }
            }
            "--properties" => {
                if let Some(next) = args.get(i + 1) {
                    parsed.properties_path = resolve_arg_path(next, cwd);
                    i += 1;
                }
            }
            "--" => {
                for rest in &args[i + 1..] {
                    if let Some(p) = resolve_arg_path(rest, cwd) {
                        parsed.paths.push(p);
                    }
                }
                break;
            }
            other if !other.starts_with('-') => {
                if let Some(p) = resolve_arg_path(other, cwd) {
                    parsed.paths.push(p);
                }
            }
            _ => {}
        }
        i += 1;
    }
    parsed
}

fn resolve_arg_path(raw: &str, cwd: Option<&std::path::Path>) -> Option<PathBuf> {
    if raw.starts_with("file://") {
        return uri_to_path(raw);
    }
    if raw.is_empty() {
        return None;
    }
    let pb = if let Some(rest) = raw.strip_prefix("~/") {
        home_dir().join(rest)
    } else if raw == "~" {
        home_dir()
    } else {
        let p = PathBuf::from(raw);
        if p.is_absolute() {
            p
        } else {
            let base = cwd
                .map(PathBuf::from)
                .or_else(|| std::env::current_dir().ok())
                .unwrap_or_else(home_dir);
            let joined = base.join(p);
            joined.canonicalize().unwrap_or(joined)
        }
    };
    Some(pb)
}

fn print_usage() {
    println!(
        "\
Alis Files ({}) — Native GTK4 & Abyss Overlay file manager for Alis

Usage: alis-files [OPTIONS] [PATH...]

Options:
  -n, --new, --new-window   Open a new standalone window
      --select PATH         Reveal and select PATH inside its folder
      --properties PATH     Open Properties dialog for PATH
      --dbus-service        Run headless org.freedesktop.FileManager1 service
      --overlay-daemon      Run stdio JSON-RPC bridge for Alis Abyss Overlay
  -V, --version             Print version and exit
  -h, --help                Print help and exit",
        env!("CARGO_PKG_VERSION")
    );
}

fn nearest_existing_dir(path: &std::path::Path) -> PathBuf {
    path.ancestors()
        .find(|p| p.is_dir())
        .map(PathBuf::from)
        .unwrap_or_else(home_dir)
}

fn main() -> glib::ExitCode {
    let early_args: Vec<String> = std::env::args().collect();
    let early_parsed = parse_cli_args(&early_args, None);
    if early_parsed.help {
        print_usage();
        return glib::ExitCode::SUCCESS;
    }
    if early_parsed.version {
        println!("alis-files {}", env!("CARGO_PKG_VERSION"));
        return glib::ExitCode::SUCCESS;
    }
    if early_parsed.overlay_daemon {
        overlay_daemon::run_stdio_daemon();
        return glib::ExitCode::SUCCESS;
    }

    let app = gtk4::Application::builder()
        .application_id(APP_ID)
        .flags(gio::ApplicationFlags::HANDLES_COMMAND_LINE)
        .build();

    let state = SharedState::new(AppConfig::load());
    let windows: Rc<RefCell<Vec<AlisFilesWindow>>> = Rc::new(RefCell::new(Vec::new()));
    let theme_holder: Rc<RefCell<Option<LiveThemeHandle>>> = Rc::new(RefCell::new(None));
    let dbus_holder: Rc<RefCell<Option<dbus::FileManager1Registration>>> =
        Rc::new(RefCell::new(None));

    let ensure_window = {
        let state = state.clone();
        let windows = windows.clone();
        Rc::new(move |app: &gtk4::Application, start_dir: PathBuf, force_new: bool, restore_session: bool| -> AlisFilesWindow {
            // Prune closed windows
            windows.borrow_mut().retain(|w| w.window.is_visible() || w.window.application().is_some());
            if !force_new
                && let Some(existing) = windows.borrow().last().cloned()
            {
                return existing;
            }
            if windows.borrow().is_empty() {
                state.borrow_mut().config = AppConfig::load();
            }
            let win = AlisFilesWindow::new(app, start_dir, state.clone(), restore_session);
            windows.borrow_mut().push(win.clone());
            let windows_rm = windows.clone();
            let win_ptr = win.window.clone();
            win.window.connect_destroy(move |_| {
                windows_rm.borrow_mut().retain(|item| item.window != win_ptr);
            });
            win
        })
    };

    {
        let theme_h = theme_holder.clone();
        let dbus_h = dbus_holder.clone();
        let ensure_w = ensure_window.clone();
        app.connect_startup(move |app| {
            *theme_h.borrow_mut() = Some(theme::install_live_theme());
            let app_weak = app.downgrade();
            let ensure_dbus = ensure_w.clone();
            *dbus_h.borrow_mut() = register_file_manager1(move |req| {
                let Some(app) = app_weak.upgrade() else {
                    return;
                };
                match req {
                    FileManagerRequest::ShowFolders(paths) => {
                        let mut iter = paths.into_iter();
                        let first = iter.next().unwrap_or_else(home_dir);
                        let dir = if first.is_dir() {
                            first
                        } else {
                            first.parent().map(PathBuf::from).unwrap_or_else(home_dir)
                        };
                        let win = ensure_dbus(&app, dir.clone(), false, false);
                        win.open_folder(dir);
                        for extra in iter {
                            if extra.is_dir() {
                                win.active_pane().open_new_tab(extra);
                            }
                        }
                    }
                    FileManagerRequest::ShowItems(paths) => {
                        let first = paths.into_iter().next().unwrap_or_else(home_dir);
                        let start = first
                            .parent()
                            .map(PathBuf::from)
                            .unwrap_or_else(home_dir);
                        let win = ensure_dbus(&app, start, false, false);
                        win.show_item(first);
                    }
                    FileManagerRequest::ShowItemProperties(paths) => {
                        let first = paths.into_iter().next().unwrap_or_else(home_dir);
                        let start = first
                            .parent()
                            .map(PathBuf::from)
                            .unwrap_or_else(home_dir);
                        let win = ensure_dbus(&app, start, false, false);
                        win.show_item_properties(first);
                    }
                }
            });
        });
    }

    {
        let ensure_w = ensure_window.clone();
        app.connect_command_line(move |app, cmdline| {
            let raw_args: Vec<String> = cmdline
                .arguments()
                .into_iter()
                .map(|a| a.to_string_lossy().to_string())
                .collect();
            let remote_cwd = cmdline.cwd();
            let parsed = parse_cli_args(&raw_args, remote_cwd.as_deref());

            if parsed.dbus_service
                && parsed.paths.is_empty()
                && parsed.select_path.is_none()
                && parsed.properties_path.is_none()
            {
                // Hold the application alive as a D-Bus activatable service without opening a window yet.
                let _hold = app.hold();
                std::mem::forget(_hold);
                return glib::ExitCode::SUCCESS;
            }

            if let Some(prop_path) = parsed.properties_path {
                let dir = prop_path
                    .parent()
                    .map(PathBuf::from)
                    .unwrap_or_else(home_dir);
                let win = ensure_w(app, dir, parsed.new_window, false);
                win.show_item_properties(prop_path);
                return glib::ExitCode::SUCCESS;
            }

            if let Some(sel_path) = parsed.select_path {
                let dir = sel_path
                    .parent()
                    .map(PathBuf::from)
                    .unwrap_or_else(home_dir);
                let win = ensure_w(app, dir, parsed.new_window, false);
                win.show_item(sel_path);
                return glib::ExitCode::SUCCESS;
            }

            if parsed.paths.is_empty() {
                let win = ensure_w(app, home_dir(), parsed.new_window, true);
                win.window.present();
            } else {
                let first = parsed.paths[0].clone();
                let start = if first.is_dir() {
                    first.clone()
                } else if first.exists() {
                    first.parent().map(PathBuf::from).unwrap_or_else(home_dir)
                } else {
                    nearest_existing_dir(&first)
                };
                let win = ensure_w(app, start.clone(), parsed.new_window, false);
                if first.is_dir() {
                    win.open_folder(first);
                } else if first.exists() || first.symlink_metadata().is_ok() {
                    win.show_item(first);
                } else {
                    win.open_folder(start);
                }
                for extra in parsed.paths.into_iter().skip(1) {
                    if extra.is_dir() {
                        win.active_pane().open_new_tab(extra);
                    }
                }
            }
            glib::ExitCode::SUCCESS
        });
    }

    app.run()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cli_parser_handles_new_select_properties_and_uris() {
        let args = vec![
            "alis-files".into(),
            "--new".into(),
            "file:///tmp/my%20dir".into(),
        ];
        let p = parse_cli_args(&args, None);
        assert!(p.new_window);
        assert_eq!(p.paths, vec![PathBuf::from("/tmp/my dir")]);

        let args2 = vec![
            "alis-files".into(),
            "--select".into(),
            "/tmp/hello.txt".into(),
        ];
        let p2 = parse_cli_args(&args2, None);
        assert!(!p2.new_window);
        assert_eq!(p2.select_path, Some(PathBuf::from("/tmp/hello.txt")));

        let args3 = vec!["alis-files".into(), "--dbus-service".into()];
        let p3 = parse_cli_args(&args3, None);
        assert!(p3.dbus_service);

        let args4 = vec!["alis-files".into(), "sub/dir".into()];
        let p4 = parse_cli_args(&args4, Some(std::path::Path::new("/tmp")));
        assert_eq!(p4.paths, vec![PathBuf::from("/tmp/sub/dir")]);

        let args5 = vec![
            "alis-files".into(),
            "--help".into(),
            "--version".into(),
            "--overlay-daemon".into(),
        ];
        let p5 = parse_cli_args(&args5, None);
        assert!(p5.help);
        assert!(p5.version);
        assert!(p5.overlay_daemon);

        // Preserve intentional leading/trailing spaces in paths
        assert_eq!(
            resolve_arg_path(" leading/trail ", Some(std::path::Path::new("/tmp"))),
            Some(PathBuf::from("/tmp/ leading/trail "))
        );
        assert_eq!(
            resolve_arg_path("/tmp/ space ", None),
            Some(PathBuf::from("/tmp/ space "))
        );
    }
}
