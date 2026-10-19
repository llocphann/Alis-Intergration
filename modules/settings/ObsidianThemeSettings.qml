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
 id:root
 title:Translation.tr("Obsidian");icon:"diamond";expanded:true
 Component.onCompleted:ObsidianTheme.inspect()
 SettingsNativeDialogGuard {dialog:picker;dialogKey:"obsidianConfigPicker"}
 FolderDialog {
  id:picker;title:"Obsidian configuration folder"
  onAccepted:Config.setNestedValue("integrations.obsidian.configPath",FileUtils.trimFileProtocol(String(selectedFolder)))
 }
 SettingsGroup {
  ContentSubsection {title:"Paths"}
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

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
                        // Clear the old override so clearing the shared field
                        // never resurrects a separate Quick Notes vault.
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


  StyledText {text:"Vault configuration folder";color:Appearance.colors.colSubtext}
  RowLayout {
   Layout.fillWidth:true
   MaterialTextField {objectName:"obsidianVaultConfigPath";Layout.fillWidth:true;wrapMode:TextInput.NoWrap;text:Config.options?.integrations?.obsidian?.configPath ?? "";placeholderText:".obsidian (inside the shared vault)";onEditingFinished:Config.setNestedValue("integrations.obsidian.configPath",text.trim())}
   RippleButtonWithIcon {materialIcon:"folder_open";mainText:Translation.tr("Browse");onClicked:picker.open()}
  }
  StyledText {text:"Application configuration folder";color:Appearance.colors.colSubtext}
  MaterialTextField {objectName:"obsidianApplicationConfigPath";Layout.fillWidth:true;wrapMode:TextInput.NoWrap;text:Config.options?.integrations?.obsidian?.applicationConfigPath ?? "";placeholderText:"Auto-detect Obsidian's application config";onEditingFinished:Config.setNestedValue("integrations.obsidian.applicationConfigPath",text.trim())}
  StyledText {text:"Application executable";color:Appearance.colors.colSubtext}
  RowLayout {
   Layout.fillWidth:true
   MaterialTextField {Layout.fillWidth:true;wrapMode:TextInput.NoWrap;text:Config.options?.integrations?.obsidian?.applicationPath ?? "obsidian";placeholderText:"obsidian";onEditingFinished:Config.setNestedValue("integrations.obsidian.applicationPath",text.trim() || "obsidian")}
   DialogButton {buttonText:"Open Obsidian";onClicked:Quickshell.execDetached([String(Config.options?.integrations?.obsidian?.applicationPath || "obsidian").trim()])}
  }
  ContentSubsection {title:Translation.tr("Auto theming")}
  SettingsSwitch {text:Translation.tr("Follow Alis colors");autoToggle:false;checked:ObsidianTheme.enabled;onToggledByUser:checked=>Config.setNestedValue("integrations.obsidian.autoTheme",checked)}
  StyledText {
   Layout.fillWidth:true;wrapMode:Text.WordWrap
   color:ObsidianTheme.error ? Appearance.colors.colError : Appearance.colors.colSubtext
   text:ObsidianTheme.error || (ObsidianTheme.info.activeTheme ? ObsidianTheme.info.activeTheme+" · "+(ObsidianTheme.info.enabled ? Translation.tr("Applied") : Translation.tr("Not applied")) : Translation.tr("Choose a vault"))
   StyledToolTip {text:ObsidianTheme.info.snippetPath || ""}
  }
  RowLayout {
   DialogButton {buttonText:Translation.tr("Detect");enabled:!ObsidianTheme.busy;onClicked:ObsidianTheme.inspect()}
   DialogButton {buttonText:Translation.tr("Apply");enabled:!ObsidianTheme.busy;onClicked:ObsidianTheme.apply()}
   DialogButton {buttonText:Translation.tr("Disable");enabled:!ObsidianTheme.busy && (ObsidianTheme.info.enabled ?? false);onClicked:ObsidianTheme.restore()}
  }
  DialogButton {buttonText:"Use detected vault";visible:!Todo.sharedVaultPath && !!ObsidianTheme.info.vaultPath;onClicked:Config.setNestedValue("todo.obsidian.vaultPath",ObsidianTheme.info.vaultPath)}
 }
}
