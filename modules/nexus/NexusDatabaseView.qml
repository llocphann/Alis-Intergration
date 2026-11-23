import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: dbRoot
    property var nexus: null
    property var settledColors: null

    property string viewMode: "table" // "table" | "board" | "gallery" | "timeline"
    property string sortKey: "title"
    property bool sortAsc: true

    color: settledColors?.colLayer0 ?? Appearance.colors.colLayer0
    radius: 12
    clip: true

    readonly property var qData: nexus?.queryResults ?? ({ "rows": [], "schemaKeys": [], "groups": [], "aggregations": ({}), "total": 0 })
    readonly property var rows: Array.isArray(qData.rows) ? qData.rows : []
    readonly property var schemaKeys: Array.isArray(qData.schemaKeys) ? qData.schemaKeys.slice(0, 6) : []

    function triggerRun(): void {
        if (!nexus)
            return;
        const wheres = whereField.text.trim().length > 0 ? whereField.text.split(";").map(s => s.trim()).filter(s => s.length > 0) : [];
        nexus.runDatabaseQuery({
            "folder": folderField.text.trim(),
            "tag": tagField.text.trim().replace(/^#+/, ""),
            "whereFilters": wheres,
            "sort": sortKey + ":" + (sortAsc ? "asc" : "desc"),
            "groupBy": groupField.text.trim(),
            "limit": 300
        });
    }

    function groupedBuckets(): var {
        const key = groupField.text.trim() || "status";
        const map = {};
        const order = [];
        for (let i = 0; i < rows.length; ++i) {
            const r = rows[i];
            const val = String(r?.frontmatter?.[key] ?? r?.[key] ?? "(None)").trim() || "(None)";
            if (!map[val]) {
                map[val] = [];
                order.push(val);
            }
            map[val].push(r);
        }
        return order.map(k => ({ "name": k, "key": key, "items": map[k] }));
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // Header & View Mode Tabs
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                text: "table_view"
                iconSize: 18
                color: dbRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
            }

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: (dbRoot.nexus?.databasePath ? dbRoot.nexus.databasePath : "Vault Database") + " · " + Number(dbRoot.qData.total ?? dbRoot.rows.length) + " rows"
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: dbRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                elide: Text.ElideRight
            }

            Repeater {
                model: [
                    { "id": "table", "label": "Table" },
                    { "id": "board", "label": "Board" },
                    { "id": "gallery", "label": "Gallery" },
                    { "id": "timeline", "label": "Timeline" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool active: dbRoot.viewMode === modelData.id
                    height: 26; width: 64; radius: 13
                    color: active
                        ? (dbRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary)
                        : (dbRoot.settledColors?.colLayer1 ?? Appearance.colors.colLayer1)
                    StyledText {
                        anchors.centerIn: parent
                        text: modelData.label
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: active ? Font.DemiBold : Font.Normal
                        color: active
                            ? (dbRoot.settledColors?.colOnPrimary ?? Appearance.colors.colOnPrimary)
                            : (dbRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1)
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dbRoot.viewMode = modelData.id }
                }
            }
        }

        // Query Builder Toolbar
        Rectangle {
            Layout.fillWidth: true
            height: 38
            radius: 8
            color: dbRoot.settledColors?.colLayer1 ?? Appearance.colors.colLayer1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8; anchors.rightMargin: 8
                spacing: 6

                TextField {
                    id: folderField
                    Layout.preferredWidth: 130; Layout.minimumWidth: 0
                    implicitHeight: 26
                    placeholderText: "Folder..."
                    color: dbRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    background: Rectangle { radius: 6; color: dbRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0 }
                }

                TextField {
                    id: tagField
                    Layout.preferredWidth: 100; Layout.minimumWidth: 0
                    implicitHeight: 26
                    placeholderText: "#tag"
                    color: dbRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    background: Rectangle { radius: 6; color: dbRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0 }
                }

                TextField {
                    id: whereField
                    Layout.fillWidth: true; Layout.minimumWidth: 80
                    implicitHeight: 26
                    placeholderText: "Filter e.g. status = active; rating >= 4"
                    color: dbRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    background: Rectangle { radius: 6; color: dbRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0 }
                    onAccepted: dbRoot.triggerRun()
                }

                TextField {
                    id: groupField
                    Layout.preferredWidth: 100; Layout.minimumWidth: 0
                    implicitHeight: 26
                    text: "status"
                    placeholderText: "Group by"
                    color: dbRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    background: Rectangle { radius: 6; color: dbRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0 }
                }

                Rectangle {
                    height: 26; width: 54; radius: 6
                    color: dbRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
                    StyledText {
                        anchors.centerIn: parent
                        text: "Run"
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: dbRoot.settledColors?.colOnPrimary ?? Appearance.colors.colOnPrimary
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dbRoot.triggerRun() }
                }

                Rectangle {
                    height: 26; width: 64; radius: 6
                    color: dbRoot.settledColors?.colSecondaryContainer ?? Appearance.colors.colSecondaryContainer
                    StyledText {
                        anchors.centerIn: parent
                        text: "+ Save"
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: dbRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!dbRoot.nexus) return;
                            const label = (tagField.text.trim() || folderField.text.trim() || "View") + " · " + dbRoot.viewMode;
                            dbRoot.nexus.saveDatabaseView({
                                "name": label,
                                "viewMode": dbRoot.viewMode,
                                "folder": folderField.text.trim(),
                                "tag": tagField.text.trim(),
                                "whereFilters": whereField.text.split(";").map(s => s.trim()).filter(Boolean),
                                "groupBy": groupField.text.trim()
                            });
                        }
                    }
                }

                Rectangle {
                    height: 26; width: 46; radius: 6
                    color: dbRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0
                    StyledText {
                        anchors.centerIn: parent
                        text: "CSV"
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: dbRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const rows = dbRoot.rows;
                            const esc = v => '"' + String(v ?? "").replace(/"/g, '""') + '"';
                            const lines = ["Title,Path,Folder,Status,Tags"];
                            for (let i = 0; i < rows.length; ++i) {
                                const r = rows[i] || {};
                                const st = r.frontmatter?.status ?? r.status ?? "";
                                lines.push([r.title, r.relPath, r.folder, st, Array.isArray(r.tags) ? r.tags.join(" ") : (r.tags ?? "")].map(esc).join(","));
                            }
                            const text = lines.join("\n");
                            if (typeof dbRoot.nexus?.copyToClipboard === "function")
                                dbRoot.nexus.copyToClipboard(text, "Copied CSV");
                            else
                                Quickshell.clipboardText = text;
                        }
                    }
                }

                Rectangle {
                    height: 26; width: 42; radius: 6
                    color: dbRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0
                    StyledText {
                        anchors.centerIn: parent
                        text: "MD"
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: dbRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const rows = dbRoot.rows;
                            const clean = v => String(v ?? "").replace(/\|/g, "\\|").replace(/\n/g, " ");
                            const lines = ["| Title | Folder | Status | Tags |", "| --- | --- | --- | --- |"];
                            for (let i = 0; i < rows.length; ++i) {
                                const r = rows[i] || {};
                                const st = r.frontmatter?.status ?? r.status ?? "";
                                lines.push("| " + [r.title || r.relPath, r.folder, st, Array.isArray(r.tags) ? r.tags.join(", ") : (r.tags ?? "")].map(clean).join(" | ") + " |");
                            }
                            const text = lines.join("\n");
                            if (typeof dbRoot.nexus?.copyToClipboard === "function")
                                dbRoot.nexus.copyToClipboard(text, "Copied Markdown");
                            else
                                Quickshell.clipboardText = text;
                        }
                    }
                }
            }
        }

        // Saved view presets strip
        RowLayout {
            visible: (dbRoot.nexus?.savedDatabaseViews?.length ?? 0) > 0
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: (dbRoot.nexus?.savedDatabaseViews ?? []).slice(0, 6)
                delegate: Rectangle {
                    required property var modelData
                    height: 22; width: Math.max(54, svLbl.implicitWidth + 16); radius: 11
                    color: dbRoot.settledColors?.colLayer1 ?? Appearance.colors.colLayer1
                    StyledText {
                        id: svLbl
                        anchors.centerIn: parent
                        text: String(modelData.name ?? "")
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: dbRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            dbRoot.viewMode = String(modelData.viewMode ?? "table");
                            folderField.text = String(modelData.folder ?? "");
                            tagField.text = String(modelData.tag ?? "");
                            whereField.text = Array.isArray(modelData.whereFilters) ? modelData.whereFilters.join("; ") : "";
                            groupField.text = String(modelData.groupBy ?? "status");
                            dbRoot.triggerRun();
                        }
                    }
                }
            }
        }

        // Main Data Views
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // 1. Table View
            ListView {
                visible: dbRoot.viewMode === "table"
                anchors.fill: parent
                clip: true
                spacing: 4
                model: dbRoot.rows
                header: Rectangle {
                    width: ListView.view.width
                    height: 28; radius: 6
                    color: dbRoot.settledColors?.colLayer1 ?? Appearance.colors.colLayer1
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 8
                        StyledText {
                            Layout.fillWidth: true
                            text: "Title"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Bold
                            color: dbRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
                        }
                        StyledText {
                            Layout.preferredWidth: 120
                            text: "Folder"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: dbRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext
                        }
                        Repeater {
                            model: dbRoot.schemaKeys.slice(0, 3)
                            delegate: StyledText {
                                required property var modelData
                                Layout.preferredWidth: 88
                                text: String(modelData)
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: dbRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }
                        }
                        Item { Layout.preferredWidth: 50 }
                    }
                }
                delegate: Rectangle {
                    id: tableRowItem
                    required property var modelData
                    width: ListView.view.width
                    height: 32; radius: 6
                    color: dbRoot.settledColors?.colLayer1 ?? Appearance.colors.colLayer1
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 8
                        StyledText {
                            Layout.fillWidth: true; Layout.minimumWidth: 0
                            text: String(tableRowItem.modelData.title ?? tableRowItem.modelData.relPath ?? "")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: dbRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.preferredWidth: 120; Layout.minimumWidth: 0
                            text: String(tableRowItem.modelData.folder ?? "")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: dbRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext
                            elide: Text.ElideLeft
                        }
                        Repeater {
                            model: dbRoot.schemaKeys.slice(0, 3)
                            delegate: StyledText {
                                required property var modelData
                                Layout.preferredWidth: 88; Layout.minimumWidth: 0
                                text: String(tableRowItem.modelData?.frontmatter?.[String(modelData)] ?? "—")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: dbRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }
                        }
                        Rectangle {
                            height: 22; width: 46; radius: 5
                            color: dbRoot.settledColors?.colSecondaryContainer ?? Appearance.colors.colSecondaryContainer
                            StyledText { anchors.centerIn: parent; text: "Split"; horizontalAlignment: Text.AlignHCenter; font.pixelSize: Appearance.font.pixelSize.smallest; color: dbRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: if (dbRoot.nexus && modelData.relPath) dbRoot.nexus.openInSecondaryPane(String(modelData.relPath))
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.rightMargin: 56
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (dbRoot.nexus && modelData.relPath) dbRoot.nexus.openFile(String(modelData.relPath), true)
                    }
                }
            }

            // 2. Kanban Board View
            ScrollView {
                visible: dbRoot.viewMode === "board"
                anchors.fill: parent
                clip: true

                RowLayout {
                    spacing: 10
                    Repeater {
                        model: dbRoot.viewMode === "board" ? dbRoot.groupedBuckets() : []
                        delegate: Rectangle {
                            required property var modelData
                            Layout.preferredWidth: 230
                            Layout.fillHeight: true
                            implicitHeight: Math.max(260, kbCol.implicitHeight + 16)
                            radius: 10
                            color: dbRoot.settledColors?.colLayer1 ?? Appearance.colors.colLayer1

                            ColumnLayout {
                                id: kbCol
                                anchors.fill: parent; anchors.margins: 8; spacing: 6
                                StyledText {
                                    Layout.fillWidth: true
                                    text: String(modelData.name) + " (" + modelData.items.length + ")"
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Bold
                                    color: dbRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
                                }
                                Repeater {
                                    model: modelData.items.slice(0, 40)
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: kbCardTxt.implicitHeight + 16
                                        radius: 8
                                        color: dbRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0
                                        StyledText {
                                            id: kbCardTxt
                                            anchors.fill: parent; anchors.margins: 8
                                            text: String(modelData.title ?? "")
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: dbRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                                            wrapMode: Text.WordWrap
                                        }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: if (dbRoot.nexus && modelData.relPath) dbRoot.nexus.openFile(String(modelData.relPath), true)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 3. Gallery View
            GridView {
                visible: dbRoot.viewMode === "gallery"
                anchors.fill: parent
                clip: true
                cellWidth: Math.max(190, Math.floor(width / 3))
                cellHeight: 112
                model: dbRoot.rows
                delegate: Item {
                    required property var modelData
                    width: GridView.view.cellWidth
                    height: GridView.view.cellHeight
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 5; radius: 10
                        color: dbRoot.settledColors?.colLayer1 ?? Appearance.colors.colLayer1
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 10; spacing: 4
                            StyledText {
                                Layout.fillWidth: true
                                text: String(modelData.title ?? "")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: dbRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                text: String(modelData.snippet ?? modelData.folder ?? "")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: dbRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext
                                wrapMode: Text.WordWrap
                                elide: Text.ElideRight
                            }
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: if (dbRoot.nexus && modelData.relPath) dbRoot.nexus.openFile(String(modelData.relPath), true)
                        }
                    }
                }
            }

            // 4. Timeline View
            ListView {
                visible: dbRoot.viewMode === "timeline"
                anchors.fill: parent
                clip: true
                spacing: 6
                model: dbRoot.rows
                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: 48; radius: 8
                    color: dbRoot.settledColors?.colLayer1 ?? Appearance.colors.colLayer1
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 10
                        Rectangle { width: 10; height: 10; radius: 5; color: dbRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary }
                        StyledText {
                            text: String(modelData.frontmatter?.date ?? modelData.frontmatter?.due ?? (modelData.mtimeSecs ? Qt.formatDate(new Date(Number(modelData.mtimeSecs) * 1000), "yyyy-MM-dd") : "Undated"))
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: dbRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
                        }
                        StyledText {
                            Layout.fillWidth: true; Layout.minimumWidth: 0
                            text: String(modelData.title ?? "")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: dbRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }
                        StyledText {
                            text: String(modelData.folder ?? "")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: dbRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext
                        }
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: if (dbRoot.nexus && modelData.relPath) dbRoot.nexus.openFile(String(modelData.relPath), true)
                    }
                }
            }
        }

        // Aggregations Summary Footer
        Rectangle {
            Layout.fillWidth: true
            height: 28; radius: 6
            color: dbRoot.settledColors?.colLayer1 ?? Appearance.colors.colLayer1
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left; anchors.leftMargin: 10
                anchors.right: parent.right; anchors.rightMargin: 10
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: dbRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext
                text: {
                    const agg = dbRoot.qData.aggregations || {};
                    const parts = ["Rows: " + dbRoot.rows.length];
                    const keys = Object.keys(agg).slice(0, 3);
                    for (let i = 0; i < keys.length; ++i) {
                        const a = agg[keys[i]];
                        parts.push(keys[i] + " avg " + Number(a.avg || 0).toFixed(1) + " (sum " + Number(a.sum || 0).toFixed(1) + ")");
                    }
                    return parts.join("  ·  ");
                }
            }
        }
    }
}
