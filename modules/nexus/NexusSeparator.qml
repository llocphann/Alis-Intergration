pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common

// 100% parity with Obsidian .obsidian/snippets/03_Compatibility.css decorative <hr> separator
Item {
    id: root
    objectName: "nexusSeparator"

    property color accentColor: Appearance.colors.colPrimary
    property color mutedColor: Appearance.colors.colSubtext
    property real maxWidth: 768

    Layout.fillWidth: true
    Layout.preferredHeight: 34
    implicitHeight: 34

    readonly property color _inkColor: Qt.rgba(root.mutedColor.r, root.mutedColor.g, root.mutedColor.b, 0.58)
    readonly property color _accentInkMix: {
        const a = 0.68 + 0.32 * 0.58;
        const r = (0.68 * root.accentColor.r + 0.32 * 0.58 * root.mutedColor.r) / a;
        const g = (0.68 * root.accentColor.g + 0.32 * 0.58 * root.mutedColor.g) / a;
        const b = (0.68 * root.accentColor.b + 0.32 * 0.58 * root.mutedColor.b) / a;
        return Qt.rgba(r, g, b, a);
    }
    readonly property color _diamondBorder: Qt.rgba(
        root.accentColor.r * 0.76 + root.mutedColor.r * 0.24,
        root.accentColor.g * 0.76 + root.mutedColor.g * 0.24,
        root.accentColor.b * 0.76 + root.mutedColor.b * 0.24,
        1.0
    )

    // Centered 48rem max-width ornament stage
    Item {
        id: stage
        anchors.centerIn: parent
        width: Math.min(root.width, root.maxWidth)
        height: 34

        // Fading 1px horizontal hairline with center gap (46%..54%)
        Rectangle {
            id: hairline
            anchors.centerIn: parent
            width: parent.width
            height: 1
            antialiasing: true
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.00; color: Qt.rgba(root.mutedColor.r, root.mutedColor.g, root.mutedColor.b, 0.0) }
                GradientStop { position: 0.12; color: root._inkColor }
                GradientStop { position: 0.39; color: root._accentInkMix }
                GradientStop { position: 0.46; color: Qt.rgba(root._accentInkMix.r, root._accentInkMix.g, root._accentInkMix.b, 0.0) }
                GradientStop { position: 0.54; color: Qt.rgba(root._accentInkMix.r, root._accentInkMix.g, root._accentInkMix.b, 0.0) }
                GradientStop { position: 0.61; color: root._accentInkMix }
                GradientStop { position: 0.88; color: root._inkColor }
                GradientStop { position: 1.00; color: Qt.rgba(root.mutedColor.r, root.mutedColor.g, root.mutedColor.b, 0.0) }
            }
        }

        // Outer halo: box-shadow 0 0 0 4px color-mix(accent 10%, transparent) — strictly outside the 14x14 diamond
        Rectangle {
            anchors.centerIn: parent
            width: 22
            height: 22
            radius: 7
            rotation: 45
            antialiasing: true
            color: "transparent"
            border.width: 4
            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)
        }

        // 14x14 rotated 45deg diamond frame + inner 3px halo (inset 0 0 0 3px accent @ 9%)
        Rectangle {
            id: diamondFrame
            anchors.centerIn: parent
            width: 14
            height: 14
            radius: 3
            rotation: 45
            antialiasing: true
            color: "transparent"
            border.width: 1
            border.color: root._diamondBorder

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: 2
                antialiasing: true
                color: "transparent"
                border.width: 3
                border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.09)
            }
        }

        // Center 4px accent dot
        Rectangle {
            anchors.centerIn: parent
            width: 4
            height: 4
            radius: 2
            antialiasing: true
            color: root.accentColor
        }

        // Flanking inner 2px dots at -23px and +23px (accent @ 56%)
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: -23
            width: 2
            height: 2
            radius: 1
            antialiasing: true
            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.56)
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: 23
            width: 2
            height: 2
            radius: 1
            antialiasing: true
            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.56)
        }

        // Flanking outer 1px dots at -35px and +35px (4px - 2*1.5px spread = 1px, muted @ 45%)
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: -35
            width: 1
            height: 1
            radius: 0.5
            antialiasing: true
            color: Qt.rgba(root.mutedColor.r, root.mutedColor.g, root.mutedColor.b, 0.45)
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: 35
            width: 1
            height: 1
            radius: 0.5
            antialiasing: true
            color: Qt.rgba(root.mutedColor.r, root.mutedColor.g, root.mutedColor.b, 0.45)
        }
    }
}
