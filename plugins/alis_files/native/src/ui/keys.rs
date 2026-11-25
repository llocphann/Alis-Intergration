use gtk4::gdk;
use gtk4::glib;
use gtk4::prelude::*;
use std::cell::Cell;
use std::rc::Rc;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GotoTarget {
    Home,
    Config,
    Downloads,
    Documents,
    Desktop,
    Pictures,
    Videos,
    Music,
    Trash,
    Root,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeyCommand {
    MoveDown,
    MoveUp,
    MoveDownFast,
    MoveUpFast,
    MoveHalfPageDown,
    MoveHalfPageUp,
    GoParent,
    OpenSelected,
    GoFirst,
    GoLast,
    GoBack,
    GoForward,
    Goto(GotoTarget),
    Copy,
    Cut,
    Paste,
    Undo,
    Redo,
    Trash,
    PermanentDelete,
    Rename,
    NewFolder,
    CreatePrompt,
    ToggleHidden,
    FocusFilter,
    FocusPathBar,
    OpenCommandPalette,
    NewTab,
    CloseTab,
    PrevTab,
    NextTab,
    SwitchTab(usize),
    ToggleSplitView,
    ToggleInspector,
    ToggleRail,
    SetViewGrid,
    SetViewList,
    SetViewGallery,
    QuickLook,
    ToggleSelectAndAdvance,
    Properties,
    SelectAll,
    Refresh,
    SwitchSplitPane,
    FocusPaneLeft,
    FocusPaneDown,
    FocusPaneUp,
    FocusPaneRight,
    Escape,
}

/// Stateful keyboard interpreter supporting both standard desktop shortcuts
/// and Yazi/Vim keybindings (`j/k/h/l`, `J/K`, `H/L`, `Ctrl+d/u`, `gg`, `gh/gc/gd/gD/...`,
/// `Space` select, `Alt+Space` preview, `y/x/p/d/D/a`, `[/]/t/1..9`, `u`, `Ctrl+R`, `.`, `r`, `o`, `-`).
#[derive(Default)]
pub struct VimKeyState {
    pending_chord: Cell<Option<char>>,
}

impl VimKeyState {
    pub fn pending_chord(&self) -> Option<char> {
        self.pending_chord.get()
    }

    pub fn interpret(
        &self,
        key: gdk::Key,
        mods: gdk::ModifierType,
        vim_enabled: bool,
        in_text_input: bool,
        is_grid_mode: bool,
    ) -> Option<KeyCommand> {
        if matches!(
            key,
            gdk::Key::Shift_L
                | gdk::Key::Shift_R
                | gdk::Key::Control_L
                | gdk::Key::Control_R
                | gdk::Key::Alt_L
                | gdk::Key::Alt_R
                | gdk::Key::Super_L
                | gdk::Key::Super_R
                | gdk::Key::Caps_Lock
        ) {
            return None;
        }

        let ctrl = mods.contains(gdk::ModifierType::CONTROL_MASK);
        let shift = mods.contains(gdk::ModifierType::SHIFT_MASK);
        let alt = mods.contains(gdk::ModifierType::ALT_MASK);

        if key == gdk::Key::Escape {
            self.pending_chord.set(None);
            return Some(KeyCommand::Escape);
        }

        // Global Ctrl/Alt/Function shortcuts that work even when filter/entry isn't focused
        if ctrl && !alt {
            self.pending_chord.set(None);
            match key {
                gdk::Key::k | gdk::Key::K => return Some(KeyCommand::OpenCommandPalette),
                gdk::Key::l | gdk::Key::L => return Some(KeyCommand::FocusPathBar),
                gdk::Key::f | gdk::Key::F => return Some(KeyCommand::FocusFilter),
                gdk::Key::t | gdk::Key::T => return Some(KeyCommand::NewTab),
                gdk::Key::w | gdk::Key::W => return Some(KeyCommand::CloseTab),
                gdk::Key::h | gdk::Key::H => return Some(KeyCommand::ToggleHidden),
                gdk::Key::_1 => return Some(KeyCommand::SetViewGrid),
                gdk::Key::_2 => return Some(KeyCommand::SetViewList),
                gdk::Key::_3 => return Some(KeyCommand::SetViewGallery),
                gdk::Key::i | gdk::Key::I if !in_text_input => return Some(KeyCommand::ToggleInspector),
                gdk::Key::ISO_Left_Tab => return Some(KeyCommand::PrevTab),
                gdk::Key::Tab => return Some(KeyCommand::NextTab),
                _ => {}
            }
            if !in_text_input {
                match key {
                    gdk::Key::c | gdk::Key::C => return Some(KeyCommand::Copy),
                    gdk::Key::x | gdk::Key::X => return Some(KeyCommand::Cut),
                    gdk::Key::v | gdk::Key::V => return Some(KeyCommand::Paste),
                    gdk::Key::z if !shift => return Some(KeyCommand::Undo),
                    gdk::Key::Z | gdk::Key::y | gdk::Key::Y => return Some(KeyCommand::Redo),
                    gdk::Key::d | gdk::Key::D if vim_enabled => {
                        return Some(KeyCommand::MoveHalfPageDown);
                    }
                    gdk::Key::u | gdk::Key::U if vim_enabled => {
                        return Some(KeyCommand::MoveHalfPageUp);
                    }
                    gdk::Key::r | gdk::Key::R if vim_enabled => return Some(KeyCommand::Redo),
                    gdk::Key::r | gdk::Key::R => return Some(KeyCommand::Refresh),
                    gdk::Key::N | gdk::Key::n if shift => return Some(KeyCommand::NewFolder),
                    gdk::Key::a | gdk::Key::A => return Some(KeyCommand::SelectAll),
                    _ => {}
                }
            }
            return None;
        }

        if alt && !ctrl {
            self.pending_chord.set(None);
            return match key {
                gdk::Key::Left => Some(KeyCommand::GoBack),
                gdk::Key::Right => Some(KeyCommand::GoForward),
                gdk::Key::Up => Some(KeyCommand::GoParent),
                gdk::Key::h | gdk::Key::H => Some(KeyCommand::FocusPaneLeft),
                gdk::Key::j | gdk::Key::J => Some(KeyCommand::FocusPaneDown),
                gdk::Key::k | gdk::Key::K => Some(KeyCommand::FocusPaneUp),
                gdk::Key::l | gdk::Key::L => Some(KeyCommand::FocusPaneRight),
                gdk::Key::t | gdk::Key::T => Some(KeyCommand::NewTab),
                gdk::Key::w | gdk::Key::W => Some(KeyCommand::CloseTab),
                gdk::Key::_1 | gdk::Key::KP_1 => Some(KeyCommand::SwitchTab(0)),
                gdk::Key::_2 | gdk::Key::KP_2 => Some(KeyCommand::SwitchTab(1)),
                gdk::Key::_3 | gdk::Key::KP_3 => Some(KeyCommand::SwitchTab(2)),
                gdk::Key::_4 | gdk::Key::KP_4 => Some(KeyCommand::SwitchTab(3)),
                gdk::Key::_5 | gdk::Key::KP_5 => Some(KeyCommand::SwitchTab(4)),
                gdk::Key::_6 | gdk::Key::KP_6 => Some(KeyCommand::SwitchTab(5)),
                gdk::Key::_7 | gdk::Key::KP_7 => Some(KeyCommand::SwitchTab(6)),
                gdk::Key::_8 | gdk::Key::KP_8 => Some(KeyCommand::SwitchTab(7)),
                gdk::Key::_9 | gdk::Key::KP_9 => Some(KeyCommand::SwitchTab(8)),
                gdk::Key::i | gdk::Key::I => Some(KeyCommand::ToggleInspector),
                gdk::Key::space if !in_text_input => Some(KeyCommand::QuickLook),
                gdk::Key::Return | gdk::Key::KP_Enter => Some(KeyCommand::Properties),
                _ => None,
            };
        }

        if key == gdk::Key::F3 {
            self.pending_chord.set(None);
            return Some(KeyCommand::ToggleSplitView);
        }
        if key == gdk::Key::F9 {
            self.pending_chord.set(None);
            return Some(KeyCommand::ToggleRail);
        }
        if key == gdk::Key::F5 {
            self.pending_chord.set(None);
            return Some(KeyCommand::Refresh);
        }

        if in_text_input {
            return None;
        }

        // Standard non-modifier navigation & actions
        match key {
            gdk::Key::F2 => {
                self.pending_chord.set(None);
                return Some(KeyCommand::Rename);
            }
            gdk::Key::Delete if shift => {
                self.pending_chord.set(None);
                return Some(KeyCommand::PermanentDelete);
            }
            gdk::Key::Delete => {
                self.pending_chord.set(None);
                return Some(KeyCommand::Trash);
            }
            gdk::Key::BackSpace => {
                self.pending_chord.set(None);
                return Some(KeyCommand::GoParent);
            }
            gdk::Key::space => {
                if vim_enabled && self.pending_chord.take() == Some('g') {
                    return Some(KeyCommand::FocusPathBar);
                }
                self.pending_chord.set(None);
                return Some(KeyCommand::ToggleSelectAndAdvance);
            }
            gdk::Key::Tab => {
                self.pending_chord.set(None);
                return Some(KeyCommand::SwitchSplitPane);
            }
            gdk::Key::Return | gdk::Key::KP_Enter => {
                self.pending_chord.set(None);
                return Some(KeyCommand::OpenSelected);
            }
            gdk::Key::Down if !is_grid_mode && !shift => {
                self.pending_chord.set(None);
                return Some(KeyCommand::MoveDown);
            }
            gdk::Key::Up if !is_grid_mode && !shift => {
                self.pending_chord.set(None);
                return Some(KeyCommand::MoveUp);
            }
            gdk::Key::Home => {
                self.pending_chord.set(None);
                return Some(KeyCommand::GoFirst);
            }
            gdk::Key::End => {
                self.pending_chord.set(None);
                return Some(KeyCommand::GoLast);
            }
            _ => {}
        }

        if !vim_enabled {
            self.pending_chord.set(None);
            return None;
        }

        // Yazi/Vim two-key chords: gg, g<place>, zh
        if let Some(first) = self.pending_chord.take() {
            return match (first, key) {
                ('g', gdk::Key::g) => Some(KeyCommand::GoFirst),
                ('g', gdk::Key::h) => Some(KeyCommand::Goto(GotoTarget::Home)),
                ('g', gdk::Key::c) => Some(KeyCommand::Goto(GotoTarget::Config)),
                ('g', gdk::Key::d) => Some(KeyCommand::Goto(GotoTarget::Downloads)),
                ('g', gdk::Key::D) => Some(KeyCommand::Goto(GotoTarget::Documents)),
                ('g', gdk::Key::e) => Some(KeyCommand::Goto(GotoTarget::Desktop)),
                ('g', gdk::Key::p) => Some(KeyCommand::Goto(GotoTarget::Pictures)),
                ('g', gdk::Key::v) => Some(KeyCommand::Goto(GotoTarget::Videos)),
                ('g', gdk::Key::m) => Some(KeyCommand::Goto(GotoTarget::Music)),
                ('g', gdk::Key::t) => Some(KeyCommand::Goto(GotoTarget::Trash)),
                ('g', gdk::Key::slash) => Some(KeyCommand::Goto(GotoTarget::Root)),
                ('z', gdk::Key::h) => Some(KeyCommand::ToggleHidden),
                _ => None,
            };
        }

        match key {
            gdk::Key::j => Some(KeyCommand::MoveDown),
            gdk::Key::k => Some(KeyCommand::MoveUp),
            gdk::Key::J => Some(KeyCommand::MoveDownFast),
            gdk::Key::K => Some(KeyCommand::MoveUpFast),
            gdk::Key::h | gdk::Key::minus => Some(KeyCommand::GoParent),
            gdk::Key::l | gdk::Key::o => Some(KeyCommand::OpenSelected),
            gdk::Key::H => Some(KeyCommand::GoBack),
            gdk::Key::L => Some(KeyCommand::GoForward),
            gdk::Key::G => Some(KeyCommand::GoLast),
            gdk::Key::slash => Some(KeyCommand::FocusFilter),
            gdk::Key::y => Some(KeyCommand::Copy),
            gdk::Key::x => Some(KeyCommand::Cut),
            gdk::Key::p => Some(KeyCommand::Paste),
            gdk::Key::d => Some(KeyCommand::Trash),
            gdk::Key::D => Some(KeyCommand::PermanentDelete),
            gdk::Key::a => Some(KeyCommand::CreatePrompt),
            gdk::Key::u => Some(KeyCommand::Undo),
            gdk::Key::r => Some(KeyCommand::Rename),
            gdk::Key::period => Some(KeyCommand::ToggleHidden),
            gdk::Key::bracketleft => Some(KeyCommand::PrevTab),
            gdk::Key::bracketright => Some(KeyCommand::NextTab),
            gdk::Key::t => Some(KeyCommand::NewTab),
            gdk::Key::_1 => Some(KeyCommand::SwitchTab(0)),
            gdk::Key::_2 => Some(KeyCommand::SwitchTab(1)),
            gdk::Key::_3 => Some(KeyCommand::SwitchTab(2)),
            gdk::Key::_4 => Some(KeyCommand::SwitchTab(3)),
            gdk::Key::_5 => Some(KeyCommand::SwitchTab(4)),
            gdk::Key::_6 => Some(KeyCommand::SwitchTab(5)),
            gdk::Key::_7 => Some(KeyCommand::SwitchTab(6)),
            gdk::Key::_8 => Some(KeyCommand::SwitchTab(7)),
            gdk::Key::_9 => Some(KeyCommand::SwitchTab(8)),
            gdk::Key::g => {
                self.pending_chord.set(Some('g'));
                None
            }
            gdk::Key::z => {
                self.pending_chord.set(Some('z'));
                None
            }
            _ => None,
        }
    }
}

pub fn is_focus_in_text_input(window: &gtk4::ApplicationWindow) -> bool {
    let Some(focus) = gtk4::prelude::GtkWindowExt::focus(window) else {
        return false;
    };
    focus.is::<gtk4::Text>()
        || focus.is::<gtk4::Entry>()
        || focus.is::<gtk4::SearchEntry>()
        || focus.is::<gtk4::TextView>()
        || focus.is::<gtk4::Editable>()
}

pub fn attach_window_keys<F, P>(
    window: &gtk4::ApplicationWindow,
    vim_enabled: Rc<dyn Fn() -> bool>,
    is_grid_mode: Rc<dyn Fn() -> bool>,
    on_command: F,
    on_pending_chord: P,
) where
    F: Fn(KeyCommand) + 'static,
    P: Fn(Option<char>) + 'static,
{
    let ctrl = gtk4::EventControllerKey::new();
    ctrl.set_propagation_phase(gtk4::PropagationPhase::Capture);
    let state = Rc::new(VimKeyState::default());
    let win_weak = window.downgrade();
    ctrl.connect_key_pressed(move |_, key, _, mods| {
        let Some(win) = win_weak.upgrade() else {
            return glib::Propagation::Proceed;
        };
        let in_text = is_focus_in_text_input(&win);
        let cmd = state.interpret(key, mods, vim_enabled(), in_text, is_grid_mode());
        on_pending_chord(state.pending_chord());
        if let Some(cmd) = cmd {
            on_command(cmd);
            return glib::Propagation::Stop;
        }
        glib::Propagation::Proceed
    });
    window.add_controller(ctrl);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn vim_chords_and_standard_shortcuts_work() {
        let st = VimKeyState::default();
        assert_eq!(
            st.interpret(gdk::Key::j, gdk::ModifierType::empty(), true, false, false),
            Some(KeyCommand::MoveDown)
        );
        assert_eq!(
            st.interpret(gdk::Key::g, gdk::ModifierType::empty(), true, false, false),
            None
        );
        assert_eq!(
            st.interpret(gdk::Key::g, gdk::ModifierType::empty(), true, false, false),
            Some(KeyCommand::GoFirst)
        );
        // Yazi single-key bindings: y copy, x cut, d trash, D permanent delete, a create
        assert_eq!(
            st.interpret(gdk::Key::y, gdk::ModifierType::empty(), true, false, false),
            Some(KeyCommand::Copy)
        );
        assert_eq!(
            st.interpret(gdk::Key::x, gdk::ModifierType::empty(), true, false, false),
            Some(KeyCommand::Cut)
        );
        assert_eq!(
            st.interpret(gdk::Key::d, gdk::ModifierType::empty(), true, false, false),
            Some(KeyCommand::Trash)
        );
        assert_eq!(
            st.interpret(gdk::Key::D, gdk::ModifierType::SHIFT_MASK, true, false, false),
            Some(KeyCommand::PermanentDelete)
        );
        assert_eq!(
            st.interpret(gdk::Key::a, gdk::ModifierType::empty(), true, false, false),
            Some(KeyCommand::CreatePrompt)
        );
        assert_eq!(
            st.interpret(gdk::Key::space, gdk::ModifierType::empty(), true, false, false),
            Some(KeyCommand::ToggleSelectAndAdvance)
        );
        assert_eq!(
            st.interpret(gdk::Key::space, gdk::ModifierType::ALT_MASK, true, false, false),
            Some(KeyCommand::QuickLook)
        );
        // Vim keys must NOT fire while typing in an Entry/SearchEntry
        assert_eq!(
            st.interpret(gdk::Key::j, gdk::ModifierType::empty(), true, true, false),
            None
        );
        // Arrow keys in Grid mode are delegated to native GridView 2D navigation
        assert_eq!(
            st.interpret(gdk::Key::Down, gdk::ModifierType::empty(), true, false, true),
            None
        );
        // Ctrl+K works everywhere
        assert_eq!(
            st.interpret(gdk::Key::k, gdk::ModifierType::CONTROL_MASK, true, true, true),
            Some(KeyCommand::OpenCommandPalette)
        );
        // Alt+T opens new tab, Alt+W closes tab, Alt+1..9 switches tabs
        assert_eq!(
            st.interpret(gdk::Key::t, gdk::ModifierType::ALT_MASK, true, false, true),
            Some(KeyCommand::NewTab)
        );
        assert_eq!(
            st.interpret(gdk::Key::w, gdk::ModifierType::ALT_MASK, true, true, false),
            Some(KeyCommand::CloseTab)
        );
        assert_eq!(
            st.interpret(gdk::Key::_1, gdk::ModifierType::ALT_MASK, true, false, false),
            Some(KeyCommand::SwitchTab(0))
        );
        assert_eq!(
            st.interpret(gdk::Key::_5, gdk::ModifierType::ALT_MASK, true, true, true),
            Some(KeyCommand::SwitchTab(4))
        );
        assert_eq!(
            st.interpret(gdk::Key::_9, gdk::ModifierType::ALT_MASK, true, false, false),
            Some(KeyCommand::SwitchTab(8))
        );
        assert_eq!(
            st.interpret(gdk::Key::F3, gdk::ModifierType::empty(), true, false, false),
            Some(KeyCommand::ToggleSplitView)
        );
        assert_eq!(
            st.interpret(gdk::Key::Tab, gdk::ModifierType::empty(), true, false, false),
            Some(KeyCommand::SwitchSplitPane)
        );
        // Alt+h/j/k/l directional pane navigation
        assert_eq!(
            st.interpret(gdk::Key::h, gdk::ModifierType::ALT_MASK, true, false, false),
            Some(KeyCommand::FocusPaneLeft)
        );
        assert_eq!(
            st.interpret(gdk::Key::j, gdk::ModifierType::ALT_MASK, true, true, true),
            Some(KeyCommand::FocusPaneDown)
        );
        assert_eq!(
            st.interpret(gdk::Key::k, gdk::ModifierType::ALT_MASK, false, false, false),
            Some(KeyCommand::FocusPaneUp)
        );
        assert_eq!(
            st.interpret(gdk::Key::l, gdk::ModifierType::ALT_MASK, true, false, false),
            Some(KeyCommand::FocusPaneRight)
        );
        // Extended Yazi g<place> chords (including Shift_L pressed before 'D' and safe cancel on unknown key)
        for (k2, mods, expected) in [
            (gdk::Key::h, gdk::ModifierType::empty(), GotoTarget::Home),
            (gdk::Key::c, gdk::ModifierType::empty(), GotoTarget::Config),
            (gdk::Key::d, gdk::ModifierType::empty(), GotoTarget::Downloads),
            (gdk::Key::e, gdk::ModifierType::empty(), GotoTarget::Desktop),
            (gdk::Key::p, gdk::ModifierType::empty(), GotoTarget::Pictures),
            (gdk::Key::v, gdk::ModifierType::empty(), GotoTarget::Videos),
            (gdk::Key::m, gdk::ModifierType::empty(), GotoTarget::Music),
            (gdk::Key::t, gdk::ModifierType::empty(), GotoTarget::Trash),
            (gdk::Key::slash, gdk::ModifierType::empty(), GotoTarget::Root),
        ] {
            assert_eq!(
                st.interpret(gdk::Key::g, gdk::ModifierType::empty(), true, false, false),
                None
            );
            assert_eq!(st.pending_chord(), Some('g'));
            assert_eq!(
                st.interpret(k2, mods, true, false, false),
                Some(KeyCommand::Goto(expected))
            );
            assert_eq!(st.pending_chord(), None);
        }
        // g -> Shift_L -> D -> Documents
        assert_eq!(
            st.interpret(gdk::Key::g, gdk::ModifierType::empty(), true, false, false),
            None
        );
        assert_eq!(
            st.interpret(gdk::Key::Shift_L, gdk::ModifierType::SHIFT_MASK, true, false, false),
            None
        );
        assert_eq!(st.pending_chord(), Some('g'));
        assert_eq!(
            st.interpret(gdk::Key::D, gdk::ModifierType::SHIFT_MASK, true, false, false),
            Some(KeyCommand::Goto(GotoTarget::Documents))
        );
        // g -> Space -> FocusPathBar
        assert_eq!(
            st.interpret(gdk::Key::g, gdk::ModifierType::empty(), true, false, false),
            None
        );
        assert_eq!(
            st.interpret(gdk::Key::space, gdk::ModifierType::empty(), true, false, false),
            Some(KeyCommand::FocusPathBar)
        );
        // Mistyped chord g -> x cancels cleanly instead of triggering Cut
        assert_eq!(
            st.interpret(gdk::Key::g, gdk::ModifierType::empty(), true, false, false),
            None
        );
        assert_eq!(
            st.interpret(gdk::Key::x, gdk::ModifierType::empty(), true, false, false),
            None
        );
        assert_eq!(st.pending_chord(), None);
        // History H/L, fast jump J/K, Ctrl+d/u, tabs [/]/t/1..9
        assert_eq!(
            st.interpret(gdk::Key::H, gdk::ModifierType::SHIFT_MASK, true, false, false),
            Some(KeyCommand::GoBack)
        );
        assert_eq!(
            st.interpret(gdk::Key::L, gdk::ModifierType::SHIFT_MASK, true, false, false),
            Some(KeyCommand::GoForward)
        );
        assert_eq!(
            st.interpret(gdk::Key::J, gdk::ModifierType::SHIFT_MASK, true, false, false),
            Some(KeyCommand::MoveDownFast)
        );
        assert_eq!(
            st.interpret(gdk::Key::K, gdk::ModifierType::SHIFT_MASK, true, false, false),
            Some(KeyCommand::MoveUpFast)
        );
        assert_eq!(
            st.interpret(gdk::Key::d, gdk::ModifierType::CONTROL_MASK, true, false, false),
            Some(KeyCommand::MoveHalfPageDown)
        );
        assert_eq!(
            st.interpret(gdk::Key::u, gdk::ModifierType::CONTROL_MASK, true, false, false),
            Some(KeyCommand::MoveHalfPageUp)
        );
        assert_eq!(
            st.interpret(gdk::Key::bracketleft, gdk::ModifierType::empty(), true, false, false),
            Some(KeyCommand::PrevTab)
        );
        assert_eq!(
            st.interpret(gdk::Key::bracketright, gdk::ModifierType::empty(), true, false, false),
            Some(KeyCommand::NextTab)
        );
        assert_eq!(
            st.interpret(gdk::Key::t, gdk::ModifierType::empty(), true, false, false),
            Some(KeyCommand::NewTab)
        );
        assert_eq!(
            st.interpret(gdk::Key::_1, gdk::ModifierType::empty(), true, false, false),
            Some(KeyCommand::SwitchTab(0))
        );
        assert_eq!(
            st.interpret(gdk::Key::_9, gdk::ModifierType::empty(), true, false, false),
            Some(KeyCommand::SwitchTab(8))
        );
    }
}
