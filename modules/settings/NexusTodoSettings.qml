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
    objectName: "alisIntergrationNexusTodoSettings"
    settingsTaskSection: "nexus"
    expanded: true
    icon: "checklist"
    title: root.settingsView === "todo" ? Translation.tr("To-do")
        : root.settingsView === "quicknotes" ? Translation.tr("Quick Notes")
        : Translation.tr("To-do & Quick Notes")

    GridLayout {
        Layout.fillWidth: true
        columns: root.settingsView === "all" && width >= 620 ? 2 : 1
        columnSpacing: 12
        rowSpacing: 10

        SettingsGroup {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            visible: root.settingsView !== "quicknotes"

            ContentSubsection {
                title: Translation.tr("To-do")
                tooltip: Translation.tr("Choose the task store; your Alis backup is preserved.")

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialSymbol {
                        text: Todo.backend === "nexus" ? "description" : "database"
                        iconSize: 20
                        color: Appearance.colors.colPrimary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: Todo.backend === "nexus"
                                ? Translation.tr("Nexus is canonical")
                                : Translation.tr("Alis internal Todo is canonical")
                            color: Appearance.colors.colOnSurface
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                        }
                    }

                    RippleButton {
                        visible: Todo.backend !== "nexus" && !Todo.nexusSetupActive
                        Layout.preferredWidth: todoPrepareRow.implicitWidth + 20
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.small
                        colBackground: Appearance.colors.colLayer1
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        onClicked: Todo.beginNexusSetup()

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
                                text: Translation.tr("Prepare Nexus")
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                    }

                    RippleButton {
                        visible: Todo.backend !== "nexus" && Todo.nexusSetupActive
                        Layout.preferredWidth: todoCancelSetupRow.implicitWidth + 20
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.small
                        colBackground: Appearance.colors.colLayer1
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        onClicked: Todo.cancelNexusSetup()

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
                        visible: Todo.backend === "nexus"
                        Layout.preferredWidth: todoRollbackRow.implicitWidth + 20
                        implicitHeight: 32
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

            ConfigRow {
                uniform: false

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 2
                    spacing: 4

                    StyledText {
                        text: Translation.tr("Note path pattern")
                        color: Appearance.colors.colOnSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    MaterialTextField {
                        id: todoMarkdownNotePattern
                        objectName: "nexusTodoNotePattern"
                        Layout.fillWidth: true
                        implicitWidth: 0
                        placeholderText: ""
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colOnSurface
                        text: {
                            const folder = String(Config.options?.todo?.nexus?.dailyNote?.folder
                                ?? "00_Capture/01_Journal").trim().replace(/^\/+|\/+$/g, "")
                            let format = String(Config.options?.todo?.nexus?.dailyNote?.format
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
                            Config.setNestedValue("todo.nexus.dailyNote.folder", folder)
                            Config.setNestedValue("todo.nexus.dailyNote.format", format)
                            if (Todo.backend !== "nexus"
                                    && Todo.nexusSourceMode !== "markdown-note")
                                Config.setNestedValue("todo.nexus.sourceMode", "markdown-note")
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 4

                    StyledText {
                        text: Translation.tr("Heading")
                        color: Appearance.colors.colOnSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    MaterialTextField {
                        id: todoMarkdownHeading
                        objectName: "nexusTodoHeading"
                        Layout.fillWidth: true
                        implicitWidth: 0
                        placeholderText: ""
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurface
                        text: String(Config.options?.todo?.nexus?.dailyNote?.plannerHeading
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
                                    && value !== String(Config.options?.todo?.nexus?.dailyNote?.plannerHeading
                                        ?? "Tasks"))
                                Config.setNestedValue("todo.nexus.dailyNote.plannerHeading", value)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ConfigSpinBox {
                    Layout.fillWidth: true
                    icon: "tag"
                    text: Translation.tr("Heading level")
                    value: Config.options?.todo?.nexus?.dailyNote?.plannerHeadingLevel ?? 2
                    from: 1
                    to: 6
                    stepSize: 1
                    onValueChanged:
                        Config.setNestedValue("todo.nexus.dailyNote.plannerHeadingLevel", value)
                }

                ConfigSpinBox {
                    Layout.fillWidth: true
                    icon: "schedule"
                    text: Translation.tr("Default duration (min)")
                    value: Config.options?.todo?.nexus?.dailyNote?.defaultDurationMinutes ?? 30
                    from: 5
                    to: 240
                    stepSize: 5
                    onValueChanged:
                        Config.setNestedValue("todo.nexus.dailyNote.defaultDurationMinutes", value)
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: todoNexusStatusColumn.implicitHeight + 16
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1

                ColumnLayout {
                    id: todoNexusStatusColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 8
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialSymbol {
                            text: {
                                if (Todo.backend !== "nexus" && !Todo.nexusSetupActive)
                                    return "database"
                                if (Todo.nexusErrorCode.length > 0)
                                    return "error"
                                if (Todo.nexusCapabilities?.richMutationAvailable === true)
                                    return "verified"
                                if (Todo.nexusReady)
                                    return "sync"
                                return "hourglass"
                            }
                            iconSize: 18
                            color: Todo.nexusErrorCode.length > 0
                                ? Appearance.colors.colError
                                : Appearance.colors.colPrimary
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                if (Todo.backend !== "nexus" && !Todo.nexusSetupActive)
                                    return Translation.tr("Nexus setup is inactive")
                                if (Todo.nexusErrorMessage.length > 0)
                                    return Todo.nexusErrorMessage
                                if (Todo.nexusReady)
                                    return Translation.tr("Markdown task source ready")
                                return Translation.tr("Waiting for the configured Markdown note and heading")
                            }
                            color: Todo.nexusErrorCode.length > 0
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
                visible: Todo.backend === "nexus" || Todo.nexusSetupActive

                RippleButton {
                    Layout.preferredWidth: todoRefreshRow.implicitWidth + 20
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    enabled: !Todo.nexusBusy
                    onClicked: Todo.refreshNexusSetup()

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
                        && !Todo.nexusReady
                        && String(Config.options?.todo?.nexus?.vaultPath ?? "").trim().length > 0
                        && String(Config.options?.todo?.nexus?.notePath ?? "").trim().length > 0
                    Layout.preferredWidth: todoInitRow.implicitWidth + 20
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    enabled: !Todo.nexusBusy
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
                }

                RippleButton {
                    visible: Todo.nexusReady
                    Layout.preferredWidth: todoOpenRow.implicitWidth + 20
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    onClicked: Todo.openNexusSource()

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
                    visible: Todo.backend !== "nexus"
                        && Todo.nexusSetupActive
                        && Todo.nexusReady
                        && Todo.internalItemCount > 0
                        && Todo.nexusList.length === 0
                        && Todo.nexusMigrationPreview === null
                    Layout.preferredWidth: todoPreviewRow.implicitWidth + 20
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    enabled: !Todo.nexusBusy && !Todo.internalPersistenceBusy
                    onClicked: Todo.previewInternalToNexus()

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
                visible: Todo.backend !== "nexus"
                    && Todo.nexusSetupActive
                    && Todo.nexusMigrationPreview !== null
                implicitHeight: todoMigrationPreviewColumn.implicitHeight + 16
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1

                ColumnLayout {
                    id: todoMigrationPreviewColumn
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Migration preview") + " · "
                            + Translation.tr("Add %1 · duplicates %2 · conflicts %3")
                                .arg(Number(Todo.nexusMigrationPreview?.preview?.added ?? 0))
                                .arg(Number(Todo.nexusMigrationPreview?.preview?.duplicates ?? 0))
                                .arg(Number(Todo.nexusMigrationPreview?.preview?.conflicts ?? 0))
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                        wrapMode: Text.WordWrap
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: Todo.nexusMigrationPreview?.target?.empty !== true
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
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.small
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            enabled: !Todo.nexusBusy
                                && !Todo.internalPersistenceBusy
                                && Todo.nexusMigrationPreview?.target?.empty === true
                                && Number(Todo.nexusMigrationPreview?.preview?.conflicts ?? 0) === 0
                                && String(Todo.nexusMigrationPreview?.source?.sha256 ?? "").length > 0
                            onClicked: Todo.migrateInternalToNexus(
                                String(Todo.nexusMigrationPreview?.source?.sha256 ?? "")
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
                        }

                        RippleButton {
                            Layout.preferredWidth: todoRepreviewRow.implicitWidth + 20
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.small
                            colBackground: Appearance.colors.colLayer1
                            colBackgroundHover: Appearance.colors.colLayer1Hover
                            enabled: !Todo.nexusBusy && !Todo.internalPersistenceBusy
                            onClicked: Todo.previewInternalToNexus()

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
                visible: Todo.backend !== "nexus"
                    && Todo.nexusSetupActive
                    && Todo.nexusReady

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
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    enabled: !Todo.nexusBusy
                    onClicked: Todo.activateNexus()

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
                            text: Translation.tr("Use Nexus source")
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                }
            }
        }

        SettingsGroup {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            visible: root.settingsView !== "todo"

            ContentSubsection {
                title: Translation.tr("Quick Notes")
                tooltip: Translation.tr("Capture to Zettelkasten without clearing the Notepad draft.")
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    text: Translation.tr("Zettelkasten folder")
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.small
                }

                MaterialTextField {
                    id: zettelkastenFolder
                    objectName: "nexusQuickNoteFolder"
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
                implicitHeight: zettelkastenStatusRow.implicitHeight + 16
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1

                RowLayout {
                    id: zettelkastenStatusRow
                    anchors.fill: parent
                    anchors.margins: 8
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
}
