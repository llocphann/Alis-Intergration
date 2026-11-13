pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import qs
import qs.services
import qs.modules.settings
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

SettingsCardSection {
    id: root
    title: Translation.tr("Alis Nexus")
    icon: "hub"
    expanded: true
    property var nexusOverride: null
    property bool shortcutsTabOpen: false
    readonly property var _nexus: root.nexusOverride ?? AlisIntergration.session?.nexus ?? null
    readonly property real standardSubTabTargetHeight: {
        const stdH = Number(SettingsMaterialPreset.standardBentoHeight ?? 0);
        return stdH > 400 ? stdH : 815;
    }
    readonly property real targetSubTabCardHeight: root._effectiveCustomHeight > 0
        ? root._effectiveCustomHeight
        : root.standardSubTabTargetHeight
    readonly property real subTabContentHeight: {
        const cardOverhead = (root.chromeImplicitHeight > 0 ? root.chromeImplicitHeight : 65)
            + (SettingsMaterialPreset.groupPadding ?? 12) * 2;
        return Math.max(360, root.targetSubTabCardHeight - cardOverhead);
    }
    Component.onCompleted: NexusTheme.inspect()
    SettingsNativeDialogGuard { dialog: picker; dialogKey: "nexusConfigPicker" }
    FolderDialog {
        id: picker
        title: "Nexus configuration folder"
        onAccepted: Config.setNestedValue("integrations.nexus.configPath", FileUtils.trimFileProtocol(String(selectedFolder)))
    }

    SettingsGroup {
        // ── TAB 1: Main Nexus Settings (Hidden when Shortcuts Sub-Tab is open) ──
        ColumnLayout {
            id: mainSettingsSubTab
            objectName: "nexusMainSettingsSubTab"
            visible: !root.shortcutsTabOpen
            Layout.fillWidth: true
            spacing: 10

            GridLayout {
                Layout.fillWidth: true
                columns: 1
                columnSpacing: 12
                rowSpacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    spacing: 4

                    StyledText {
                        text: Translation.tr("Nexus vault folder")
                        color: Appearance.colors.colOnSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    MaterialTextField {
                        id: todoNexusVaultPath
                        objectName: "nexusVaultPath"
                        Layout.fillWidth: true
                        wrapMode: TextInput.NoWrap
                        placeholderText: ""
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurface
                        text: Todo.sharedVaultPath
                        background: Rectangle {
                            color: Appearance.colors.colLayer1
                            radius: Appearance.rounding.small
                            border.width: todoNexusVaultPath.activeFocus ? 2 : 1
                            border.color: todoNexusVaultPath.activeFocus
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colLayer0Border
                        }
                        onEditingFinished: {
                            const value = text.trim()
                            const canonical = String(Config.options?.todo?.nexus?.vaultPath ?? "").trim()
                            const legacy = String(Config.options?.notes?.zettelkasten?.vaultPath ?? "").trim()
                            const updates = {}
                            if (value !== canonical)
                                updates["todo.nexus.vaultPath"] = value
                            if (legacy.length > 0)
                                updates["notes.zettelkasten.vaultPath"] = ""
                            Config.setNestedValues(updates)
                        }

                        StyledToolTip {
                            text: Translation.tr("Shared by To-do and Zettelkasten.")
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 4

                    StyledText {
                        text: Translation.tr("Vault configuration folder")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        MaterialTextField {
                            objectName: "nexusVaultConfigPath"
                            Layout.fillWidth: true
                            wrapMode: TextInput.NoWrap
                            text: Config.options?.integrations?.nexus?.configPath ?? ""
                            placeholderText: ".nexus (inside the shared vault)"
                            onEditingFinished: Config.setNestedValue("integrations.nexus.configPath", text.trim())
                        }
                        RippleButtonWithIcon {
                            materialIcon: "folder_open"
                            mainText: Translation.tr("Browse")
                            onClicked: picker.open()
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 4

                    StyledText {
                        text: Translation.tr("Application configuration folder")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    MaterialTextField {
                        objectName: "nexusApplicationConfigPath"
                        Layout.fillWidth: true
                        wrapMode: TextInput.NoWrap
                        text: Config.options?.integrations?.nexus?.applicationConfigPath ?? ""
                        placeholderText: "Auto-detect Nexus's application config"
                        onEditingFinished: Config.setNestedValue("integrations.nexus.applicationConfigPath", text.trim())
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 4

                    StyledText {
                        text: Translation.tr("Application executable")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        MaterialTextField {
                            Layout.fillWidth: true
                            wrapMode: TextInput.NoWrap
                            text: Config.options?.integrations?.nexus?.applicationPath ?? "nexus"
                            placeholderText: "nexus"
                            onEditingFinished: Config.setNestedValue("integrations.nexus.applicationPath", text.trim() || "nexus")
                        }
                        DialogButton {
                            buttonText: Translation.tr("Open Nexus")
                            onClicked: Quickshell.execDetached([String(Config.options?.integrations?.nexus?.applicationPath || "nexus").trim()])
                        }
                    }
                }
            }

            SettingsDivider {}

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                SettingsSwitch {
                    Layout.fillWidth: false
                    text: Translation.tr("Follow Alis colors")
                    autoToggle: false
                    checked: NexusTheme.enabled
                    onToggledByUser: checked => Config.setNestedValue("integrations.nexus.autoTheme", checked)
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: NexusTheme.error ? Appearance.colors.colError : Appearance.colors.colSubtext
                    text: NexusTheme.error || (NexusTheme.info.activeTheme
                        ? NexusTheme.info.activeTheme + " · " + (NexusTheme.info.enabled ? Translation.tr("Applied") : Translation.tr("Not applied"))
                        : Translation.tr("Choose a vault"))
                    StyledToolTip { text: NexusTheme.info.snippetPath || "" }
                }

                DialogButton {
                    buttonText: Translation.tr("Detect")
                    enabled: !NexusTheme.busy
                    onClicked: NexusTheme.inspect()
                }
                DialogButton {
                    buttonText: Translation.tr("Apply")
                    enabled: !NexusTheme.busy
                    onClicked: NexusTheme.apply()
                }
                DialogButton {
                    buttonText: Translation.tr("Disable")
                    enabled: !NexusTheme.busy && (NexusTheme.info.enabled ?? false)
                    onClicked: NexusTheme.restore()
                }
                DialogButton {
                    buttonText: Translation.tr("Use detected vault")
                    visible: !Todo.sharedVaultPath && !!NexusTheme.info.vaultPath
                    onClicked: Config.setNestedValue("todo.nexus.vaultPath", NexusTheme.info.vaultPath)
                }
            }

            SettingsDivider {}

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Alis Nexus Knowledge Workspace")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: Translation.tr("Rust-powered knowledge graph, Logseq-style hybrid block outliner, and Vim markdown editor for your shared vault.")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    DialogButton {
                        objectName: "openNexusOverlayButton"
                        buttonText: Translation.tr("Open Nexus (Overlay)")
                        onClicked: {
                            if (AlisIntergration.session?.nexus)
                                AlisIntergration.session.nexus.openOverlay();
                        }
                    }

                    DialogButton {
                        objectName: "openNexusWindowButton"
                        buttonText: Translation.tr("Open Nexus (Window)")
                        onClicked: {
                            if (AlisIntergration.session?.nexus)
                                AlisIntergration.session.nexus.openWindow();
                        }
                    }

                    DialogButton {
                        objectName: "openNexusDailyButton"
                        buttonText: Translation.tr("Open Daily Journal")
                        onClicked: {
                            if (AlisIntergration.session?.nexus) {
                                AlisIntergration.session.nexus.open();
                                AlisIntergration.session.nexus.openDailyNote();
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    SettingsSwitch {
                        objectName: "nexusOverlayModeSwitch"
                        Layout.fillWidth: false
                        text: Translation.tr("Overlay mode by default")
                        autoToggle: false
                        checked: AlisIntergration.session?.nexus?.overlayMode ?? true
                        onToggledByUser: checked => {
                            if (AlisIntergration.session?.nexus)
                                AlisIntergration.session.nexus.setOverlayMode(checked);
                        }
                    }

                    SettingsSwitch {
                        objectName: "nexusVimModeSwitch"
                        Layout.fillWidth: false
                        text: Translation.tr("Vim keybindings")
                        autoToggle: false
                        checked: AlisIntergration.session?.nexus?.vimEnabled ?? true
                        onToggledByUser: checked => {
                            if (AlisIntergration.session?.nexus)
                                AlisIntergration.session.nexus.setVimEnabled(checked);
                        }
                    }
                }
            }

            SettingsDivider {}

            // ── Single Button to Open Keyboard Shortcuts Sub-Tab ──
            Rectangle {
                id: openShortcutsCard
                objectName: "openNexusShortcutsTabButton"
                visible: !root.shortcutsTabOpen
                Layout.fillWidth: true
                Layout.preferredHeight: 54
                radius: Appearance.rounding.small ?? 8
                color: openShortcutsMouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer1
                border.width: 1
                border.color: openShortcutsMouse.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    Rectangle {
                        width: 34
                        height: 34
                        radius: 8
                        color: Appearance.colors.colSecondaryContainer
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "keyboard"
                            iconSize: 18
                            color: Appearance.colors.colPrimary
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Keyboard Shortcuts & Keybindings")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: String((root._nexus?.shortcutCatalog ?? []).length) + " " + Translation.tr("configurable shortcuts · Click to customize")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }

                    Rectangle {
                        height: 28
                        width: openTabPillRow.implicitWidth + 16
                        radius: 6
                        color: Appearance.colors.colSecondaryContainer
                        RowLayout {
                            id: openTabPillRow
                            anchors.centerIn: parent
                            spacing: 4
                            StyledText {
                                text: Translation.tr("Configure")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            MaterialSymbol {
                                text: "arrow_forward"
                                iconSize: 14
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }
                }

                MouseArea {
                    id: openShortcutsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.shortcutsTabOpen = true;
                        shortcutCaptureScope.forceActiveFocus();
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                Layout.preferredHeight: 0
            }
        }

        // ── TAB 2: Keyboard Shortcuts Sub-Tab (Opened strictly via openNexusShortcutsTabButton, sized to standardBentoHeight) ──
        FocusScope {
            id: shortcutCaptureScope
            objectName: "nexusShortcutCaptureScope"
            visible: root.shortcutsTabOpen
            Layout.fillWidth: true
            Layout.fillHeight: visible
            Layout.preferredHeight: visible ? root.subTabContentHeight : 0
            implicitHeight: visible ? root.subTabContentHeight : 0
            focus: root.shortcutsTabOpen

            property string recordingActionId: ""
            property string filterQuery: ""

            Keys.onPressed: event => {
                if (shortcutCaptureScope.recordingActionId.length === 0)
                    return;
                event.accepted = true;
                if (event.key === Qt.Key_Escape && (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier | Qt.MetaModifier)) === 0) {
                    shortcutCaptureScope.recordingActionId = "";
                    return;
                }
                const nx = root._nexus;
                if (!nx)
                    return;
                const combo = nx.formatKeyEvent(event);
                if (combo.length > 0) {
                    nx.setShortcut(shortcutCaptureScope.recordingActionId, combo);
                    shortcutCaptureScope.recordingActionId = "";
                }
            }

            ColumnLayout {
                id: shortcutsCol
                objectName: "nexusShortcutsSubTab"
                width: parent.width
                height: parent.height
                spacing: 8

                // Top Sub-Tab Navigation Bar with Back Button
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        id: closeShortcutsBtn
                        objectName: "closeNexusShortcutsTabButton"
                        visible: root.shortcutsTabOpen
                        height: 30
                        width: backBtnRow.implicitWidth + 16
                        radius: 6
                        color: backBtnMouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer1
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border

                        RowLayout {
                            id: backBtnRow
                            anchors.centerIn: parent
                            spacing: 4
                            MaterialSymbol {
                                text: "arrow_back"
                                iconSize: 15
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                text: Translation.tr("Back")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                            }
                        }

                        MouseArea {
                            id: backBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                shortcutCaptureScope.recordingActionId = "";
                                root.shortcutsTabOpen = false;
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Nexus Keyboard Shortcuts")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurface
                    }

                    DialogButton {
                        objectName: "syncNexusVaultShortcutsButton"
                        buttonText: Translation.tr("Sync from Vault")
                        onClicked: {
                            if (root._nexus)
                                root._nexus.syncShortcutsFromVault();
                        }
                    }

                    DialogButton {
                        objectName: "resetNexusShortcutsButton"
                        buttonText: Translation.tr("Reset All")
                        onClicked: {
                            if (root._nexus)
                                root._nexus.resetAllShortcuts();
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: Translation.tr("Click any shortcut badge to record a new key combination, or press Escape to cancel.")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }

                MaterialTextField {
                    id: shortcutFilterField
                    objectName: "nexusShortcutFilterInput"
                    Layout.fillWidth: true
                    wrapMode: TextInput.NoWrap
                    placeholderText: Translation.tr("Filter shortcuts by action, key, or command...")
                    font.pixelSize: Appearance.font.pixelSize.small
                    onTextChanged: shortcutCaptureScope.filterQuery = text.trim().toLowerCase()
                }

                Flickable {
                    id: shortcutsListFlick
                    objectName: "nexusShortcutsFlickable"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 200
                    Layout.preferredHeight: Math.max(240, root.subTabContentHeight - 110)
                    contentWidth: width
                    contentHeight: shortcutListColumn.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: StyledScrollBar {
                        policy: shortcutsListFlick.contentHeight > shortcutsListFlick.height + 2 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    }

                    ColumnLayout {
                        id: shortcutListColumn
                        objectName: "nexusShortcutsList"
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: {
                                const catalog = root._nexus?.shortcutCatalog ?? [];
                                const q = shortcutCaptureScope.filterQuery;
                                const _rev = root._nexus?._shortcutRevision ?? 0;
                                void(_rev);
                                if (q.length === 0)
                                    return catalog;
                                const out = [];
                                for (let i = 0; i < catalog.length; ++i) {
                                    const item = catalog[i];
                                    if (!item)
                                        continue;
                                    const activeCombo = String(root._nexus?.shortcutFor(item.id) ?? item.defaultKey ?? "").toLowerCase();
                                    const vaultCmd = String(item.obsidianCommand ?? item.obsidianId ?? "").toLowerCase();
                                    if (String(item.title ?? "").toLowerCase().indexOf(q) !== -1
                                        || String(item.description ?? "").toLowerCase().indexOf(q) !== -1
                                        || vaultCmd.indexOf(q) !== -1
                                        || activeCombo.indexOf(q) !== -1) {
                                        out.push(item);
                                    }
                                }
                                return out;
                            }

                            delegate: Rectangle {
                                id: shortcutRowDelegate
                                required property var modelData
                                objectName: "nexusShortcutRow_" + String(modelData.id ?? "")
                                Layout.fillWidth: true
                                Layout.preferredHeight: 44
                                radius: Appearance.rounding.small ?? 8
                                color: Appearance.colors.colLayer1
                                border.width: (shortcutCaptureScope.recordingActionId === modelData.id) ? 2 : 1
                                border.color: (shortcutCaptureScope.recordingActionId === modelData.id)
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colLayer0Border

                                readonly property string currentCombo: {
                                    const _rev = root._nexus?._shortcutRevision ?? 0;
                                    void(_rev);
                                    return root._nexus
                                        ? root._nexus.shortcutFor(modelData.id)
                                        : String(modelData.defaultKey ?? "");
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: String(modelData.title ?? "")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.DemiBold
                                            color: Appearance.colors.colOnLayer1
                                            elide: Text.ElideRight
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            readonly property string cmdLabel: String(modelData.obsidianCommand ?? modelData.obsidianId ?? "")
                                            text: String(modelData.description ?? "") + (cmdLabel.length > 0 ? ("  ·  " + cmdLabel) : "")
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colSubtext
                                            elide: Text.ElideRight
                                        }
                                    }

                                    // Record / Active Keybinding Badge Button
                                    Rectangle {
                                        objectName: "nexusShortcutBindButton_" + String(modelData.id ?? "")
                                        Layout.preferredHeight: 28
                                        Layout.preferredWidth: Math.max(96, keyComboText.implicitWidth + 20)
                                        radius: 6
                                        color: (shortcutCaptureScope.recordingActionId === shortcutRowDelegate.modelData.id)
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colSecondaryContainer

                                        StyledText {
                                            id: keyComboText
                                            anchors.centerIn: parent
                                            text: (shortcutCaptureScope.recordingActionId === shortcutRowDelegate.modelData.id)
                                                ? Translation.tr("Press keys...")
                                                : (shortcutRowDelegate.currentCombo || Translation.tr("Unbound"))
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.weight: Font.Bold
                                            color: (shortcutCaptureScope.recordingActionId === shortcutRowDelegate.modelData.id)
                                                ? Appearance.colors.colOnPrimary
                                                : Appearance.colors.colOnSecondaryContainer
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (shortcutCaptureScope.recordingActionId === shortcutRowDelegate.modelData.id) {
                                                    shortcutCaptureScope.recordingActionId = "";
                                                } else {
                                                    shortcutCaptureScope.recordingActionId = shortcutRowDelegate.modelData.id;
                                                    shortcutCaptureScope.forceActiveFocus();
                                                }
                                            }
                                        }
                                    }

                                    // Reset single shortcut button
                                    Rectangle {
                                        objectName: "nexusShortcutResetButton_" + String(modelData.id ?? "")
                                        implicitWidth: 28
                                        implicitHeight: 28
                                        width: 28
                                        height: 28
                                        radius: 6
                                        color: resetSingleMouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "restart_alt"
                                            iconSize: 15
                                            color: Appearance.colors.colSubtext
                                        }

                                        MouseArea {
                                            id: resetSingleMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (root._nexus)
                                                    root._nexus.resetShortcut(shortcutRowDelegate.modelData.id);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
