import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.services.deferred
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings
SettingsCardSection {
    id: root
    // Additive API: legacy hosts retain the combined editor.
    property string settingsView: "all"
    objectName: "hadalirdObsidianTodoSettings"
    settingsTaskSection: "obsidian"
    expanded: true
    icon: "checklist"
    title: root.settingsView === "todo" ? Translation.tr("To-do")
        : root.settingsView === "quicknotes" ? Translation.tr("Quick Notes")
        : Translation.tr("To-do & Quick Notes")

    SettingsGroup {
        visible: root.settingsView !== "quicknotes"
        ContentSubsection {
            title: Translation.tr("To-do")
            tooltip: Translation.tr("Choose the task store; your Alis backup is preserved.")

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: Todo.backend === "obsidian" ? "description" : "database"
                    iconSize: 20
                    color: Appearance.colors.colPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        text: Todo.backend === "obsidian"
                            ? Translation.tr("Obsidian is canonical")
                            : Translation.tr("Alis internal Todo is canonical")
                        color: Appearance.colors.colOnSurface
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                    }
                }

                RippleButton {
                    visible: Todo.backend !== "obsidian" && !Todo.obsidianSetupActive
                    Layout.preferredWidth: todoPrepareRow.implicitWidth + 20
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    onClicked: Todo.beginObsidianSetup()

                    contentItem: RowLayout {
                        id: todoPrepareRow
                        anchors.centerIn: parent
                        spacing: 5
                        MaterialSymbol {
                            text: "settings"
                            iconSize: 16
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: Translation.tr("Prepare Obsidian")
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                }

                RippleButton {
                    visible: Todo.backend !== "obsidian" && Todo.obsidianSetupActive
                    Layout.preferredWidth: todoCancelSetupRow.implicitWidth + 20
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    onClicked: Todo.cancelObsidianSetup()

                    contentItem: RowLayout {
                        id: todoCancelSetupRow
                        anchors.centerIn: parent
                        spacing: 5
                        MaterialSymbol {
                            text: "close"
                            iconSize: 16
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        StyledText {
                            text: Translation.tr("Cancel setup")
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                }

                RippleButton {
                    visible: Todo.backend === "obsidian"
                    Layout.preferredWidth: todoRollbackRow.implicitWidth + 20
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    onClicked: Todo.reactivateInternal()

                    contentItem: RowLayout {
                        id: todoRollbackRow
                        anchors.centerIn: parent
                        spacing: 5
                        MaterialSymbol {
                            text: "undo"
                            iconSize: 16
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: Translation.tr("Use Alis")
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }

                    StyledToolTip {
                        text: Translation.tr("Restore the preserved Alis store.")
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Task source")
            tooltip: Todo.useLegacyManagedNote
                ? Translation.tr("Legacy managed-note mode.")
                : Translation.tr("Tasks are read from one Markdown file and heading.")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            StyledText {
                text: Translation.tr("Note path pattern")
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
            }

            MaterialTextField {
                id: todoMarkdownNotePattern
                objectName: "obsidianTodoNotePattern"
                Layout.fillWidth: true
                implicitWidth: 0
                placeholderText: ""
                font.pixelSize: Appearance.font.pixelSize.small
                font.family: Appearance.font.family.monospace
                color: Appearance.colors.colOnSurface
                text: {
                    const folder = String(Config.options?.todo?.obsidian?.dailyNote?.folder
                        ?? "00_Capture/01_Journal").trim().replace(/^\/+|\/+$/g, "")
                    let format = String(Config.options?.todo?.obsidian?.dailyNote?.format
                        ?? "YYYY/MMMM/DD-MM-YYYY-dddd").trim().replace(/^\/+|\/+$/g, "")
                    if (!format.toLowerCase().endsWith(".md"))
                        format += ".md"
                    return folder.length > 0 ? folder + "/" + format : format
                }
                background: Rectangle {
                    color: Appearance.colors.colLayer1
                    radius: Appearance.rounding.small
                    border.width: todoMarkdownNotePattern.activeFocus ? 2 : 1
                    border.color: todoMarkdownNotePattern.activeFocus
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colLayer0Border
                }
                onEditingFinished: {
                    let value = text.trim().replace(/^\/+|\/+$/g, "")
                    if (value.length === 0)
                        return
                    const slash = value.lastIndexOf("/")
                    const folder = slash >= 0 ? value.slice(0, slash) : ""
                    const format = slash >= 0 ? value.slice(slash + 1) : value
                    if (format.length === 0)
                        return
                    Config.setNestedValue("todo.obsidian.dailyNote.folder", folder)
                    Config.setNestedValue("todo.obsidian.dailyNote.format", format)
                    if (Todo.backend !== "obsidian"
                            && Todo.obsidianSourceMode !== "markdown-note")
                        Config.setNestedValue("todo.obsidian.sourceMode", "markdown-note")
                }
            }

        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            StyledText {
                text: Translation.tr("Heading")
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
            }

            MaterialTextField {
                id: todoMarkdownHeading
                objectName: "obsidianTodoHeading"
                Layout.fillWidth: true
                implicitWidth: 0
                placeholderText: ""
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurface
                text: String(Config.options?.todo?.obsidian?.dailyNote?.plannerHeading
                    ?? "Tasks")
                background: Rectangle {
                    color: Appearance.colors.colLayer1
                    radius: Appearance.rounding.small
                    border.width: todoMarkdownHeading.activeFocus ? 2 : 1
                    border.color: todoMarkdownHeading.activeFocus
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colLayer0Border
                }
                onEditingFinished: {
                    const value = text.trim()
                    if (value.length > 0
                            && value !== String(Config.options?.todo?.obsidian?.dailyNote?.plannerHeading
                                ?? "Tasks"))
                        Config.setNestedValue("todo.obsidian.dailyNote.plannerHeading", value)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ConfigSpinBox {
                    Layout.fillWidth: true
                    icon: "tag"
                    text: Translation.tr("Heading level")
                    value: Config.options?.todo?.obsidian?.dailyNote?.plannerHeadingLevel ?? 2
                    from: 1
                    to: 6
                    stepSize: 1
                    onValueChanged:
                        Config.setNestedValue("todo.obsidian.dailyNote.plannerHeadingLevel", value)
                }

                ConfigSpinBox {
                    Layout.fillWidth: true
                    icon: "schedule"
                    text: Translation.tr("Default duration (minutes)")
                    value: Config.options?.todo?.obsidian?.dailyNote?.defaultDurationMinutes ?? 30
                    from: 5
                    to: 240
                    stepSize: 5
                    onValueChanged:
                        Config.setNestedValue("todo.obsidian.dailyNote.defaultDurationMinutes", value)
                }
            }

        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: todoObsidianStatusColumn.implicitHeight + 20
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1

            ColumnLayout {
                id: todoObsidianStatusColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 10
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialSymbol {
                        text: {
                            if (Todo.backend !== "obsidian" && !Todo.obsidianSetupActive)
                                return "database"
                            if (Todo.obsidianErrorCode.length > 0)
                                return "error"
                            if (Todo.obsidianCapabilities?.richMutationAvailable === true)
                                return "verified"
                            if (Todo.obsidianReady)
                                return "sync"
                            return "hourglass"
                        }
                        iconSize: 18
                        color: Todo.obsidianErrorCode.length > 0
                            ? Appearance.colors.colError
                            : Appearance.colors.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            if (Todo.backend !== "obsidian" && !Todo.obsidianSetupActive)
                                return Translation.tr("Obsidian setup is inactive")
                            if (Todo.obsidianErrorMessage.length > 0)
                                return Todo.obsidianErrorMessage
                            if (Todo.obsidianReady)
                                return Translation.tr("Markdown task source ready")
                            return Translation.tr("Waiting for the configured Markdown note and heading")
                        }
                        color: Todo.obsidianErrorCode.length > 0
                            ? Appearance.colors.colError
                            : Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                        wrapMode: Text.WordWrap
                    }
                }

            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: Todo.backend === "obsidian" || Todo.obsidianSetupActive

            RippleButton {
                Layout.preferredWidth: todoRefreshRow.implicitWidth + 20
                implicitHeight: 34
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colLayer1
                colBackgroundHover: Appearance.colors.colLayer1Hover
                enabled: !Todo.obsidianBusy
                onClicked: Todo.refreshObsidianSetup()

                contentItem: RowLayout {
                    id: todoRefreshRow
                    anchors.centerIn: parent
                    spacing: 5
                    MaterialSymbol {
                        text: "refresh"
                        iconSize: 16
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: Translation.tr("Refresh")
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }

            RippleButton {
                visible: Todo.useLegacyManagedNote
                    && !Todo.obsidianReady
                    && String(Config.options?.todo?.obsidian?.vaultPath ?? "").trim().length > 0
                    && String(Config.options?.todo?.obsidian?.notePath ?? "").trim().length > 0
                Layout.preferredWidth: todoInitRow.implicitWidth + 20
                implicitHeight: 34
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colLayer1
                colBackgroundHover: Appearance.colors.colLayer1Hover
                enabled: !Todo.obsidianBusy
                onClicked: Todo.initializeSection()

                contentItem: RowLayout {
                    id: todoInitRow
                    anchors.centerIn: parent
                    spacing: 5
                    MaterialSymbol {
                        text: "playlist_add"
                        iconSize: 16
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: Translation.tr("Initialize section")
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }

                StyledToolTip {
                    text: Translation.tr("Create the note if needed, then append the two Alis managed markers. Existing content is preserved.")
                }
            }

            RippleButton {
                visible: Todo.obsidianReady
                Layout.preferredWidth: todoOpenRow.implicitWidth + 20
                implicitHeight: 34
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colLayer1
                colBackgroundHover: Appearance.colors.colLayer1Hover
                onClicked: Todo.openObsidianSource()

                contentItem: RowLayout {
                    id: todoOpenRow
                    anchors.centerIn: parent
                    spacing: 5
                    MaterialSymbol {
                        text: "open_in_new"
                        iconSize: 16
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: Translation.tr("Open note")
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }

            RippleButton {
                visible: Todo.backend !== "obsidian"
                    && Todo.obsidianSetupActive
                    && Todo.obsidianReady
                    && Todo.internalItemCount > 0
                    && Todo.obsidianList.length === 0
                    && Todo.obsidianMigrationPreview === null
                Layout.preferredWidth: todoPreviewRow.implicitWidth + 20
                implicitHeight: 34
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colLayer1
                colBackgroundHover: Appearance.colors.colLayer1Hover
                enabled: !Todo.obsidianBusy && !Todo.internalPersistenceBusy
                onClicked: Todo.previewInternalToObsidian()

                contentItem: RowLayout {
                    id: todoPreviewRow
                    anchors.centerIn: parent
                    spacing: 5
                    MaterialSymbol {
                        text: "fact_check"
                        iconSize: 16
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: Translation.tr("Preview import")
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: Todo.backend !== "obsidian"
                && Todo.obsidianSetupActive
                && Todo.obsidianMigrationPreview !== null
            implicitHeight: todoMigrationPreviewColumn.implicitHeight + 20
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1

            ColumnLayout {
                id: todoMigrationPreviewColumn
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Migration preview")
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Add %1 · duplicates %2 · conflicts %3")
                        .arg(Number(Todo.obsidianMigrationPreview?.preview?.added ?? 0))
                        .arg(Number(Todo.obsidianMigrationPreview?.preview?.duplicates ?? 0))
                        .arg(Number(Todo.obsidianMigrationPreview?.preview?.conflicts ?? 0))
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.small
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: Todo.obsidianMigrationPreview?.target?.empty !== true
                    text: Translation.tr("Import blocked: target heading already has tasks.")
                    color: Appearance.colors.colError
                    font.pixelSize: Appearance.font.pixelSize.small
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RippleButton {
                        Layout.preferredWidth: todoImportRow.implicitWidth + 20
                        implicitHeight: 34
                        buttonRadius: Appearance.rounding.small
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        enabled: !Todo.obsidianBusy
                            && !Todo.internalPersistenceBusy
                            && Todo.obsidianMigrationPreview?.target?.empty === true
                            && Number(Todo.obsidianMigrationPreview?.preview?.conflicts ?? 0) === 0
                            && String(Todo.obsidianMigrationPreview?.source?.sha256 ?? "").length > 0
                        onClicked: Todo.migrateInternalToObsidian(
                            String(Todo.obsidianMigrationPreview?.source?.sha256 ?? "")
                        )

                        contentItem: RowLayout {
                            id: todoImportRow
                            anchors.centerIn: parent
                            spacing: 5
                            MaterialSymbol {
                                text: "move_to_inbox"
                                iconSize: 16
                                color: Appearance.colors.colOnPrimary
                            }
                            StyledText {
                                text: Translation.tr("Import & activate")
                                color: Appearance.colors.colOnPrimary
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                            }
                        }

                        StyledToolTip {
                            text: Translation.tr("Back up the target Markdown note, import the preserved internal Todo store into the configured heading, re-scan it, then activate only after verification succeeds.")
                        }
                    }

                    RippleButton {
                        Layout.preferredWidth: todoRepreviewRow.implicitWidth + 20
                        implicitHeight: 34
                        buttonRadius: Appearance.rounding.small
                        colBackground: Appearance.colors.colLayer1
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        enabled: !Todo.obsidianBusy && !Todo.internalPersistenceBusy
                        onClicked: Todo.previewInternalToObsidian()

                        contentItem: RowLayout {
                            id: todoRepreviewRow
                            anchors.centerIn: parent
                            spacing: 5
                            MaterialSymbol {
                                text: "refresh"
                                iconSize: 16
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                text: Translation.tr("Refresh preview")
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: Todo.backend !== "obsidian"
                && Todo.obsidianSetupActive
                && Todo.obsidianReady

            StyledText {
                Layout.fillWidth: true
                text: Todo.internalItemCount > 0
                    ? Translation.tr("Activate without importing tasks.")
                    : Translation.tr("Activate verified source.")
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.WordWrap
            }

            RippleButton {
                Layout.preferredWidth: todoActivateRow.implicitWidth + 20
                implicitHeight: 34
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colLayer1
                colBackgroundHover: Appearance.colors.colLayer1Hover
                enabled: !Todo.obsidianBusy
                onClicked: Todo.activateObsidian()

                contentItem: RowLayout {
                    id: todoActivateRow
                    anchors.centerIn: parent
                    spacing: 5
                    MaterialSymbol {
                        text: "check_circle"
                        iconSize: 16
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: Translation.tr("Use Obsidian source")
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }
        }
    }

    SettingsGroup {
        visible: root.settingsView !== "todo"
        ContentSubsection {
            title: Translation.tr("Quick Notes")
            tooltip: Translation.tr("Capture to Zettelkasten without clearing the Notepad draft.")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            StyledText {
                text: Translation.tr("Zettelkasten folder")
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
            }

            MaterialTextField {
                id: zettelkastenFolder
                objectName: "obsidianQuickNoteFolder"
                Layout.fillWidth: true
                implicitWidth: 0
                placeholderText: ""
                font.pixelSize: Appearance.font.pixelSize.small
                font.family: Appearance.font.family.monospace
                color: Appearance.colors.colOnSurface
                placeholderTextColor: Appearance.colors.colSubtext
                text: String(Config.options?.notes?.zettelkasten?.folder
                    ?? "00_Capture/03_Zettelkasten")
                background: Rectangle {
                    color: Appearance.colors.colLayer1
                    radius: Appearance.rounding.small
                    border.width: zettelkastenFolder.activeFocus ? 2 : 1
                    border.color: zettelkastenFolder.activeFocus
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colLayer0Border
                }
                onEditingFinished: {
                    const value = text.trim()
                    if (value.length > 0
                            && value !== String(Config.options?.notes?.zettelkasten?.folder
                                ?? "00_Capture/03_Zettelkasten"))
                        Config.setNestedValue("notes.zettelkasten.folder", value)
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Default Zettelkasten type")

            ConfigSelectionArray {
                Layout.fillWidth: true
                currentValue: Config.options?.notes?.zettelkasten?.defaultType ?? "Fleeting"
                onSelected: newValue =>
                    Config.setNestedValue("notes.zettelkasten.defaultType", newValue)
                options: [
                    {
                        displayName: Translation.tr("Fleeting"),
                        icon: "bolt",
                        value: "Fleeting"
                    },
                    {
                        displayName: Translation.tr("Literature"),
                        icon: "menu_book",
                        value: "Literature"
                    },
                    {
                        displayName: Translation.tr("Permanent"),
                        icon: "deployed_code",
                        value: "Permanent"
                    }
                ]
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: zettelkastenStatusRow.implicitHeight + 18
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1

            RowLayout {
                id: zettelkastenStatusRow
                anchors.fill: parent
                anchors.margins: 9
                spacing: 8

                MaterialSymbol {
                    text: Zettelkasten.ready ? "check_circle" : "warning"
                    iconSize: 18
                    color: Zettelkasten.ready
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colError
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Zettelkasten.ready
                        ? Translation.tr("Capture folder: %1").arg(Zettelkasten.folder)
                        : Translation.tr("Set the shared vault path above.")
                    color: Zettelkasten.ready
                        ? Appearance.colors.colOnLayer1
                        : Appearance.colors.colError
                    font.pixelSize: Appearance.font.pixelSize.small
                    wrapMode: Text.WrapAnywhere
                }
            }
        }
    }
}

