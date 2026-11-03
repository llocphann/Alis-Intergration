pragma ComponentBehavior: Bound
import QtQuick
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
    title: Translation.tr("Obsidian")
    icon: "diamond"
    expanded: true
    Component.onCompleted: ObsidianTheme.inspect()
    SettingsNativeDialogGuard { dialog: picker; dialogKey: "obsidianConfigPicker" }
    FolderDialog {
        id: picker
        title: "Obsidian configuration folder"
        onAccepted: Config.setNestedValue("integrations.obsidian.configPath", FileUtils.trimFileProtocol(String(selectedFolder)))
    }

    SettingsGroup {
        GridLayout {
            Layout.fillWidth: true
            columns: width >= 560 ? 2 : 1
            columnSpacing: 12
            rowSpacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 4

                StyledText {
                    text: Translation.tr("Obsidian vault folder")
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.small
                }

                MaterialTextField {
                    id: todoObsidianVaultPath
                    objectName: "obsidianVaultPath"
                    Layout.fillWidth: true
                    wrapMode: TextInput.NoWrap
                    placeholderText: ""
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurface
                    text: Todo.sharedVaultPath
                    background: Rectangle {
                        color: Appearance.colors.colLayer1
                        radius: Appearance.rounding.small
                        border.width: todoObsidianVaultPath.activeFocus ? 2 : 1
                        border.color: todoObsidianVaultPath.activeFocus
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colLayer0Border
                    }
                    onEditingFinished: {
                        const value = text.trim()
                        const canonical = String(Config.options?.todo?.obsidian?.vaultPath ?? "").trim()
                        const legacy = String(Config.options?.notes?.zettelkasten?.vaultPath ?? "").trim()
                        const updates = {}
                        if (value !== canonical)
                            updates["todo.obsidian.vaultPath"] = value
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
                        objectName: "obsidianVaultConfigPath"
                        Layout.fillWidth: true
                        wrapMode: TextInput.NoWrap
                        text: Config.options?.integrations?.obsidian?.configPath ?? ""
                        placeholderText: ".obsidian (inside the shared vault)"
                        onEditingFinished: Config.setNestedValue("integrations.obsidian.configPath", text.trim())
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
                    objectName: "obsidianApplicationConfigPath"
                    Layout.fillWidth: true
                    wrapMode: TextInput.NoWrap
                    text: Config.options?.integrations?.obsidian?.applicationConfigPath ?? ""
                    placeholderText: "Auto-detect Obsidian's application config"
                    onEditingFinished: Config.setNestedValue("integrations.obsidian.applicationConfigPath", text.trim())
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
                        text: Config.options?.integrations?.obsidian?.applicationPath ?? "obsidian"
                        placeholderText: "obsidian"
                        onEditingFinished: Config.setNestedValue("integrations.obsidian.applicationPath", text.trim() || "obsidian")
                    }
                    DialogButton {
                        buttonText: Translation.tr("Open Obsidian")
                        onClicked: Quickshell.execDetached([String(Config.options?.integrations?.obsidian?.applicationPath || "obsidian").trim()])
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
                checked: ObsidianTheme.enabled
                onToggledByUser: checked => Config.setNestedValue("integrations.obsidian.autoTheme", checked)
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: ObsidianTheme.error ? Appearance.colors.colError : Appearance.colors.colSubtext
                text: ObsidianTheme.error || (ObsidianTheme.info.activeTheme
                    ? ObsidianTheme.info.activeTheme + " · " + (ObsidianTheme.info.enabled ? Translation.tr("Applied") : Translation.tr("Not applied"))
                    : Translation.tr("Choose a vault"))
                StyledToolTip { text: ObsidianTheme.info.snippetPath || "" }
            }

            DialogButton {
                buttonText: Translation.tr("Detect")
                enabled: !ObsidianTheme.busy
                onClicked: ObsidianTheme.inspect()
            }
            DialogButton {
                buttonText: Translation.tr("Apply")
                enabled: !ObsidianTheme.busy
                onClicked: ObsidianTheme.apply()
            }
            DialogButton {
                buttonText: Translation.tr("Disable")
                enabled: !ObsidianTheme.busy && (ObsidianTheme.info.enabled ?? false)
                onClicked: ObsidianTheme.restore()
            }
            DialogButton {
                buttonText: Translation.tr("Use detected vault")
                visible: !Todo.sharedVaultPath && !!ObsidianTheme.info.vaultPath
                onClicked: Config.setNestedValue("todo.obsidian.vaultPath", ObsidianTheme.info.vaultPath)
            }
        }
    }
}
