import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: propRoot
    property var nexus: null
    property var settledColors: null

    readonly property var doc: nexus?.currentDoc ?? null
    readonly property var fmObj: (doc && doc.frontmatter && typeof doc.frontmatter === "object") ? doc.frontmatter : ({})
    readonly property var fmKeys: Object.keys(fmObj)
    property bool expanded: Boolean(nexus?.propertiesPanelExpanded ?? false)
    property string newKey: ""
    property string newVal: ""
    property string newSupertag: ""

    visible: doc !== null && String(doc.category ?? "") === "markdown"
    Layout.fillWidth: true
    implicitHeight: propCol.implicitHeight + 16
    radius: 10
    color: settledColors?.colLayer1 ?? Appearance.colors.colLayer1

    function inferType(key: string, val): string {
        const k = String(key ?? "").toLowerCase();
        if (k === "tags" || k === "aliases" || Array.isArray(val))
            return "list";
        if (typeof val === "boolean" || val === "true" || val === "false")
            return "bool";
        if (k === "date" || k === "due" || k === "created" || k === "updated" || /^\d{4}-\d{2}-\d{2}/.test(String(val ?? "")))
            return "date";
        if (k === "rating" || k === "score")
            return "rating";
        if (k === "url" || k === "link" || /^https?:\/\//.test(String(val ?? "")))
            return "url";
        if (typeof val === "number")
            return "number";
        return "text";
    }

    function updateField(key: string, val): void {
        if (!nexus || !key)
            return;
        const patch = {};
        patch[key] = val;
        nexus.updateNoteFrontmatter(patch);
    }

    ColumnLayout {
        id: propCol
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                text: propRoot.expanded ? "expand_more" : "chevron_right"
                iconSize: 16
                color: propRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext
            }

            StyledText {
                text: "Properties (" + propRoot.fmKeys.length + ")"
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: propRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
            }

            Item { Layout.fillWidth: true }

            // Quick Supertag badge buttons from user schema
            Repeater {
                model: Object.keys(propRoot.nexus?.supertagSchemas ?? ({})).slice(0, 4)
                delegate: Rectangle {
                    required property var modelData
                    height: 22
                    width: Math.max(48, stTxt.implicitWidth + 14)
                    radius: 11
                    color: propRoot.settledColors?.colSecondaryContainer ?? Appearance.colors.colSecondaryContainer
                    StyledText {
                        id: stTxt
                        anchors.centerIn: parent
                        text: "#" + String(modelData)
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: propRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (propRoot.nexus)
                                propRoot.nexus.applySupertag(propRoot.nexus.currentPath, String(modelData));
                        }
                    }
                }
            }

            Rectangle {
                height: 22
                width: 64
                radius: 6
                color: propRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0
                StyledText {
                    anchors.centerIn: parent
                    text: propRoot.expanded ? "Collapse" : "Expand"
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: propRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (propRoot.nexus)
                            propRoot.nexus.propertiesPanelExpanded = !propRoot.nexus.propertiesPanelExpanded;
                    }
                }
            }
        }

        ColumnLayout {
            visible: propRoot.expanded
            Layout.fillWidth: true
            spacing: 5

            Repeater {
                model: propRoot.fmKeys
                delegate: RowLayout {
                    id: propRow
                    required property var modelData
                    readonly property string kName: String(modelData)
                    readonly property var rawVal: propRoot.fmObj[kName]
                    readonly property string fType: propRoot.inferType(kName, rawVal)

                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        Layout.preferredWidth: 110
                        Layout.minimumWidth: 0
                        text: propRow.kName
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.monospace
                        color: propRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }

                    // Checkbox boolean editor
                    Rectangle {
                        visible: propRow.fType === "bool"
                        height: 24; width: 64; radius: 6
                        color: (propRow.rawVal === true || String(propRow.rawVal) === "true")
                            ? (propRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary)
                            : (propRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0)
                        StyledText {
                            anchors.centerIn: parent
                            text: (propRow.rawVal === true || String(propRow.rawVal) === "true") ? "true" : "false"
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: (propRow.rawVal === true || String(propRow.rawVal) === "true")
                                ? (propRoot.settledColors?.colOnPrimary ?? Appearance.colors.colOnPrimary)
                                : (propRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1)
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const nextB = !(propRow.rawVal === true || String(propRow.rawVal) === "true");
                                propRoot.updateField(propRow.kName, nextB);
                            }
                        }
                    }

                    // Rating clickable dots/stars
                    RowLayout {
                        visible: propRow.fType === "rating"
                        spacing: 3
                        Repeater {
                            model: 5
                            delegate: MaterialSymbol {
                                required property int index
                                readonly property int curScore: Math.round(Number(propRow.rawVal) || 0)
                                text: "star"
                                iconSize: 16
                                fill: (index + 1) <= curScore ? 1 : 0
                                color: (index + 1) <= curScore
                                    ? (propRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary)
                                    : (propRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext)
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: propRoot.updateField(propRow.kName, String(index + 1))
                                }
                            }
                        }
                    }

                    // List / Tags display + inline editor
                    TextField {
                        visible: propRow.fType !== "bool"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        implicitHeight: 26
                        text: Array.isArray(propRow.rawVal) ? propRow.rawVal.join(", ") : String(propRow.rawVal ?? "")
                        color: propRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        background: Rectangle {
                            radius: 6
                            color: propRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0
                        }
                        onEditingFinished: {
                            const txt = text.trim();
                            if (propRow.fType === "list") {
                                const arr = txt ? txt.split(",").map(s => s.trim()).filter(s => s.length > 0) : [];
                                propRoot.updateField(propRow.kName, arr);
                            } else {
                                propRoot.updateField(propRow.kName, txt);
                            }
                        }
                    }
                }
            }

            // Add new property row
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                TextField {
                    id: addPropKeyField
                    Layout.preferredWidth: 110
                    Layout.minimumWidth: 0
                    implicitHeight: 26
                    placeholderText: "key"
                    color: propRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    background: Rectangle { radius: 6; color: propRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0 }
                }

                TextField {
                    id: addPropValField
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    implicitHeight: 26
                    placeholderText: "value (e.g. active, 2026-11-22)"
                    color: propRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    background: Rectangle { radius: 6; color: propRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0 }
                }

                Rectangle {
                    height: 26; width: 54; radius: 6
                    color: propRoot.settledColors?.colSecondaryContainer ?? Appearance.colors.colSecondaryContainer
                    StyledText {
                        anchors.centerIn: parent
                        text: "+ Prop"
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: propRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const k = addPropKeyField.text.trim();
                            const v = addPropValField.text.trim();
                            if (!k) return;
                            propRoot.updateField(k, v);
                            addPropKeyField.text = "";
                            addPropValField.text = "";
                        }
                    }
                }
            }

            // Apply / save supertag template row
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                TextField {
                    id: supertagInput
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    implicitHeight: 26
                    placeholderText: "Supertag (#tag) to save or apply schema (status, rating, priority)..."
                    color: propRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    background: Rectangle { radius: 6; color: propRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0 }
                }

                Rectangle {
                    height: 26; width: 92; radius: 6
                    color: propRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0
                    StyledText {
                        anchors.centerIn: parent
                        text: "Save Schema"
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: propRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const tag = supertagInput.text.trim().replace(/^#+/, "");
                            if (!tag || !propRoot.nexus) return;
                            const fields = propRoot.fmKeys
                                .filter(k => k !== "tags" && k !== "aliases")
                                .map(k => ({ "key": k, "type": propRoot.inferType(k, propRoot.fmObj[k]), "defaultVal": String(propRoot.fmObj[k] ?? "") }));
                            propRoot.nexus.saveSupertagSchema(tag, fields.length > 0 ? fields : [
                                { "key": "status", "type": "text", "defaultVal": "active" },
                                { "key": "priority", "type": "text", "defaultVal": "medium" },
                                { "key": "rating", "type": "rating", "defaultVal": "3" }
                            ]);
                        }
                    }
                }

                Rectangle {
                    height: 26; width: 64; radius: 6
                    color: propRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
                    StyledText {
                        anchors.centerIn: parent
                        text: "Apply"
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: propRoot.settledColors?.colOnPrimary ?? Appearance.colors.colOnPrimary
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const tag = supertagInput.text.trim().replace(/^#+/, "");
                            if (!tag || !propRoot.nexus) return;
                            propRoot.nexus.applySupertag(propRoot.nexus.currentPath, tag);
                            supertagInput.text = "";
                        }
                    }
                }
            }
        }
    }
}
