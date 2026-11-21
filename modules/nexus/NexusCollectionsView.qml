import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs
import qs.services as HostServices
import qs.modules.common
import qs.modules.common.widgets
import "NexusExerciseAnatomyData.js" as ExerciseAnatomyData

ColumnLayout {
    id: collectionViewRoot
    objectName: "nexusCollectionView"
    required property var workspace
    readonly property var root: workspace
    readonly property var settledColors: workspace ? workspace.settledColors : null
    property alias collectionFilterField: nexusCollectionFilterField
    property alias newEntryInput: newCollectionEntryInput
    anchors.fill: parent
    spacing: 12

    property string newEntryTitleDraft: ""
    property string viewMode: "cards"
    property string financeSubTab: "transactions"

    readonly property var activeCollectionMeta: {
        const cid = String(root.nexus?.activeCollection ?? "movies").toLowerCase();
        if (cid === "tvseries" || cid === "tv")
            return { "id": "tvseries", "title": "TV-Series Tracker", "icon": "live_tv", "accent": "#ff9e64", "placeholder": "New TV series title...", "groupIndex": "02", "groupKicker": "TV SERIES", "groupSub": "EPISODIC STORIES" };
        if (cid === "games")
            return { "id": "games", "title": "Games Library", "icon": "sports_esports", "accent": "#73daca", "placeholder": "New game title...", "groupIndex": "01", "groupKicker": "GAMES", "groupSub": "PLAYED & BACKLOG" };
        if (cid === "books")
            return { "id": "books", "title": "Books & Reading Library", "icon": "menu_book", "accent": "#c0caf5", "placeholder": "New book title...", "groupIndex": "01", "groupKicker": "BOOKS", "groupSub": "READING ARCHIVE" };
        if (cid === "recipes")
            return { "id": "recipes", "title": "Cooking & Recipes", "icon": "restaurant", "accent": "#e0af68", "placeholder": "New recipe title...", "groupIndex": "01", "groupKicker": "FOOD & DRINKS", "groupSub": "RECIPE CARDS" };
        if (cid === "exercises")
            return { "id": "exercises", "title": "Gym & Calisthenics Exercises", "icon": "fitness_center", "accent": "#9ece6a", "placeholder": "New exercise title...", "groupIndex": "01", "groupKicker": "BODYBUILDING", "groupSub": "EXERCISE ATLAS" };
        if (cid === "places")
            return { "id": "places", "title": "Places & Coordinates", "icon": "place", "accent": String(settledColors.colTertiary ?? settledColors.colPrimary), "placeholder": "New place title...", "groupIndex": "01", "groupKicker": "PLACES", "groupSub": "VISITED & SAVED" };
        if (cid === "contacts")
            return { "id": "contacts", "title": "Contact Tracker", "icon": "contacts", "accent": "#f2cdcd", "placeholder": "New contact name...", "groupIndex": "01", "groupKicker": "CONTACTS", "groupSub": "PEOPLE DIRECTORY" };
        if (cid === "websites")
            return { "id": "websites", "title": "Onion Web-Sites Directory", "icon": "language", "accent": "#2ac3de", "placeholder": "New website entry...", "groupIndex": "01", "groupKicker": "WEB-SITES", "groupSub": "CURATED LINKS" };
        if (cid === "cornell")
            return { "id": "cornell", "title": "Cornell Study Notes", "icon": "school", "accent": "#e0af68", "placeholder": "New Cornell study note...", "groupIndex": "01", "groupKicker": "CORNELL", "groupSub": "STUDY NOTES" };
        if (cid === "zettelkasten")
            return { "id": "zettelkasten", "title": "Zettelkasten Knowledge Cards", "icon": "psychology", "accent": "#9ece6a", "placeholder": "New Zettelkasten note...", "groupIndex": "01", "groupKicker": "ZETTELKASTEN", "groupSub": "ATOMIC NOTES" };
        if (cid === "finance")
            return { "id": "finance", "title": "Finance & Ledger", "icon": "account_balance_wallet", "accent": "#7dcfff", "placeholder": "New finance note...", "groupIndex": "01", "groupKicker": "FINANCE", "groupSub": "LEDGER" };
        if (cid === "clippings")
            return { "id": "clippings", "title": "Web Clippings Archive", "icon": "bookmark", "accent": "#a6adc8", "placeholder": "New clipping title...", "groupIndex": "01", "groupKicker": "CLIPPINGS", "groupSub": "WEB ARCHIVE" };
        return { "id": "movies", "title": "Movies Tracker", "icon": "movie", "accent": "#80b8c8", "placeholder": "New movie title...", "groupIndex": "01", "groupKicker": "MOVIES", "groupSub": "FEATURE FILMS" };
    }

    readonly property var filteredCollectionItems: {
        const cid = String(root.nexus?.activeCollection ?? "movies").toLowerCase();
        let all = root.nexus?.collections?.[cid] ?? (cid === "tvseries" ? (root.nexus?.collections?.tvSeries ?? []) : []);
        if (cid === "finance") {
            const fs = root.nexus?.financeSummary ?? {};
            const tab = collectionViewRoot.financeSubTab;
            if (tab === "accounts" && Array.isArray(fs.accounts) && fs.accounts.length > 0)
                all = fs.accounts;
            else if (tab === "subscriptions" && Array.isArray(fs.subscriptions) && fs.subscriptions.length > 0)
                all = fs.subscriptions;
            else if (tab === "transactions" && Array.isArray(fs.transactions) && fs.transactions.length > 0)
                all = fs.transactions;
            else if (tab === "all") {
                const combined = []
                    .concat(Array.isArray(fs.transactions) ? fs.transactions : [])
                    .concat(Array.isArray(fs.accounts) ? fs.accounts : [])
                    .concat(Array.isArray(fs.subscriptions) ? fs.subscriptions : []);
                if (combined.length > 0)
                    all = combined;
            }
        }
        const q = String(root.nexus?.collectionFilterQuery ?? "").trim().toLowerCase();
        if (!q)
            return all;
        const out = [];
        for (let i = 0; i < all.length; ++i) {
            const it = all[i];
            const hay = (
                String(it.title ?? it.name ?? "") + " " +
                String(it.description ?? "") + " " +
                String(it.merchant ?? "") + " " +
                String(it.account ?? "") + " " +
                String(it.txType ?? it.type ?? "") + " " +
                String(it.zettelId ?? "") + " " +
                String(it.zettelType ?? "") + " " +
                String(it.genre ?? "") + " " +
                String(it.director ?? "") + " " +
                String(it.actors ?? "") + " " +
                String(it.category ?? "") + " " +
                String(it.muscleGroup ?? "") + " " +
                String(it.secondaryMuscles ?? "") + " " +
                String(it.equipment ?? "") + " " +
                String(it.level ?? "") + " " +
                String(it.force ?? "") + " " +
                String(it.mechanic ?? "") + " " +
                String(it.plot ?? "") + " " +
                String(it.status ?? "") + " " +
                String(it.location ?? "") + " " +
                String(it.url ?? "") + " " +
                (Array.isArray(it.tags) ? it.tags.join(" ") : "")
            ).toLowerCase();
            if (hay.indexOf(q) !== -1)
                out.push(it);
        }
        return out;
    }

    function _formatMoney(rawVal, currency): string {
        const n = Number(rawVal);
        const cur = String(currency ?? "").trim();
        if (!Number.isFinite(n))
            return String(rawVal ?? "0") + (cur ? (" " + cur) : "");
        const abs = Math.abs(n);
        const fixed = Math.abs(abs - Math.round(abs)) < 0.005 ? Math.round(abs).toString() : abs.toFixed(2);
        const parts = fixed.split(".");
        parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",");
        const formatted = parts.join(".");
        const sign = n < 0 ? "-" : "";
        if (cur === "$" || cur === "USD")
            return sign + "$" + formatted;
        if (cur === "€" || cur === "EUR")
            return sign + "€" + formatted;
        return sign + formatted + (cur.length > 0 ? (" " + cur) : "");
    }

    function _cleanExcerpt(raw): string {
        let s = String(raw ?? "");
        s = s.replace(/!\[\[[^\]]+\]\]/g, "");
        s = s.replace(/!\[[^\]]*\]\([^)]+\)/g, "");
        s = s.replace(/\[\[([^\]|]+)\|([^\]]+)\]\]/g, "$2");
        s = s.replace(/\[\[([^\]]+)\]\]/g, "$1");
        s = s.replace(/\[([^\]]+)\]\([^)]+\)/g, "$1");
        s = s.replace(/^#+\s*/gm, "");
        s = s.replace(/[*_`~]/g, "");
        s = s.replace(/\s+/g, " ").trim();
        return s;
    }

    function _placeCoordinates(item): string {
        if (!item || item.hasCoordinates === false)
            return "";
        const lat = item.lat ?? item.latitude;
        const lon = item.lon ?? item.longitude;
        if (lat === null || lat === undefined || lon === null || lon === undefined
                || String(lat).trim() === "" || String(lon).trim() === ""
                || !Number.isFinite(Number(lat)) || !Number.isFinite(Number(lon)))
            return "";
        return String(lat) + ", " + String(lon);
    }

    function _starsForScore(rawScore): string {
        const num = parseFloat(String(rawScore ?? "0").replace(/[^0-9.]/g, ""));
        if (!Number.isFinite(num) || num <= 0)
            return "☆☆☆☆☆";
        const five = num > 5.0 ? Math.round(num / 2.0) : Math.round(num);
        const clamped = Math.max(1, Math.min(5, five));
        return "★".repeat(clamped) + "☆".repeat(5 - clamped);
    }

    // Top Collection Switcher Tabs
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        MaterialSymbol {
            text: collectionViewRoot.activeCollectionMeta.icon
            iconSize: 22
            color: collectionViewRoot.activeCollectionMeta.accent
        }

        StyledText {
            text: collectionViewRoot.activeCollectionMeta.title
            font.pixelSize: 20
            font.weight: Font.Bold
            color: settledColors.colOnLayer1
        }

        Rectangle {
            height: 22
            width: activeCollCountLabel.implicitWidth + 14
            radius: 11
            color: settledColors.colLayer0
            border.width: 1
            border.color: collectionViewRoot.activeCollectionMeta.accent

            StyledText {
                id: activeCollCountLabel
                anchors.centerIn: parent
                text: String(collectionViewRoot.filteredCollectionItems.length) + " entries"
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: collectionViewRoot.activeCollectionMeta.accent
            }
        }

        Rectangle {
            id: collExercisesTrackerBtn
            objectName: "nexusCollectionOpenExercisesTrackerButton"
            visible: collectionViewRoot.activeCollectionMeta.id === "exercises"
            height: 24
            width: collExBtnRow.implicitWidth + 16
            radius: 12
            color: collExBtnMouse.containsMouse ? collectionViewRoot.activeCollectionMeta.accent : settledColors.colLayer0
            border.width: 1
            border.color: collectionViewRoot.activeCollectionMeta.accent

            Row {
                id: collExBtnRow
                anchors.centerIn: parent
                spacing: 5

                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "monitoring"
                    iconSize: 14
                    color: collExBtnMouse.containsMouse ? settledColors.colLayer0 : collectionViewRoot.activeCollectionMeta.accent
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Workout Tracker"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: collExBtnMouse.containsMouse ? settledColors.colLayer0 : collectionViewRoot.activeCollectionMeta.accent
                }
            }

            MouseArea {
                id: collExBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openExercisesTracker("")
            }
        }

        Flickable {
            id: collectionTabsFlickable
            objectName: "nexusCollectionTabsFlickable"
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick
            contentWidth: collectionTabsRow.implicitWidth
            contentHeight: height

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    if (collectionTabsFlickable.contentWidth <= collectionTabsFlickable.width)
                        return;
                    const delta = Math.abs(event.angleDelta.x) > Math.abs(event.angleDelta.y)
                        ? event.angleDelta.x
                        : event.angleDelta.y;
                    const maxX = Math.max(0, collectionTabsFlickable.contentWidth - collectionTabsFlickable.width);
                    collectionTabsFlickable.contentX = Math.max(0, Math.min(maxX, collectionTabsFlickable.contentX - delta * 0.6));
                    event.accepted = true;
                }
            }

            Row {
                id: collectionTabsRow
                objectName: "nexusCollectionTabsRow"
                x: Math.max(0, collectionTabsFlickable.width - implicitWidth)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Repeater {
                    model: [
                        { "id": "movies", "label": "Movies", "accent": "#80b8c8" },
                        { "id": "tvseries", "label": "TV-Series", "accent": "#ff9e64" },
                        { "id": "games", "label": "Games", "accent": "#73daca" },
                        { "id": "books", "label": "Books", "accent": "#c0caf5" },
                        { "id": "recipes", "label": "Recipes", "accent": "#e0af68" },
                        { "id": "exercises", "label": "Exercises", "accent": "#9ece6a" },
                        { "id": "places", "label": "Places", "accent": String(settledColors.colTertiary ?? settledColors.colPrimary) },
                        { "id": "contacts", "label": "Contacts", "accent": "#f2cdcd" },
                        { "id": "websites", "label": "Web-Sites", "accent": "#2ac3de" },
                        { "id": "cornell", "label": "Cornell", "accent": "#e0af68" },
                        { "id": "zettelkasten", "label": "ZK", "accent": "#9ece6a" },
                        { "id": "finance", "label": "Finance", "accent": "#7dcfff" },
                        { "id": "clippings", "label": "Clippings", "accent": "#a6adc8" }
                    ]
                    delegate: Rectangle {
                        id: collTabDelegate
                        required property var modelData
                        objectName: "nexusCollectionTab_" + modelData.id
                        readonly property bool isCurrent: String(root.nexus?.activeCollection ?? "movies").toLowerCase() === modelData.id
                        height: 24
                        width: collTabText.implicitWidth + 12
                        radius: 6
                        color: isCurrent ? settledColors.colSecondaryContainer : settledColors.colLayer0
                        border.width: 1
                        border.color: isCurrent ? modelData.accent : settledColors.colLayer0Border

                        onIsCurrentChanged: {
                            if (isCurrent && collectionTabsFlickable.contentWidth > collectionTabsFlickable.width) {
                                const leftEdge = collTabDelegate.x;
                                const rightEdge = leftEdge + collTabDelegate.width;
                                const maxX = Math.max(0, collectionTabsFlickable.contentWidth - collectionTabsFlickable.width);
                                if (leftEdge < collectionTabsFlickable.contentX)
                                    collectionTabsFlickable.contentX = Math.max(0, leftEdge - 8);
                                else if (rightEdge > collectionTabsFlickable.contentX + collectionTabsFlickable.width)
                                    collectionTabsFlickable.contentX = Math.min(maxX, rightEdge - collectionTabsFlickable.width + 8);
                            }
                        }

                        StyledText {
                            id: collTabText
                            anchors.centerIn: parent
                            text: modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: isCurrent ? Font.Bold : Font.Normal
                            color: isCurrent ? modelData.accent : settledColors.colSubtext
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.nexus)
                                    root.nexus.openCollection(modelData.id);
                            }
                        }
                    }
                }
            }
        }
    }

    // Filter & Quick Create Bar
    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            radius: 8
            color: settledColors.colLayer0
            border.width: 1
            border.color: settledColors.colLayer0Border

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 6

                MaterialSymbol {
                    text: "filter_list"
                    iconSize: 16
                    color: settledColors.colSubtext
                }

                TextInput {
                    id: nexusCollectionFilterField
                    objectName: "nexusCollectionFilterField"
                    Layout.fillWidth: true
                    color: settledColors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    selectByMouse: true
                    Component.onCompleted: text = String(root.nexus?.collectionFilterQuery ?? "")
                    Connections {
                        target: root.nexus
                        function onCollectionFilterQueryChanged(): void {
                            if (nexusCollectionFilterField.inputMethodComposing)
                                return;
                            const nextQ = String(root.nexus?.collectionFilterQuery ?? "");
                            if (!nexusCollectionFilterField.activeFocus && nexusCollectionFilterField.text !== nextQ)
                                nexusCollectionFilterField.text = nextQ;
                        }
                    }
                    onTextChanged: {
                        if (inputMethodComposing)
                            return;
                        if (root.nexus && root.nexus.collectionFilterQuery !== text)
                            root.nexus.collectionFilterQuery = text;
                    }
                    onInputMethodComposingChanged: {
                        if (!inputMethodComposing && root.nexus && root.nexus.collectionFilterQuery !== text)
                            root.nexus.collectionFilterQuery = text;
                    }
                    Keys.onEscapePressed: event => {
                        if (inputMethodComposing) {
                            event.accepted = false;
                            return;
                        }
                        nexusCollectionFilterField.focus = false;
                        root.restoreWorkspaceFocus();
                        Qt.callLater(root.restoreWorkspaceFocus);
                        event.accepted = true;
                    }
                    Keys.onPressed: event => {
                        if (inputMethodComposing || event.key === 0 || event.key === Qt.Key_unknown) {
                            event.accepted = false;
                            return;
                        }
                        if ((event.modifiers & (Qt.AltModifier | Qt.ControlModifier | Qt.MetaModifier)) !== 0
                            && root.nexus && root.nexus.handleKeyEvent(event)) {
                            event.accepted = true;
                        }
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !parent.text
                        text: "Filter by title, muscle, equipment, genre, director, cast, or category..."
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: settledColors.colSubtext
                    }
                }
            }
        }

        Rectangle {
            Layout.preferredWidth: 210
            Layout.preferredHeight: 32
            radius: 8
            color: settledColors.colLayer0
            border.width: 1
            border.color: settledColors.colLayer0Border

            TextInput {
                id: newCollectionEntryInput
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                color: settledColors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.smaller
                selectByMouse: true
                onTextChanged: {
                    if (!inputMethodComposing)
                        collectionViewRoot.newEntryTitleDraft = text;
                }
                onInputMethodComposingChanged: {
                    if (!inputMethodComposing)
                        collectionViewRoot.newEntryTitleDraft = text;
                }
                onAccepted: {
                    if (inputMethodComposing)
                        Qt.inputMethod.commit();
                    if (root.nexus && text.trim().length > 0) {
                        root.nexus.createCollectionEntry(root.nexus.activeCollection, text.trim());
                        text = "";
                        newCollectionEntryInput.focus = false;
                        root.restoreWorkspaceFocus();
                        Qt.callLater(root.restoreWorkspaceFocus);
                    }
                }
                Keys.onEscapePressed: event => {
                    if (inputMethodComposing) {
                        event.accepted = false;
                        return;
                    }
                    newCollectionEntryInput.focus = false;
                    root.restoreWorkspaceFocus();
                    Qt.callLater(root.restoreWorkspaceFocus);
                    event.accepted = true;
                }
                Keys.onPressed: event => {
                    if (inputMethodComposing || event.key === 0 || event.key === Qt.Key_unknown) {
                        event.accepted = false;
                        return;
                    }
                    if ((event.modifiers & (Qt.AltModifier | Qt.ControlModifier | Qt.MetaModifier)) !== 0
                        && root.nexus && root.nexus.handleKeyEvent(event)) {
                        event.accepted = true;
                    }
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !parent.text
                    text: collectionViewRoot.activeCollectionMeta.placeholder
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: settledColors.colSubtext
                }
            }
        }

        Rectangle {
            id: nexusNewCollectionEntryButton
            objectName: "nexusNewCollectionEntryButton"
            Layout.preferredWidth: addEntryBtnRow.implicitWidth + 20
            Layout.preferredHeight: 32
            radius: 8
            color: settledColors.colPrimary

            RowLayout {
                id: addEntryBtnRow
                anchors.centerIn: parent
                spacing: 4
                MaterialSymbol {
                    text: "add"
                    iconSize: 16
                    color: settledColors.colOnPrimary
                }
                StyledText {
                    text: "Add Entry"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Bold
                    color: settledColors.colOnPrimary
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (!root.nexus)
                        return;
                    const draft = newCollectionEntryInput.text.trim();
                    const isApi = root.nexus.isApiBackedKind(root.nexus.activeCollection);
                    if (!isApi && draft.length > 0) {
                        root.nexus.createCollectionEntry(root.nexus.activeCollection, draft);
                        newCollectionEntryInput.text = "";
                        return;
                    }
                    root.nexus.openNewNoteModal(root.nexus.activeCollection, "");
                    if (draft.length > 0 && root && typeof root.setNewNoteSearchDraft === "function") {
                        root.setNewNoteSearchDraft(draft);
                        newCollectionEntryInput.text = "";
                        if (root.nexus.isApiBackedKind(root.nexus.newNoteModalKind) && draft.length >= 2)
                            root.nexus.searchExternalApi(root.nexus.newNoteModalKind, draft);
                    }
                }
            }
        }
    }

    // Obsidian Media_Tracker / Bases Section Banner Header ([01] [ MOVIES · FEATURE FILMS ] ───────• + Cards/Table Switcher)
    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Rectangle {
            width: 34
            height: 28
            radius: 6
            color: Qt.color(root.ccStop(1))
            border.width: 1
            border.color: settledColors.colLayer0Border
            StyledText {
                anchors.centerIn: parent
                text: collectionViewRoot.activeCollectionMeta.groupIndex
                font.family: Appearance.font.family.monospace
                font.pixelSize: 11
                font.weight: Font.Bold
                color: settledColors.colPrimary
            }
        }

        Rectangle {
            height: 28
            implicitWidth: bannerKickerRow.implicitWidth + 24
            radius: 6
            color: Qt.color(root.ccStop(1))
            border.width: 1
            border.color: settledColors.colLayer0Border

            RowLayout {
                id: bannerKickerRow
                anchors.centerIn: parent
                spacing: 10

                StyledText {
                    text: collectionViewRoot.activeCollectionMeta.groupKicker
                    font.pixelSize: 12
                    font.weight: Font.Black
                    font.letterSpacing: 2.2
                    color: settledColors.colOnLayer0
                }

                Rectangle {
                    width: 1
                    height: 12
                    color: settledColors.colLayer0Border
                }

                StyledText {
                    text: collectionViewRoot.activeCollectionMeta.groupSub
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: 9
                    font.letterSpacing: 1.8
                    color: settledColors.colPrimary
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: settledColors.colLayer0Border
        }

        // Finance.base sub-view tabs (`All | Transactions | Accounts | Subscription`)
        RowLayout {
            visible: collectionViewRoot.activeCollectionMeta.id === "finance"
            spacing: 4
            Repeater {
                model: [
                    { "id": "all", "label": "All" },
                    { "id": "transactions", "label": "Transactions" },
                    { "id": "accounts", "label": "Accounts" },
                    { "id": "subscriptions", "label": "Subscription" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool active: collectionViewRoot.financeSubTab === modelData.id
                    height: 24
                    width: finSubTxt.implicitWidth + 14
                    radius: 5
                    color: active ? settledColors.colSecondaryContainer : settledColors.colLayer0
                    border.width: 1
                    border.color: active ? settledColors.colPrimary : settledColors.colLayer0Border
                    StyledText {
                        id: finSubTxt
                        anchors.centerIn: parent
                        text: modelData.label
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: 10
                        font.weight: active ? Font.Bold : Font.Normal
                        color: active ? settledColors.colPrimary : settledColors.colSubtext
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: collectionViewRoot.financeSubTab = modelData.id
                    }
                }
            }
        }

        // Bases View Mode Switcher (`Cards | Table`)
        RowLayout {
            spacing: 4
            Repeater {
                model: [
                    { "id": "cards", "label": "Cards", "icon": "grid_view" },
                    { "id": "table", "label": "Table", "icon": "table_rows" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    objectName: "nexusBasesViewMode_" + modelData.id
                    readonly property bool active: collectionViewRoot.viewMode === modelData.id
                    height: 24
                    width: viewModeRow.implicitWidth + 12
                    radius: 5
                    color: active ? settledColors.colSecondaryContainer : settledColors.colLayer0
                    border.width: 1
                    border.color: active ? settledColors.colPrimary : settledColors.colLayer0Border
                    RowLayout {
                        id: viewModeRow
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: modelData.icon
                            iconSize: 12
                            color: active ? settledColors.colPrimary : settledColors.colSubtext
                        }
                        StyledText {
                            text: modelData.label
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: 10
                            font.weight: active ? Font.Bold : Font.Normal
                            color: active ? settledColors.colPrimary : settledColors.colSubtext
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: collectionViewRoot.viewMode = modelData.id
                    }
                }
            }
        }

        Rectangle {
            width: 7
            height: 7
            radius: 3.5
            color: settledColors.colPrimary
        }
    }

    // Finance Cashflow KPI Summary Strip (shown in Finance collection Cards/Table view)
    RowLayout {
        id: financeKpiSummaryBar
        objectName: "nexusFinanceKpiSummaryBar"
        visible: collectionViewRoot.activeCollectionMeta.id === "finance"
        Layout.fillWidth: true
        spacing: 8

        readonly property var fs: root.nexus?.financeSummary ?? ({})
        readonly property string defaultCurrency: String(fs.currency ?? "")

        Repeater {
            model: [
                {
                    "label": "TOTAL INCOME",
                    "value": collectionViewRoot._formatMoney(financeKpiSummaryBar.fs.totalIncome ?? 0, financeKpiSummaryBar.defaultCurrency),
                    "icon": "south_west",
                    "accent": String(settledColors.colTertiary ?? settledColors.colPrimary)
                },
                {
                    "label": "TOTAL SPENT",
                    "value": collectionViewRoot._formatMoney(financeKpiSummaryBar.fs.totalSpent ?? 0, financeKpiSummaryBar.defaultCurrency),
                    "icon": "north_east",
                    "accent": String(settledColors.colError ?? "#f38ba8")
                },
                {
                    "label": "NET CASHFLOW",
                    "value": collectionViewRoot._formatMoney(financeKpiSummaryBar.fs.balance ?? 0, financeKpiSummaryBar.defaultCurrency),
                    "icon": "account_balance_wallet",
                    "accent": String(settledColors.colPrimary)
                },
                {
                    "label": "ACCOUNTS / SUBS",
                    "value": String((financeKpiSummaryBar.fs.accounts ?? []).length) + " acc · " + String((financeKpiSummaryBar.fs.subscriptions ?? []).length) + " sub",
                    "icon": "autorenew",
                    "accent": String(settledColors.colSecondary ?? settledColors.colPrimary)
                }
            ]
            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 54
                radius: 10
                color: settledColors.colLayer2
                border.width: 1
                border.color: settledColors.colLayer0Border

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        radius: 8
                        color: Qt.alpha(Qt.color(modelData.accent), 0.16)
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: modelData.icon
                            iconSize: 16
                            color: Qt.color(modelData.accent)
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.label
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            font.letterSpacing: 0.6
                            color: settledColors.colSubtext
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.value
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            color: settledColors.colOnLayer0
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    // Collection / Bases Cards Grid (Virtualized GridView for zero-freeze rendering on 873+ Exercise notes)
    GridView {
        id: collectionCardsGrid
        objectName: "nexusCollectionCardsGrid"
        visible: collectionViewRoot.viewMode === "cards"
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: 480
        readonly property string activeKind: String(root.nexus?.activeCollection ?? "movies").toLowerCase()
        readonly property bool isPortraitDeck: activeKind === "movies" || activeKind === "tvseries" || activeKind === "games" || activeKind === "books" || activeKind === "recipes" || activeKind === "exercises" || activeKind === "places"
        readonly property int columns: isPortraitDeck
            ? Math.max(2, Math.floor(Math.max(320, width) / 228))
            : Math.max(2, Math.floor(Math.max(320, width) / 276))
        readonly property int cardHeight: activeKind === "movies" ? 352
            : (activeKind === "tvseries" ? 336
            : (activeKind === "games" ? 324
            : (activeKind === "books" ? 326
            : (activeKind === "recipes" ? 324
            : (activeKind === "exercises" ? 268
            : (activeKind === "places" ? 268
            : (activeKind === "cornell" ? 222
            : (activeKind === "zettelkasten" ? 208
            : (activeKind === "finance" ? 176 : 168)))))))))
        cellWidth: Math.floor(Math.max(320, width) / columns)
        cellHeight: cardHeight + 14

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            z: -1
            onClicked: mouse => {
                const pt = mapToItem(root, mouse.x, mouse.y);
                root.openContextMenu(pt.x, pt.y, {
                    "type": "workspace",
                    "title": collectionViewRoot.activeCollectionMeta.title
                });
            }
        }

        model: (collectionViewRoot.visible && collectionViewRoot.viewMode === "cards")
            ? collectionViewRoot.filteredCollectionItems
            : []

        delegate: Item {
            id: baseCardCell
            required property var modelData
            required property int index
            width: collectionCardsGrid.cellWidth
            height: collectionCardsGrid.cellHeight

            Item {
                id: baseCardDelegate
                readonly property var modelData: baseCardCell.modelData
                readonly property int index: baseCardCell.index
                objectName: "nexusBaseCard_" + String(index)
                readonly property string cid: collectionCardsGrid.activeKind
                readonly property bool isMovieCard: cid === "movies" || modelData.kind === "movie"
                readonly property bool isTvCard: cid === "tvseries" || modelData.kind === "tvseries" || modelData.kind === "tv"
                readonly property bool isGameCard: cid === "games" || modelData.kind === "game"
                readonly property bool isBookCard: cid === "books" || modelData.kind === "book"
                readonly property bool isRecipeCard: cid === "recipes" || modelData.kind === "recipe"
                readonly property bool isExerciseCard: cid === "exercises" || modelData.kind === "exercise"
                readonly property bool isPlaceCard: cid === "places" || modelData.kind === "place"
                readonly property bool isCornellCard: cid === "cornell" || modelData.kind === "cornell"
                readonly property bool isZettelCard: cid === "zettelkasten" || modelData.kind === "zettelkasten"
                readonly property bool isFinanceCard: cid === "finance" || modelData.kind === "finance"
                property bool flipped: false
                readonly property bool showBack: flipped || baseCardHover.hovered
                width: Math.max(120, parent.width - 14)
                height: collectionCardsGrid.cardHeight
                anchors.left: parent.left
                anchors.top: parent.top

                HoverHandler {
                    id: baseCardHover
                }

                    // ── 1. MOVIES: "CINEMA TICKET" CARD (Die-Cut Ticket Silhouette Larger Than Inner Border + Non-Overlapping Stub) ──
                    Item {
                        id: cinemaTicketCard
                        objectName: "nexusCinemaTicketCard_" + String(baseCardDelegate.index)
                        visible: baseCardDelegate.isMovieCard
                        anchors.fill: parent
                        readonly property color outerCanvasBg: Qt.color(root.ccStop(0))
                        readonly property color ticketBg: Qt.darker(Qt.color(root.ccStop(1)), 1.28)
                        readonly property color ticketInnerBg: Qt.darker(Qt.color(root.ccStop(0)), 1.35)
                        readonly property color ticketAccent: settledColors.colPrimary
                        readonly property color ticketKeyline: baseCardHover.hovered ? Qt.alpha(ticketAccent, 0.72) : Qt.alpha(ticketAccent, 0.42)
                        readonly property color ticketStubBg: Qt.tint(Qt.darker(Qt.color(root.ccStop(2)), 1.18), Qt.alpha(ticketAccent, 0.22))
                        readonly property color ticketStubInk: settledColors.colOnLayer1
                        clip: false

                        // Die-Cut Ticket Background Silhouette Canvas (same concave-corner + notch shape as inner border, slightly larger; transparent outside)
                        Canvas {
                            id: cinemaTicketSilhouetteCanvas
                            objectName: "nexusCinemaTicketSilhouette_" + String(baseCardDelegate.index)
                            anchors.fill: parent
                            z: 0
                            readonly property color _bg: cinemaTicketCard.ticketBg
                            readonly property color _stubBg: cinemaTicketCard.ticketStubBg
                            readonly property color _keyline: cinemaTicketCard.ticketKeyline
                            readonly property bool _showBack: baseCardDelegate.showBack
                            readonly property string _themeSig: root.themeSignature
                            on_BgChanged: if (visible) requestPaint()
                            on_StubBgChanged: if (visible) requestPaint()
                            on_KeylineChanged: if (visible) requestPaint()
                            on_ShowBackChanged: if (visible) requestPaint()
                            on_ThemeSigChanged: if (visible) requestPaint()
                            onVisibleChanged: if (visible) requestPaint()
                            onWidthChanged: if (visible) requestPaint()
                            onHeightChanged: if (visible) requestPaint()
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);
                                const w = width;
                                const h = height;
                                if (w < 40 || h < 40) return;

                                // Outer die-cut ticket path: mirrors the inner border (pad=10, cr=8, nr=9)
                                // expanded cleanly outward (outerPad=3, outerCr=10, outerNr=9) with side perforations.
                                const p = 3;
                                const cr = 10;
                                const nr = 9;
                                const cx = w * 0.5;

                                function traceTicketSilhouette() {
                                    ctx.beginPath();
                                    // Top edge: top-left concave corner -> top-center semicircular notch -> top-right concave corner
                                    ctx.moveTo(p + cr, p);
                                    ctx.lineTo(cx - nr, p);
                                    ctx.arc(cx, p, nr, Math.PI, 0, true);
                                    ctx.lineTo(w - p - cr, p);
                                    ctx.arc(w - p, p, cr, Math.PI, Math.PI * 0.5, true);
                                    // Right edge -> bottom-right concave corner
                                    ctx.lineTo(w - p, h - p - cr);
                                    ctx.arc(w - p, h - p, cr, Math.PI * 1.5, Math.PI, true);
                                    // Straight bottom edge -> bottom-left concave corner (matches unmodified inner border shape 1:1)
                                    ctx.lineTo(p + cr, h - p);
                                    ctx.arc(p, h - p, cr, 0, Math.PI * 1.5, true);
                                    // Left edge -> top-left concave corner
                                    ctx.lineTo(p, p + cr);
                                    ctx.arc(p, p, cr, Math.PI * 0.5, 0, true);
                                    ctx.closePath();
                                }

                                // Fill ticket body + tinted bottom stub clipped cleanly inside the ticket silhouette
                                ctx.save();
                                traceTicketSilhouette();
                                ctx.fillStyle = cinemaTicketCard.ticketBg;
                                ctx.fill();
                                ctx.clip();

                                const stubTopY = baseCardDelegate.showBack ? (h - 52) : (h - 68);
                                ctx.fillStyle = cinemaTicketCard.ticketStubBg;
                                ctx.fillRect(p, stubTopY, w - p * 2, h - stubTopY);

                                // Subtle perforated tear-line separating ticket body from stub
                                ctx.strokeStyle = cinemaTicketCard.ticketKeyline;
                                ctx.lineWidth = 1;
                                if (typeof ctx.setLineDash === "function")
                                    ctx.setLineDash([4, 3]);
                                ctx.beginPath();
                                ctx.moveTo(12, stubTopY);
                                ctx.lineTo(w - 12, stubTopY);
                                ctx.stroke();
                                if (typeof ctx.setLineDash === "function")
                                    ctx.setLineDash([]);
                                ctx.restore();

                                // Punch crisp real side perforation scallops along left & right outer edges (true alpha transparency)
                                ctx.save();
                                ctx.globalCompositeOperation = "destination-out";
                                ctx.fillStyle = "#000000";
                                for (let py = 20; py < h - 18; py += 13) {
                                    ctx.beginPath();
                                    ctx.arc(p, py, 2.2, 0, Math.PI * 2);
                                    ctx.fill();
                                    ctx.beginPath();
                                    ctx.arc(w - p, py, 2.2, 0, Math.PI * 2);
                                    ctx.fill();
                                }
                                ctx.restore();

                                // Subtle outer die-cut hairline rim for tangible ticket edge contrast
                                ctx.save();
                                traceTicketSilhouette();
                                ctx.strokeStyle = Qt.alpha(cinemaTicketCard.ticketAccent, baseCardHover.hovered ? 0.34 : 0.16);
                                ctx.lineWidth = 1;
                                ctx.stroke();
                                ctx.restore();
                            }
                        }

                        // FRONT FACE: Auto-Themed "CINEMA TICKET" Header (below top notch) + Keyline Poster Frame + Properly Inset Stub
                        Item {
                            id: movieFrontFace
                            anchors.fill: parent
                            z: 2
                            visible: !baseCardDelegate.showBack

                            StyledText {
                                anchors.top: parent.top
                                anchors.topMargin: 21
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "CINEMA TICKET"
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.letterSpacing: 2.8
                                color: cinemaTicketCard.ticketAccent
                                z: 4
                            }

                            Rectangle {
                                anchors.top: parent.top
                                anchors.topMargin: 39
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                height: 1
                                color: cinemaTicketCard.ticketKeyline
                                z: 4
                            }

                            // Inner Keyline Poster Frame (`margin: 44px 16px 8px` cleanly inside pad=10 border)
                            Rectangle {
                                id: frontPosterFrame
                                anchors.top: parent.top
                                anchors.topMargin: 44
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: frontTicketStub.top
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                anchors.bottomMargin: 8
                                color: cinemaTicketCard.ticketInnerBg
                                border.width: 1
                                border.color: cinemaTicketCard.ticketKeyline
                                clip: true

                                Image {
                                    id: moviePosterImg
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    source: String(baseCardDelegate.modelData.posterUrl ?? "")
                                    sourceSize: Qt.size(360, 540)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: false
                                    visible: Boolean(baseCardDelegate.modelData.posterUrl) && status === Image.Ready
                                }

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    visible: !moviePosterImg.visible
                                    spacing: 6
                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "movie"
                                        iconSize: 34
                                        color: cinemaTicketCard.ticketAccent
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        Layout.maximumWidth: 150
                                        horizontalAlignment: Text.AlignHCenter
                                        text: String(baseCardDelegate.modelData.title ?? "")
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        color: settledColors.colOnLayer1
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }

                            // Inset Bottom Ticket Stub — aligned cleanly INSIDE the inner keyline border (pad=10, cr=8 => safe x=[21..w-21], y<=h-16) with ZERO overlap!
                            Item {
                                id: frontTicketStub
                                objectName: "nexusCinemaFrontStub_" + String(baseCardDelegate.index)
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.leftMargin: 21
                                anchors.rightMargin: 21
                                anchors.bottomMargin: 16
                                height: 48
                                clip: true

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 6

                                    // Left-Aligned Simulated Code-128 Barcode + numeric IDs (`imdbId-id`)
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        spacing: 3

                                        Item { Layout.fillHeight: true }

                                        Row {
                                            Layout.alignment: Qt.AlignLeft
                                            spacing: 1.5
                                            Repeater {
                                                model: [2, 1, 3, 1, 2, 1, 3, 1, 2, 2, 1, 3, 1, 2, 1, 3, 2, 1, 2, 3, 1, 2, 1, 2]
                                                delegate: Rectangle {
                                                    required property int modelData
                                                    width: modelData
                                                    height: 20
                                                    color: Qt.alpha(cinemaTicketCard.ticketAccent, 0.90)
                                                }
                                            }
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignLeft
                                            text: {
                                                const imdb = String(baseCardDelegate.modelData.imdbId || "tt0816711");
                                                const tmdb = String(baseCardDelegate.modelData.tmdbId || baseCardDelegate.modelData.year || "72190");
                                                return imdb + "-" + tmdb;
                                            }
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 8
                                            font.letterSpacing: 0.8
                                            color: settledColors.colSubtext
                                            elide: Text.ElideRight
                                        }

                                        Item { Layout.fillHeight: true }
                                    }

                                    // Vertical Rotated Status ("FINISHED" / "QUEUE") — sized to fit cleanly inside 48px stub height without clipping
                                    Item {
                                        Layout.preferredWidth: 15
                                        Layout.fillHeight: true
                                        StyledText {
                                            anchors.centerIn: parent
                                            rotation: 90
                                            text: {
                                                const st = String(baseCardDelegate.modelData.status ?? "").toLowerCase();
                                                return (st === "watched" || st === "completed" || st === "finished" || st === "done") ? "FINISHED" : "QUEUE";
                                            }
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 7
                                            font.weight: Font.Black
                                            font.letterSpacing: 0.4
                                            color: cinemaTicketCard.ticketAccent
                                        }
                                    }
                                }
                            }
                        }

                        // BACK FACE: Detailed Movie Dossier (Auto-Themed Labels, Monospace Values, Dashed Dividers, Properly Inset Stub)
                        Item {
                            id: movieBackFace
                            objectName: "nexusCinemaTicketBack_" + String(baseCardDelegate.index)
                            anchors.fill: parent
                            z: 2
                            visible: baseCardDelegate.showBack

                            ColumnLayout {
                                anchors.top: parent.top
                                anchors.topMargin: 24
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: movieBackStub.top
                                anchors.leftMargin: 20
                                anchors.rightMargin: 20
                                anchors.bottomMargin: 8
                                spacing: 3

                                Repeater {
                                    model: [
                                        { "k": "TITLE", "v": String(baseCardDelegate.modelData.title ?? ""), "bold": true },
                                        { "k": "GENRE", "v": String(baseCardDelegate.modelData.genre || "Feature Film"), "bold": false },
                                        { "k": "RUNTIME", "v": String(baseCardDelegate.modelData.runtime || "—"), "bold": false },
                                        { "k": "YEAR", "v": String(baseCardDelegate.modelData.year || "—"), "bold": false },
                                        { "k": "RELEASE", "v": String(baseCardDelegate.modelData.releaseDate || baseCardDelegate.modelData.released || baseCardDelegate.modelData.year || "—"), "bold": false },
                                        { "k": "DIRECTOR", "v": String(baseCardDelegate.modelData.director || "—"), "bold": false },
                                        { "k": "CAST", "v": String(baseCardDelegate.modelData.actors || "—"), "bold": false }
                                    ]
                                    delegate: ColumnLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 2
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6
                                            StyledText {
                                                Layout.preferredWidth: 56
                                                text: modelData.k
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                                color: cinemaTicketCard.ticketAccent
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                horizontalAlignment: Text.AlignLeft
                                                text: modelData.v
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: 9
                                                font.weight: modelData.bold ? Font.Bold : Font.Normal
                                                color: modelData.bold ? settledColors.colOnLayer0 : settledColors.colOnLayer1
                                                elide: Text.ElideRight
                                            }
                                        }
                                        // Dashed horizontal row divider
                                        Row {
                                            Layout.fillWidth: true
                                            spacing: 3
                                            Repeater {
                                                model: 26
                                                delegate: Rectangle {
                                                    width: 4
                                                    height: 1
                                                    color: Qt.alpha(cinemaTicketCard.ticketAccent, 0.20)
                                                }
                                            }
                                        }
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.topMargin: 2
                                    text: String(baseCardDelegate.modelData.plot || "Click to open movie note...")
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 9
                                    color: settledColors.colSubtext
                                    wrapMode: Text.WordWrap
                                    elide: Text.ElideRight
                                    maximumLineCount: 5
                                }
                            }

                            // Inset Back Stub — Rating Stars + Status cleanly inside inner border (pad=10, cr=8 => safe x=[21..w-21], y<=h-16) with ZERO overlap!
                            Item {
                                id: movieBackStub
                                objectName: "nexusCinemaBackStub_" + String(baseCardDelegate.index)
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.leftMargin: 21
                                anchors.rightMargin: 21
                                anchors.bottomMargin: 16
                                height: 30

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 6

                                    StyledText {
                                        Layout.fillWidth: true
                                        verticalAlignment: Text.AlignVCenter
                                        text: collectionViewRoot._starsForScore(baseCardDelegate.modelData.score)
                                        font.pixelSize: 12
                                        font.letterSpacing: 1.5
                                        color: cinemaTicketCard.ticketAccent
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        verticalAlignment: Text.AlignVCenter
                                        text: {
                                            const st = String(baseCardDelegate.modelData.status ?? "").toLowerCase();
                                            return (st === "watched" || st === "completed" || st === "finished" || st === "done") ? "FINISHED" : "QUEUE";
                                        }
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 9
                                        font.weight: Font.Black
                                        font.letterSpacing: 1.2
                                        color: settledColors.colOnLayer1
                                    }
                                }
                            }
                        }

                        // UNMODIFIED Inner Keyline Border (exact pad=10, cr=8, nr=9 geometry preserved intact)
                        Canvas {
                            id: cinemaTicketFrameCanvas
                            anchors.fill: parent
                            z: 9
                            readonly property color _keyline: cinemaTicketCard.ticketKeyline
                            readonly property string _themeSig: root.themeSignature
                            on_KeylineChanged: if (visible) requestPaint()
                            on_ThemeSigChanged: if (visible) requestPaint()
                            onVisibleChanged: {
                                if (visible)
                                    requestPaint();
                            }
                            onWidthChanged: if (visible) requestPaint()
                            onHeightChanged: if (visible) requestPaint()
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);
                                const w = width;
                                const h = height;
                                if (w < 40 || h < 40) return;

                                // Exact inner keyline border with concave corner arcs (r=8) and top-center notch arc (r=9)
                                const pad = 10;
                                const cr = 8;
                                const nr = 9;
                                const cx = w * 0.5;
                                ctx.strokeStyle = cinemaTicketCard.ticketKeyline;
                                ctx.lineWidth = 1;
                                ctx.beginPath();
                                // Top edge: left corner arc -> top notch arc -> right corner arc
                                ctx.moveTo(pad + cr, pad);
                                ctx.lineTo(cx - nr, pad);
                                ctx.arc(cx, pad, nr, Math.PI, 0, true);
                                ctx.lineTo(w - pad - cr, pad);
                                ctx.arc(w - pad, pad, cr, Math.PI, Math.PI * 0.5, true);
                                // Right edge -> bottom-right corner arc
                                ctx.lineTo(w - pad, h - pad - cr);
                                ctx.arc(w - pad, h - pad, cr, Math.PI * 1.5, Math.PI, true);
                                // Bottom edge -> bottom-left corner arc
                                ctx.lineTo(pad + cr, h - pad);
                                ctx.arc(pad, h - pad, cr, 0, Math.PI * 1.5, true);
                                // Left edge -> top-left corner arc
                                ctx.lineTo(pad, pad + cr);
                                ctx.arc(pad, pad, cr, Math.PI * 0.5, 0, true);
                                ctx.stroke();
                            }
                        }
                    }

                    // ── 2. TV SERIES: FULL-BLEED COVER + FILM-STRIP SPROCKET CARD (Media_Tracker.base packed_tv + 02_Components.css) ──
                    Rectangle {
                        id: tvSeriesCard
                        objectName: "nexusTvSeriesCard_" + String(baseCardDelegate.index)
                        visible: baseCardDelegate.isTvCard && !baseCardDelegate.isMovieCard
                        anchors.fill: parent
                        radius: 6
                        color: Qt.darker(Qt.color(root.ccStop(1)), 1.15)
                        border.width: 1
                        border.color: baseCardHover.hovered ? settledColors.colPrimary : Qt.alpha(settledColors.colPrimary, 0.25)
                        clip: true

                        // Front Poster: Full-bleed cover image filling 100% of the card without side bars
                        Item {
                            anchors.fill: parent
                            visible: !baseCardDelegate.showBack

                            Image {
                                id: tvPosterImg
                                objectName: "nexusTvPosterImg_" + String(baseCardDelegate.index)
                                anchors.fill: parent
                                source: String(baseCardDelegate.modelData.posterUrl ?? "")
                                sourceSize: Qt.size(360, 540)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                visible: Boolean(baseCardDelegate.modelData.posterUrl) && status === Image.Ready
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                visible: !tvPosterImg.visible
                                spacing: 6
                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "live_tv"
                                    iconSize: 34
                                    color: settledColors.colPrimary
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.maximumWidth: 150
                                    horizontalAlignment: Text.AlignHCenter
                                    text: String(baseCardDelegate.modelData.title ?? "")
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: settledColors.colOnLayer1
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        // Circular film-strip sprocket holes (7×7px, radius 3.5, every 22px) matching `02_Components.css` lines 3541-3579 & Screenshot 3
                        Repeater {
                            model: Math.max(0, Math.floor((tvSeriesCard.height - 14) / 22))
                            delegate: Item {
                                required property int index
                                y: 11 + index * 22
                                width: parent.width
                                height: 7
                                z: 4
                                Rectangle {
                                    x: 9.5
                                    width: 7
                                    height: 7
                                    radius: 3.5
                                    color: Qt.darker(Qt.color(root.ccStop(0)), 1.25)
                                    border.width: 1
                                    border.color: Qt.rgba(0, 0, 0, 0.45)
                                }
                                Rectangle {
                                    x: parent.width - 16.5
                                    width: 7
                                    height: 7
                                    radius: 3.5
                                    color: Qt.darker(Qt.color(root.ccStop(0)), 1.25)
                                    border.width: 1
                                    border.color: Qt.rgba(0, 0, 0, 0.45)
                                }
                            }
                        }

                        // Back Dossier (Matches packed_tv in Media_Tracker.base)
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 20
                            anchors.rightMargin: 20
                            anchors.topMargin: 10
                            anchors.bottomMargin: 10
                            visible: baseCardDelegate.showBack
                            spacing: 3

                            RowLayout {
                                Layout.fillWidth: true
                                StyledText {
                                    Layout.fillWidth: true
                                    text: "TV SERIES"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.8
                                    color: settledColors.colPrimary
                                }
                                StyledText {
                                    text: String(baseCardDelegate.modelData.status || baseCardDelegate.modelData.airingStatus || "WATCHING").toUpperCase()
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 8
                                    font.weight: Font.Bold
                                    color: settledColors.colSecondary
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: String(baseCardDelegate.modelData.title ?? "")
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                color: settledColors.colOnLayer1
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: {
                                    const yr = String(baseCardDelegate.modelData.year || "—");
                                    const endYr = String(baseCardDelegate.modelData.ended || "");
                                    const air = String(baseCardDelegate.modelData.airingStatus || baseCardDelegate.modelData.status || "Series");
                                    return (endYr && endYr !== yr ? (yr + "–" + endYr) : yr) + " · " + air;
                                }
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 8
                                color: settledColors.colSubtext
                                elide: Text.ElideRight
                            }

                            Repeater {
                                model: {
                                    const s = String(baseCardDelegate.modelData.seasons || "0");
                                    const ep = String(baseCardDelegate.modelData.episodes || "0");
                                    return [
                                        { "k": "Genre:", "v": String(baseCardDelegate.modelData.genre || "—") },
                                        { "k": "Run:", "v": s + " seasons · " + ep + " eps" },
                                        { "k": "Episode:", "v": String(baseCardDelegate.modelData.runtime || "—") },
                                        { "k": "Network:", "v": String(baseCardDelegate.modelData.networks || "—") },
                                        { "k": "Creator:", "v": String(baseCardDelegate.modelData.creator || baseCardDelegate.modelData.director || "—") },
                                        { "k": "Cast:", "v": String(baseCardDelegate.modelData.actors || "—") }
                                    ];
                                }
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 4
                                    StyledText { text: modelData.k; font.pixelSize: 8; font.weight: Font.Bold; color: settledColors.colOnLayer1 }
                                    StyledText { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: modelData.v; font.pixelSize: 8; color: settledColors.colSubtext; elide: Text.ElideRight }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                text: String(baseCardDelegate.modelData.plot || "Click to open TV series dossier...")
                                font.pixelSize: 8
                                color: settledColors.colSubtext
                                wrapMode: Text.WordWrap
                                elide: Text.ElideRight
                                maximumLineCount: 4
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                StyledText {
                                    Layout.fillWidth: true
                                    text: collectionViewRoot._starsForScore(baseCardDelegate.modelData.score)
                                    font.pixelSize: 11
                                    color: settledColors.colPrimary
                                }
                                StyledText {
                                    text: String(baseCardDelegate.modelData.onlineRating || baseCardDelegate.modelData.score || "")
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    color: settledColors.colSubtext
                                }
                            }
                        }
                    }

                    // ── 3. GAMES: ABYSSAL DOSSIER CARD (Game_Collection.base packed_game + 02_Components.css lines 621–915) ──
                    Rectangle {
                        id: gameBaseCard
                        objectName: "nexusGameBaseCard_" + String(baseCardDelegate.index)
                        visible: baseCardDelegate.isGameCard
                        anchors.fill: parent
                        radius: 8
                        color: Qt.darker(Qt.color(root.ccStop(1)), 1.15)
                        border.width: 1
                        border.color: baseCardHover.hovered ? settledColors.colPrimary : Qt.alpha(settledColors.colPrimary, 0.25)
                        clip: true

                        // Face 1: Full-Bleed Cover
                        Item {
                            anchors.fill: parent
                            visible: !baseCardDelegate.showBack

                            Image {
                                id: gameCoverImg
                                anchors.fill: parent
                                source: String(baseCardDelegate.modelData.posterUrl ?? "")
                                sourceSize: Qt.size(360, 540)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                visible: Boolean(baseCardDelegate.modelData.posterUrl) && status === Image.Ready
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                visible: !gameCoverImg.visible
                                spacing: 6
                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "sports_esports"
                                    iconSize: 34
                                    color: settledColors.colPrimary
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.maximumWidth: 160
                                    horizontalAlignment: Text.AlignHCenter
                                    text: String(baseCardDelegate.modelData.title ?? "")
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: settledColors.colOnLayer1
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        // Face 2: Abyssal Dossier Back (Exact match to packed_game in Game_Collection.base + .abyssal-card in 02_Components.css lines 4219–4418)
                        Item {
                            anchors.fill: parent
                            visible: baseCardDelegate.showBack

                            // Left 2px status accent bar (`.abyssal-card` status indicator)
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 2
                                color: {
                                    const st = String(baseCardDelegate.modelData.status || "").toLowerCase();
                                    if (st === "playing" || st === "completed" || st === "finished")
                                        return settledColors.colPrimary;
                                    return Qt.color(root.ccStop(8));
                                }
                            }

                            // Bottom-right corner bracket (`.abyssal-card::after`)
                            Item {
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.rightMargin: 7
                                anchors.bottomMargin: 7
                                width: 11
                                height: 11
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 1
                                    color: Qt.alpha(settledColors.colPrimary, 0.36)
                                }
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 1
                                    color: Qt.alpha(settledColors.colPrimary, 0.36)
                                }
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 13
                                anchors.rightMargin: 12
                                anchors.topMargin: 11
                                anchors.bottomMargin: 11
                                spacing: 3

                                // Header: "GAME DOSSIER · {STORE}" + Status Pill
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: "GAME DOSSIER · " + String(baseCardDelegate.modelData.store || "LIBRARY").toUpperCase()
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 8
                                        font.weight: Font.Bold
                                        font.letterSpacing: 1.1
                                        color: settledColors.colPrimary
                                        elide: Text.ElideRight
                                    }
                                    Rectangle {
                                        height: 16
                                        width: gameStText.implicitWidth + 10
                                        radius: 3
                                        color: Qt.alpha(settledColors.colPrimary, 0.16)
                                        border.width: 1
                                        border.color: Qt.alpha(settledColors.colPrimary, 0.35)
                                        StyledText {
                                            id: gameStText
                                            anchors.centerIn: parent
                                            text: String(baseCardDelegate.modelData.status || "BACKLOG").toUpperCase()
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 7
                                            font.weight: Font.Bold
                                            color: settledColors.colPrimary
                                        }
                                    }
                                }

                                // Title + "{developer} · {year}" byline
                                StyledText {
                                    Layout.fillWidth: true
                                    text: String(baseCardDelegate.modelData.title ?? "")
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: settledColors.colOnLayer0
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: {
                                        const dev = String(baseCardDelegate.modelData.developer || "Unknown studio").trim();
                                        const yr = String(baseCardDelegate.modelData.year || "").trim();
                                        return yr.length > 0 ? (dev + " · " + yr) : dev;
                                    }
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 8
                                    color: settledColors.colSubtext
                                    elide: Text.ElideRight
                                }

                                // 4 Metadata Rows: Platform, Genre, Publisher, Achievements (`.abyssal-card-meta`)
                                Repeater {
                                    model: {
                                        const achE = String(baseCardDelegate.modelData.achievementsEarned || "");
                                        const achT = String(baseCardDelegate.modelData.achievementsTotal || "");
                                        const achStr = (achE || achT) ? ((achE || "0") + " / " + (achT || "0")) : "—";
                                        return [
                                            { "k": "Platform", "v": String(baseCardDelegate.modelData.platform || "—") },
                                            { "k": "Genre", "v": String(baseCardDelegate.modelData.genre || "—") },
                                            { "k": "Publisher", "v": String(baseCardDelegate.modelData.publisher || "—") },
                                            { "k": "Achievements", "v": achStr }
                                        ];
                                    }
                                    delegate: ColumnLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 1
                                        RowLayout {
                                            Layout.fillWidth: true
                                            StyledText {
                                                text: modelData.k
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: 8
                                                color: settledColors.colSubtext
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                horizontalAlignment: Text.AlignRight
                                                text: modelData.v
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: 8
                                                font.weight: Font.Bold
                                                color: settledColors.colOnLayer1
                                                elide: Text.ElideRight
                                            }
                                        }
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 1
                                            color: Qt.alpha(settledColors.colLayer0Border, 0.38)
                                        }
                                    }
                                }

                                // Synopsis / Description (`.abyssal-card-desc`)
                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    text: String(baseCardDelegate.modelData.plot || "No description logged yet.")
                                    font.pixelSize: 8
                                    color: settledColors.colSubtext
                                    wrapMode: Text.WordWrap
                                    elide: Text.ElideRight
                                    maximumLineCount: 3
                                }

                                // Completion Progress Bar (`.abyssal-card-progress`)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    readonly property int compPct: {
                                        const n = parseFloat(String(baseCardDelegate.modelData.completion || "0").replace(/[^0-9.]/g, ""));
                                        return Number.isFinite(n) ? Math.max(0, Math.min(100, Math.round(n))) : 0;
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: "COMPLETION"
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 7
                                            font.letterSpacing: 1.0
                                            color: settledColors.colSubtext
                                        }
                                        StyledText {
                                            text: String(parent.parent.compPct) + "%"
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 8
                                            font.weight: Font.Bold
                                            color: settledColors.colPrimary
                                        }
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 3
                                        radius: 1.5
                                        color: Qt.color(root.ccStop(0))
                                        Rectangle {
                                            width: parent.width * (parent.parent.compPct / 100.0)
                                            height: parent.height
                                            radius: 1.5
                                            color: settledColors.colPrimary
                                        }
                                    }
                                }

                                // Top-bordered 3-Column Footer (`.abyssal-card-foot`: Rating /10, Hours Played, Metacritic)
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 2
                                    height: 1
                                    color: Qt.alpha(settledColors.colLayer0Border, 0.52)
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Repeater {
                                        model: [
                                            {
                                                "val": (baseCardDelegate.modelData.rating || baseCardDelegate.modelData.score || "0") + "/10",
                                                "lbl": "RATING",
                                                "align": Text.AlignLeft
                                            },
                                            {
                                                "val": String(baseCardDelegate.modelData.hoursPlayed || "0") + "h",
                                                "lbl": "PLAYED",
                                                "align": Text.AlignHCenter
                                            },
                                            {
                                                "val": String(baseCardDelegate.modelData.metacritic || "—"),
                                                "lbl": "METACRITIC",
                                                "align": Text.AlignRight
                                            }
                                        ]
                                        delegate: ColumnLayout {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            spacing: 0
                                            StyledText {
                                                Layout.fillWidth: true
                                                horizontalAlignment: modelData.align
                                                text: modelData.val
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                                color: settledColors.colPrimary
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                horizontalAlignment: modelData.align
                                                text: modelData.lbl
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: 6
                                                font.letterSpacing: 0.9
                                                color: settledColors.colSubtext
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── 4. BOOKS: 3D SPINE + CHEVRON BOOKMARK RIBBON + LINED NOTEBOOK BACK (Book_Tracker.base + 02_Components.css lines 1659–2498) ──
                    Rectangle {
                        id: bookBaseCard
                        objectName: "nexusBookBaseCard_" + String(baseCardDelegate.index)
                        visible: baseCardDelegate.isBookCard
                        anchors.fill: parent
                        radius: 5
                        color: baseCardDelegate.showBack
                            ? Qt.color(root.ccStop(2))
                            : Qt.darker(Qt.color(root.ccStop(1)), 1.15)
                        border.width: 1
                        border.color: baseCardHover.hovered ? settledColors.colPrimary : Qt.alpha(settledColors.colLayer0Border, 0.65)
                        clip: true

                        // Face 1: Full-Bleed Book Cover + Smooth 0%–22% 3D Spine Lighting + Top-Left Pointed Status Ribbon
                        Item {
                            anchors.fill: parent
                            visible: !baseCardDelegate.showBack

                            Image {
                                id: bookCoverImg
                                objectName: "nexusBookCoverImg_" + String(baseCardDelegate.index)
                                anchors.fill: parent
                                source: String(baseCardDelegate.modelData.posterUrl ?? "")
                                sourceSize: Qt.size(360, 540)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                visible: Boolean(baseCardDelegate.modelData.posterUrl) && status === Image.Ready
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                visible: !bookCoverImg.visible
                                spacing: 6
                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "menu_book"
                                    iconSize: 34
                                    color: settledColors.colPrimary
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.maximumWidth: 150
                                    horizontalAlignment: Text.AlignHCenter
                                    text: String(baseCardDelegate.modelData.title ?? "")
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: settledColors.colOnLayer1
                                    wrapMode: Text.WordWrap
                                }
                            }

                            // Smooth 3D Book Spine Lighting Overlay (`.bases-cards-cover::before` + `::after` in `02_Components.css` lines 1737–1827, 0%–22% width)
                            Rectangle {
                                id: bookSpineOverlay
                                objectName: "nexusBookSpineOverlay_" + String(baseCardDelegate.index)
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                width: Math.max(36, Math.round(parent.width * 0.22))
                                z: 3
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.00; color: Qt.rgba(0, 0, 0, 0.42) }
                                    GradientStop { position: 0.05; color: Qt.rgba(1, 1, 1, 0.20) }
                                    GradientStop { position: 0.14; color: Qt.rgba(1, 1, 1, 0.08) }
                                    GradientStop { position: 0.24; color: Qt.rgba(0, 0, 0, 0.30) }
                                    GradientStop { position: 0.34; color: Qt.rgba(0, 0, 0, 0.16) }
                                    GradientStop { position: 0.42; color: Qt.rgba(1, 1, 1, 0.22) }
                                    GradientStop { position: 0.56; color: Qt.rgba(1, 1, 1, 0.08) }
                                    GradientStop { position: 0.76; color: Qt.rgba(0, 0, 0, 0.05) }
                                    GradientStop { position: 1.00; color: "transparent" }
                                }
                            }

                            // Top-left Pointed Bookmark Status Ribbon (`02_Components.css` lines 2099–2158 & Screenshot 4)
                            Item {
                                id: bookRibbon
                                objectName: "nexusBookStatusRibbon_" + String(baseCardDelegate.index)
                                x: 9
                                y: 0
                                width: 32
                                height: 84
                                z: 6

                                readonly property string statusNorm: {
                                    const raw = String(baseCardDelegate.modelData.status || "to read").trim().toLowerCase();
                                    if (raw === "finished" || raw === "completed" || raw === "read" || raw === "done")
                                        return "FINISHED";
                                    if (raw === "reading" || raw === "in progress" || raw === "current")
                                        return "READING";
                                    return "TO READ";
                                }

                                Canvas {
                                    id: bookRibbonCanvas
                                    anchors.fill: parent
                                    readonly property string _st: bookRibbon.statusNorm
                                    readonly property string _themeSig: root.themeSignature
                                    on_StChanged: if (visible) requestPaint()
                                    on_ThemeSigChanged: if (visible) requestPaint()
                                    onVisibleChanged: {
                                        if (visible)
                                            requestPaint();
                                    }
                                    onWidthChanged: if (visible) requestPaint()
                                    onHeightChanged: if (visible) requestPaint()
                                    onPaint: {
                                        const ctx = getContext("2d");
                                        ctx.clearRect(0, 0, width, height);
                                        const w = width;
                                        const h = height;
                                        const tipH = 10;

                                        // Pointed ribbon polygon: (0,0) -> (w,0) -> (w, h-tipH) -> (w/2, h) -> (0, h-tipH)
                                        ctx.beginPath();
                                        ctx.moveTo(0.5, 0);
                                        ctx.lineTo(w - 0.5, 0);
                                        ctx.lineTo(w - 0.5, h - tipH);
                                        ctx.lineTo(w * 0.5, h - 0.5);
                                        ctx.lineTo(0.5, h - tipH);
                                        ctx.closePath();

                                        const acc = settledColors.colPrimary;
                                        const l2 = Qt.color(root.ccStop(2));
                                        const l3 = Qt.color(root.ccStop(3));
                                        let topCol = l3;
                                        let botCol = l2;
                                        if (bookRibbon.statusNorm === "FINISHED") {
                                            topCol = Qt.tint(l3, Qt.rgba(acc.r, acc.g, acc.b, 0.34));
                                            botCol = Qt.tint(l2, Qt.rgba(acc.r, acc.g, acc.b, 0.22));
                                        } else if (bookRibbon.statusNorm === "READING") {
                                            topCol = Qt.tint(l3, Qt.rgba(acc.r, acc.g, acc.b, 0.50));
                                            botCol = Qt.tint(l2, Qt.rgba(acc.r, acc.g, acc.b, 0.36));
                                        } else {
                                            topCol = Qt.darker(l3, 1.05);
                                            botCol = Qt.darker(l2, 1.12);
                                        }

                                        const grad = ctx.createLinearGradient(0, 0, 0, h);
                                        grad.addColorStop(0.0, topCol.toString());
                                        grad.addColorStop(1.0, botCol.toString());
                                        ctx.fillStyle = grad;
                                        ctx.fill();

                                        ctx.strokeStyle = Qt.rgba(acc.r, acc.g, acc.b, 0.38);
                                        ctx.lineWidth = 1;
                                        ctx.stroke();
                                    }
                                }

                                StyledText {
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: -4
                                    rotation: 90
                                    text: bookRibbon.statusNorm
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 9
                                    font.weight: Font.Black
                                    font.letterSpacing: 1.5
                                    color: bookRibbon.statusNorm === "READING"
                                        ? settledColors.colPrimary
                                        : settledColors.colOnLayer0
                                }
                            }
                        }

                        // Face 2: Lined Notebook Paper Back (`.book-back` in `Book_Tracker.base` + `02_Components.css` lines 2170–2498)
                        Item {
                            id: bookBackFace
                            objectName: "nexusBookBackFace_" + String(baseCardDelegate.index)
                            anchors.fill: parent
                            visible: baseCardDelegate.showBack

                            // 15 horizontal ruled notebook lines (`22px` line spacing)
                            Column {
                                anchors.fill: parent
                                anchors.topMargin: 22
                                spacing: 21
                                Repeater {
                                    model: 15
                                    delegate: Rectangle {
                                        width: bookBackFace.width
                                        height: 1
                                        color: Qt.alpha(settledColors.colOnLayer1, 0.08)
                                    }
                                }
                            }

                            // Left vertical margin rule line at x=34
                            Rectangle {
                                x: 34
                                y: 0
                                width: 1
                                height: parent.height
                                color: Qt.alpha(settledColors.colPrimary, 0.38)
                            }

                            // Left margin hand-jotted symbols (`×`, `↳`, and `-14deg` `keep`) matching `02_Components.css` lines 2274–2305
                            StyledText {
                                x: 12
                                y: 112
                                text: "×"
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 11
                                color: Qt.alpha(settledColors.colPrimary, 0.65)
                            }
                            StyledText {
                                x: 12
                                y: 160
                                text: "↳"
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 11
                                color: Qt.alpha(settledColors.colPrimary, 0.65)
                            }
                            StyledText {
                                x: 4
                                y: 224
                                rotation: -14
                                text: "keep"
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 8
                                font.italic: true
                                color: Qt.alpha(settledColors.colSubtext, 0.72)
                            }

                            // Top-right folded dog-ear corner (`.book-back::after`)
                            Canvas {
                                id: bookDogEarCanvas
                                anchors.top: parent.top
                                anchors.right: parent.right
                                width: 22
                                height: 22
                                readonly property color _foldCol: Qt.color(root.ccStop(4))
                                readonly property string _themeSig: root.themeSignature
                                on_FoldColChanged: if (visible) requestPaint()
                                on_ThemeSigChanged: if (visible) requestPaint()
                                onVisibleChanged: {
                                    if (visible)
                                        requestPaint();
                                }
                                onPaint: {
                                    const ctx = getContext("2d");
                                    ctx.clearRect(0, 0, width, height);
                                    ctx.beginPath();
                                    ctx.moveTo(0, 0);
                                    ctx.lineTo(width, height);
                                    ctx.lineTo(0, height);
                                    ctx.closePath();
                                    ctx.fillStyle = root.ccStop(4);
                                    ctx.fill();
                                }
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 42
                                anchors.rightMargin: 12
                                anchors.topMargin: 12
                                anchors.bottomMargin: 12
                                spacing: 4

                                StyledText {
                                    text: "✦ BOOK COLLECTION"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 8
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.4
                                    color: settledColors.colPrimary
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: String(baseCardDelegate.modelData.title ?? "")
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    font.italic: true
                                    color: settledColors.colOnLayer0
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }

                                // Hand-drawn wavy underline under book title (`.book-back-title`)
                                Canvas {
                                    id: bookWavyUnderline
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 5
                                    readonly property color _waveCol: settledColors.colPrimary
                                    readonly property string _themeSig: root.themeSignature
                                    on_WaveColChanged: if (visible) requestPaint()
                                    on_ThemeSigChanged: if (visible) requestPaint()
                                    onVisibleChanged: {
                                        if (visible)
                                            requestPaint();
                                    }
                                    onWidthChanged: if (visible) requestPaint()
                                    onPaint: {
                                        const ctx = getContext("2d");
                                        ctx.clearRect(0, 0, width, height);
                                        ctx.strokeStyle = Qt.alpha(settledColors.colPrimary, 0.58);
                                        ctx.lineWidth = 1.1;
                                        ctx.beginPath();
                                        for (let wx = 0; wx <= width; wx += 2) {
                                            const wy = 2.5 + Math.sin(wx * 0.45) * 1.2;
                                            if (wx === 0) ctx.moveTo(wx, wy);
                                            else ctx.lineTo(wx, wy);
                                        }
                                        ctx.stroke();
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: "by " + String(baseCardDelegate.modelData.author || baseCardDelegate.modelData.director || "Unknown author")
                                    font.pixelSize: 10
                                    font.italic: true
                                    color: settledColors.colSubtext
                                    elide: Text.ElideRight
                                }

                                // `.book-back-genres`: GENRES label + slash-separated list (`02_Components.css` lines 2368–2398)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 2
                                    spacing: 1
                                    StyledText {
                                        text: "GENRES"
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 7
                                        font.letterSpacing: 1.2
                                        color: settledColors.colSubtext
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: {
                                            const g = String(baseCardDelegate.modelData.genre || "").split(",").map(s => s.trim()).filter(Boolean).slice(0, 3);
                                            return g.length > 0 ? g.join(" / ") : "untagged";
                                        }
                                        font.pixelSize: 9
                                        font.italic: true
                                        color: settledColors.colOnLayer1
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }
                                }

                                Item { Layout.fillHeight: true }

                                // Reading Status Row (`.book-back-status`)
                                RowLayout {
                                    Layout.fillWidth: true
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: "Reading status"
                                        font.pixelSize: 9
                                        font.italic: true
                                        color: settledColors.colSubtext
                                    }
                                    StyledText {
                                        text: String(baseCardDelegate.modelData.status || "to read")
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        color: settledColors.colPrimary
                                    }
                                }

                                // Hatched Book Page Progress Bar (`.book-back-progress` in `02_Components.css` lines 2423–2465)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    readonly property int curPg: {
                                        const n = parseInt(String(baseCardDelegate.modelData.currentPage || "0"), 10);
                                        return Number.isFinite(n) ? Math.max(0, n) : 0;
                                    }
                                    readonly property int totPg: {
                                        const n = parseInt(String(baseCardDelegate.modelData.pages || "0"), 10);
                                        return Number.isFinite(n) ? Math.max(0, n) : 0;
                                    }
                                    readonly property int pct: {
                                        const st = String(baseCardDelegate.modelData.status || "").toLowerCase();
                                        if (st === "finished" || st === "completed" || st === "read" || st === "done")
                                            return 100;
                                        if (totPg > 0)
                                            return Math.max(0, Math.min(100, Math.round((curPg / totPg) * 100)));
                                        return 0;
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 8
                                        radius: 2
                                        color: Qt.color(root.ccStop(0))
                                        border.width: 1
                                        border.color: Qt.alpha(settledColors.colPrimary, 0.42)
                                        clip: true

                                        Canvas {
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            width: parent.width * (parent.parent.pct / 100.0)
                                            readonly property color _barCol: settledColors.colPrimary
                                            readonly property string _themeSig: root.themeSignature
                                            on_BarColChanged: if (visible) requestPaint()
                                            on_ThemeSigChanged: if (visible) requestPaint()
                                            onVisibleChanged: {
                                                if (visible)
                                                    requestPaint();
                                            }
                                            onWidthChanged: if (visible) requestPaint()
                                            onPaint: {
                                                const ctx = getContext("2d");
                                                ctx.clearRect(0, 0, width, height);
                                                if (width <= 0) return;
                                                ctx.fillStyle = Qt.alpha(settledColors.colPrimary, 0.35);
                                                ctx.fillRect(0, 0, width, height);
                                                ctx.strokeStyle = settledColors.colPrimary;
                                                ctx.lineWidth = 1.5;
                                                ctx.beginPath();
                                                for (let hx = -height; hx < width + height; hx += 5) {
                                                    ctx.moveTo(hx, height);
                                                    ctx.lineTo(hx + height, 0);
                                                }
                                                ctx.stroke();
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: {
                                                const st = String(baseCardDelegate.modelData.status || "").toLowerCase();
                                                const c = parent.parent.curPg;
                                                const t = parent.parent.totPg;
                                                if ((st === "finished" || st === "completed") && c === 0 && t > 0)
                                                    return String(t) + " / " + String(t) + " pages";
                                                return String(c) + " / " + String(t) + " pages";
                                            }
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 8
                                            color: settledColors.colSubtext
                                        }
                                        StyledText {
                                            text: String(parent.parent.pct) + "%"
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 8
                                            font.weight: Font.Bold
                                            color: settledColors.colPrimary
                                        }
                                    }
                                }

                                // Rating Footer Row (`.book-back-rating` with tilted hand-drawn stars)
                                RowLayout {
                                    Layout.fillWidth: true
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: "Rating"
                                        font.pixelSize: 9
                                        font.italic: true
                                        color: settledColors.colSubtext
                                    }
                                    StyledText {
                                        rotation: -2
                                        text: {
                                            const raw = String(baseCardDelegate.modelData.ratingRaw || baseCardDelegate.modelData.score || "");
                                            if (!raw || raw === "0")
                                                return "not rated";
                                            return collectionViewRoot._starsForScore(baseCardDelegate.modelData.score);
                                        }
                                        font.pixelSize: 10
                                        color: settledColors.colPrimary
                                    }
                                }
                            }
                        }
                    }

                    // ── 5. RECIPES: RIBBON & INGREDIENTS CARD (`FoodnDrinks.base` & `02_Components.css` L319–1075 `.rc-card`) ──
                    Rectangle {
                        id: rcBaseCard
                        objectName: "nexusRecipeBaseCard_" + String(baseCardDelegate.index)
                        visible: baseCardDelegate.isRecipeCard
                        anchors.fill: parent
                        radius: 12
                        color: Qt.color(root.ccStop(2))
                        border.width: 1
                        border.color: baseCardHover.hovered
                            ? Qt.alpha(settledColors.colPrimary, 0.58)
                            : settledColors.colLayer0Border
                        clip: true

                        readonly property string rcCategoryRaw: String(
                            baseCardDelegate.modelData.category
                            || baseCardDelegate.modelData.genre
                            || "Recipe"
                        ).trim()
                        readonly property string rcCategoryLabel: rcCategoryRaw.length > 0 ? rcCategoryRaw.toUpperCase() : "RECIPE"
                        readonly property string rcCategoryIcon: {
                            const k = rcCategoryRaw.toLowerCase();
                            if (k.indexOf("drink") !== -1 || k.indexOf("beverage") !== -1 || k.indexOf("cocktail") !== -1)
                                return "local_bar";
                            if (k.indexOf("dessert") !== -1 || k.indexOf("sweet") !== -1 || k.indexOf("cake") !== -1 || k.indexOf("bake") !== -1)
                                return "cake";
                            if (k.indexOf("soup") !== -1 || k.indexOf("stew") !== -1 || k.indexOf("ramen") !== -1)
                                return "soup_kitchen";
                            if (k.indexOf("salad") !== -1 || k.indexOf("veg") !== -1)
                                return "eco";
                            if (k.indexOf("breakfast") !== -1 || k.indexOf("brunch") !== -1)
                                return "bakery_dining";
                            return "restaurant";
                        }
                        readonly property real rcCaloriesNum: {
                            const mDirect = /(\d+(?:\.\d+)?)/.exec(String(baseCardDelegate.modelData.calories ?? ""));
                            if (mDirect && parseFloat(mDirect[1]) > 0)
                                return parseFloat(mDirect[1]);
                            const plot = String(baseCardDelegate.modelData.plot ?? "");
                            const mPlot = /(\d+(?:\.\d+)?)\s*(?:calories|kcal)\b/i.exec(plot);
                            return mPlot ? parseFloat(mPlot[1]) : 0;
                        }
                        readonly property var rcMacroChips: {
                            const plot = String(baseCardDelegate.modelData.plot ?? "");
                            const chips = [];
                            if (rcCaloriesNum > 0)
                                chips.push(String(Math.round(rcCaloriesNum)) + " kcal");
                            const mProt = /(\d+(?:\.\d+)?)\s*g\s+(?:of\s+)?protein\b/i.exec(plot);
                            const prot = mProt ? parseFloat(mProt[1]) : 0;
                            if (prot > 0)
                                chips.push(String(Math.round(prot)) + "g P");
                            const mFat = /(\d+(?:\.\d+)?)\s*g\s+(?:of\s+)?fat\b/i.exec(plot);
                            const fat = mFat ? parseFloat(mFat[1]) : 0;
                            if (fat > 0)
                                chips.push(String(Math.round(fat)) + "g F");
                            const mCarbs = /(\d+(?:\.\d+)?)\s*g\s+(?:of\s+)?(?:carbs|carbohydrates)\b/i.exec(plot);
                            if (mCarbs && parseFloat(mCarbs[1]) > 0) {
                                chips.push(String(Math.round(parseFloat(mCarbs[1]))) + "g C");
                            } else if (rcCaloriesNum > 0 && (prot > 0 || fat > 0)) {
                                const remCal = rcCaloriesNum - (prot * 4.0 + fat * 9.0);
                                if (remCal > 4)
                                    chips.push("~" + String(Math.round(remCal / 4.0)) + "g C");
                            }
                            return chips;
                        }
                        readonly property string rcTimeDisplay: {
                            const parseMin = (v) => {
                                const m = /(\d+(?:\.\d+)?)/.exec(String(v ?? ""));
                                return m ? parseFloat(m[1]) : 0;
                            };
                            const prep = parseMin(baseCardDelegate.modelData.prepTime);
                            const cook = parseMin(baseCardDelegate.modelData.cookTime);
                            const total = prep + cook;
                            if (total > 0)
                                return String(Math.round(total)) + " min";
                            const rt = String(baseCardDelegate.modelData.runtime ?? "").trim();
                            if (rt.length > 0 && rt !== "0" && rt !== "0 min")
                                return /^\d+$/.test(rt) ? (rt + " min") : rt;
                            const plot = String(baseCardDelegate.modelData.plot ?? "");
                            const mPlot = /(?:takes?\s+(?:around|about)|in\s+(?:around|about)|ready\s+in)\s+(\d+)\s*(?:minutes|mins|min)\b/i.exec(plot);
                            if (mPlot && mPlot[1])
                                return mPlot[1] + " min";
                            return "Flexible";
                        }
                        readonly property string rcTagline: {
                            const sub = String(
                                baseCardDelegate.modelData.subtitle
                                || baseCardDelegate.modelData.tagline
                                || baseCardDelegate.modelData.cuisine
                                || ""
                            ).trim();
                            if (sub.length > 0)
                                return sub;
                            const cat = rcCategoryRaw;
                            if (rcCaloriesNum > 0)
                                return cat + " · " + String(Math.round(rcCaloriesNum)) + " kcal";
                            return cat + " · Culinary Collection";
                        }
                        readonly property string rcDifficulty: {
                            const raw = String(baseCardDelegate.modelData.difficulty || baseCardDelegate.modelData.status || "Easy").trim();
                            if (raw.length === 0)
                                return "Easy";
                            return raw.charAt(0).toUpperCase() + raw.slice(1);
                        }
                        readonly property color rcDifficultyColor: {
                            const d = rcDifficulty.toLowerCase();
                            if (d.indexOf("hard") !== -1 || d.indexOf("challeng") !== -1)
                                return Qt.color("#eb6f92");
                            if (d.indexOf("med") !== -1 || d.indexOf("inter") !== -1)
                                return Qt.color("#f6c177");
                            return settledColors.colTertiary ?? Qt.color("#81be99");
                        }
                        readonly property var rcIngredientItems: {
                            const arr = baseCardDelegate.modelData.ingredients;
                            if (Array.isArray(arr) && arr.length > 0) {
                                const out = [];
                                for (let i = 0; i < arr.length && out.length < 9; ++i) {
                                    const s = String(arr[i] ?? "").trim();
                                    if (s.length > 0)
                                        out.push(s);
                                }
                                if (out.length > 0)
                                    return out;
                            }
                            const plot = String(baseCardDelegate.modelData.plot ?? "").trim();
                            if (plot.length > 0) {
                                const parts = plot.split(/\r?\n|•|·|;/);
                                const out = [];
                                for (let i = 0; i < parts.length && out.length < 8; ++i) {
                                    const clean = parts[i].replace(/^[-*]\s*/, "").trim();
                                    if (clean.length > 0)
                                        out.push(clean);
                                }
                                if (out.length > 0)
                                    return out;
                            }
                            return ["Click to open full recipe ingredients & step-by-step instructions"];
                        }

                        // ── FRONT FACE (`.rc-front`) ──
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0
                            visible: !baseCardDelegate.showBack

                            // Cover Media Container (`aspect-ratio: 3 / 2`, clips Spoonacular baked-in white margins)
                            Rectangle {
                                id: rcImageFrame
                                objectName: "nexusRecipeBaseCover_" + String(baseCardDelegate.index)
                                Layout.fillWidth: true
                                Layout.preferredHeight: 162
                                color: Qt.color(root.ccStop(1))
                                clip: true

                                // Fallback culinary icon when image is missing
                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    visible: !rcCoverImage.visible
                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: rcBaseCard.rcCategoryIcon
                                        iconSize: 32
                                        color: Qt.alpha(settledColors.colPrimary, 0.45)
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: rcBaseCard.rcCategoryLabel
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 9
                                        color: settledColors.colSubtext
                                    }
                                }

                                Image {
                                    id: rcCoverImage
                                    objectName: "nexusRecipeBaseCoverImage_" + String(baseCardDelegate.index)
                                    anchors.fill: parent
                                    source: String(baseCardDelegate.modelData.posterUrl ?? "")
                                    sourceSize: Qt.size(480, 360)
                                    fillMode: Image.PreserveAspectCrop
                                    horizontalAlignment: Image.AlignHCenter
                                    verticalAlignment: Image.AlignVCenter
                                    asynchronous: true
                                    cache: false
                                    // Spoonacular 556x370 cover JPEGs have 48px solid white sidebars baked into the image file;
                                    // 1.18x scale inside `clip: true` cleanly crops out the white sidebars on both left & right edges.
                                    readonly property real baseCropScale: String(source).indexOf("spoonacular-") !== -1 ? 1.18 : 1.02
                                    scale: baseCropScale * (baseCardHover.hovered ? 1.03 : 1.0)
                                    Behavior on scale {
                                        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                                    }
                                    visible: Boolean(baseCardDelegate.modelData.posterUrl) && status === Image.Ready
                                }

                                // Subtle bottom vignette for time pill legibility
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 44
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: "transparent" }
                                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.52) }
                                    }
                                }

                                // Top-left Category Ribbon (`.rc-ribbon`)
                                Rectangle {
                                    x: 12
                                    y: 0
                                    width: Math.max(46, rcRibbonCol.implicitWidth + 14)
                                    height: 36
                                    radius: 5
                                    color: settledColors.colPrimary
                                    border.width: 1
                                    border.color: Qt.alpha(settledColors.colOnPrimary, 0.16)

                                    // Top square cover so ribbon drops flush from top edge
                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        height: 5
                                        color: parent.color
                                    }

                                    ColumnLayout {
                                        id: rcRibbonCol
                                        anchors.centerIn: parent
                                        spacing: 1

                                        MaterialSymbol {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: rcBaseCard.rcCategoryIcon
                                            iconSize: 13
                                            color: settledColors.colOnPrimary
                                        }
                                        StyledText {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: rcBaseCard.rcCategoryLabel
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 8
                                            font.weight: Font.Black
                                            font.letterSpacing: 0.4
                                            color: settledColors.colOnPrimary
                                        }
                                    }
                                }

                                // Top-right Favorite Heart Badge (`.rc-favorite`)
                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 8
                                    width: 24
                                    height: 24
                                    radius: 12
                                    visible: Boolean(baseCardDelegate.modelData.favorite) || Number(baseCardDelegate.modelData.score ?? 0) >= 8 || baseCardHover.hovered
                                    color: Boolean(baseCardDelegate.modelData.favorite)
                                        ? Qt.rgba(0.92, 0.44, 0.57, 0.90)
                                        : Qt.alpha(Qt.color(root.ccStop(0)), 0.72)
                                    border.width: 1
                                    border.color: Boolean(baseCardDelegate.modelData.favorite)
                                        ? "transparent"
                                        : Qt.alpha(settledColors.colPrimary, 0.35)

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: Boolean(baseCardDelegate.modelData.favorite) ? "favorite" : "favorite_border"
                                        iconSize: 13
                                        color: Boolean(baseCardDelegate.modelData.favorite) ? "#ffffff" : settledColors.colPrimary
                                    }
                                }

                                // Bottom-left Time Pill (`.rc-time`)
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.bottom: parent.bottom
                                    anchors.leftMargin: 10
                                    anchors.bottomMargin: 8
                                    height: 22
                                    width: rcTimeRow.implicitWidth + 14
                                    radius: 11
                                    color: Qt.alpha(Qt.color(root.ccStop(2)), 0.92)
                                    border.width: 1
                                    border.color: Qt.alpha(settledColors.colPrimary, 0.38)

                                    RowLayout {
                                        id: rcTimeRow
                                        anchors.centerIn: parent
                                        spacing: 4

                                        MaterialSymbol {
                                            text: "schedule"
                                            iconSize: 11
                                            color: settledColors.colPrimary
                                        }
                                        StyledText {
                                            text: rcBaseCard.rcTimeDisplay
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                            color: settledColors.colOnLayer0
                                        }
                                    }
                                }

                                // Bottom-right Calories Pill (when available)
                                Rectangle {
                                    objectName: "nexusRecipeBaseCaloriesPill_" + String(baseCardDelegate.index)
                                    visible: rcBaseCard.rcCaloriesNum > 0
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.rightMargin: 10
                                    anchors.bottomMargin: 8
                                    height: 22
                                    width: rcCalRow.implicitWidth + 12
                                    radius: 11
                                    color: Qt.alpha(Qt.color(root.ccStop(0)), 0.84)
                                    border.width: 1
                                    border.color: settledColors.colLayer0Border

                                    RowLayout {
                                        id: rcCalRow
                                        anchors.centerIn: parent
                                        spacing: 3

                                        MaterialSymbol {
                                            text: "local_fire_department"
                                            iconSize: 11
                                            color: settledColors.colPrimary
                                        }
                                        StyledText {
                                            text: String(Math.round(rcBaseCard.rcCaloriesNum)) + " kcal"
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 9
                                            color: settledColors.colSubtext
                                        }
                                    }
                                }
                            }

                            // Body Section (`.rc-body`)
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                // Subtle Right Culinary Flourish (`.rc-flourish`)
                                MaterialSymbol {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.rightMargin: 8
                                    anchors.bottomMargin: 34
                                    text: "restaurant_menu"
                                    iconSize: 48
                                    color: settledColors.colPrimary
                                    opacity: 0.07
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    anchors.topMargin: 10
                                    anchors.bottomMargin: 8
                                    spacing: 4

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: String(baseCardDelegate.modelData.title ?? "")
                                        font.family: Appearance.font.family.reading || Appearance.font.family.main
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                        color: settledColors.colOnLayer0
                                        wrapMode: Text.WordWrap
                                        elide: Text.ElideRight
                                        maximumLineCount: 2
                                        lineHeight: 1.15
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: rcBaseCard.rcTagline
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 10
                                        color: settledColors.colPrimary
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }

                                    RowLayout {
                                        objectName: "nexusRecipeBaseMacroRow_" + String(baseCardDelegate.index)
                                        visible: rcBaseCard.rcMacroChips.length > 0
                                        Layout.fillWidth: true
                                        spacing: 4

                                        Repeater {
                                            model: rcBaseCard.rcMacroChips.slice(0, 4)
                                            delegate: Rectangle {
                                                required property string modelData
                                                height: 17
                                                width: rcMacroChipTxt.implicitWidth + 10
                                                radius: 8.5
                                                color: Qt.alpha(Qt.color(root.ccStop(2)), 0.72)
                                                border.width: 1
                                                border.color: settledColors.colLayer0Border

                                                StyledText {
                                                    id: rcMacroChipTxt
                                                    anchors.centerIn: parent
                                                    text: modelData
                                                    font.family: Appearance.font.family.monospace
                                                    font.pixelSize: 8
                                                    font.weight: Font.DemiBold
                                                    color: settledColors.colSubtext
                                                }
                                            }
                                        }
                                    }

                                    Item { Layout.fillHeight: true }

                                    // Top keyline divider above `.rc-footer`
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 1
                                        color: settledColors.colLayer0Border
                                    }

                                    // Footer Bar (`.rc-footer`: Servings + Rating on left; Cooking Difficulty cleanly RIGHT-ALIGNED)
                                    RowLayout {
                                        objectName: "nexusRecipeFrontFooter_" + String(baseCardDelegate.index)
                                        Layout.fillWidth: true
                                        Layout.topMargin: 4
                                        spacing: 6

                                        // Left: Servings
                                        RowLayout {
                                            spacing: 4
                                            MaterialSymbol {
                                                text: "group"
                                                iconSize: 12
                                                color: settledColors.colSubtext
                                            }
                                            StyledText {
                                                text: String(baseCardDelegate.modelData.servings || 2) + " srv"
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                                color: settledColors.colOnLayer1
                                            }
                                        }

                                        // Optional Rating pill beside servings
                                        RowLayout {
                                            visible: Number(baseCardDelegate.modelData.score ?? 0) > 0
                                            spacing: 2
                                            MaterialSymbol {
                                                text: "star"
                                                iconSize: 12
                                                color: settledColors.colPrimary
                                            }
                                            StyledText {
                                                text: String(baseCardDelegate.modelData.score ?? "")
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                                color: settledColors.colPrimary
                                            }
                                        }

                                        Item {
                                            Layout.fillWidth: true
                                        }

                                        // Right-Aligned Cooking Difficulty Pill
                                        Rectangle {
                                            objectName: "nexusRecipeDifficultyRightPill_" + String(baseCardDelegate.index)
                                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                            height: 20
                                            width: rcDiffRow.implicitWidth + 10
                                            radius: 6
                                            color: Qt.alpha(rcBaseCard.rcDifficultyColor, 0.14)
                                            border.width: 1
                                            border.color: Qt.alpha(rcBaseCard.rcDifficultyColor, 0.38)

                                            RowLayout {
                                                id: rcDiffRow
                                                anchors.centerIn: parent
                                                spacing: 3
                                                MaterialSymbol {
                                                    text: "equalizer"
                                                    iconSize: 11
                                                    color: rcBaseCard.rcDifficultyColor
                                                }
                                                StyledText {
                                                    text: rcBaseCard.rcDifficulty
                                                    font.family: Appearance.font.family.monospace
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                    color: rcBaseCard.rcDifficultyColor
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ── BACK FACE: RICH CULINARY RECIPE DOSSIER (`.rc-back`) ──
                        Rectangle {
                            id: rcBackFace
                            objectName: "nexusRecipeBackFace_" + String(baseCardDelegate.index)
                            anchors.fill: parent
                            anchors.margins: 6
                            visible: baseCardDelegate.showBack
                            radius: 10
                            color: settledColors.colLayer1
                            border.width: 1
                            border.color: Qt.alpha(settledColors.colPrimary, 0.40)
                            clip: true

                            // Subtle top accent band
                            Rectangle {
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 3
                                color: settledColors.colPrimary
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 11
                                anchors.rightMargin: 11
                                anchors.topMargin: 11
                                anchors.bottomMargin: 9
                                spacing: 7

                                // 1. Culinary Header: Title + Category Pill
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Rectangle {
                                        Layout.preferredWidth: 26
                                        Layout.preferredHeight: 26
                                        radius: 7
                                        color: Qt.alpha(settledColors.colPrimary, 0.16)
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: rcBaseCard.rcCategoryIcon
                                            iconSize: 14
                                            color: settledColors.colPrimary
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: String(baseCardDelegate.modelData.title ?? "")
                                            font.family: Appearance.font.family.reading || Appearance.font.family.main
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                            color: settledColors.colOnLayer0
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: rcBaseCard.rcCategoryLabel + (rcBaseCard.rcCaloriesNum > 0 ? (" · " + String(Math.round(rcBaseCard.rcCaloriesNum)) + " kcal") : "")
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 9
                                            font.weight: Font.DemiBold
                                            color: settledColors.colPrimary
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                // 2. Structured 3-Stat Culinary Strip (Time | Servings | Difficulty)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Repeater {
                                        model: [
                                            { "icon": "schedule", "lbl": rcBaseCard.rcTimeDisplay, "col": String(settledColors.colOnLayer1) },
                                            { "icon": "group", "lbl": String(baseCardDelegate.modelData.servings || 2) + " srv", "col": String(settledColors.colOnLayer1) },
                                            { "icon": "equalizer", "lbl": rcBaseCard.rcDifficulty, "col": String(rcBaseCard.rcDifficultyColor) }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 24
                                            radius: 6
                                            color: settledColors.colLayer2
                                            border.width: 1
                                            border.color: settledColors.colLayer0Border

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 3
                                                MaterialSymbol {
                                                    text: modelData.icon
                                                    iconSize: 11
                                                    color: Qt.color(modelData.col)
                                                }
                                                StyledText {
                                                    text: modelData.lbl
                                                    font.family: Appearance.font.family.monospace
                                                    font.pixelSize: 9
                                                    font.weight: Font.DemiBold
                                                    color: Qt.color(modelData.col)
                                                }
                                            }
                                        }
                                    }
                                }

                                // 3. Ingredients Checklist Section with Count Pill
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 5
                                    MaterialSymbol {
                                        text: "shopping_basket"
                                        iconSize: 12
                                        color: settledColors.colPrimary
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: "INGREDIENTS"
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0.9
                                        color: settledColors.colPrimary
                                    }
                                    Rectangle {
                                        height: 16
                                        width: ingCountTxt.implicitWidth + 8
                                        radius: 8
                                        color: settledColors.colSecondaryContainer
                                        StyledText {
                                            id: ingCountTxt
                                            anchors.centerIn: parent
                                            text: String(rcBaseCard.rcIngredientItems.length)
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            color: settledColors.colOnSecondaryContainer
                                        }
                                    }
                                }

                                // Ingredients Container (stepped tonal inset card with word-wrapped entries)
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 7
                                    color: settledColors.colLayer0
                                    border.width: 1
                                    border.color: settledColors.colLayer0Border
                                    clip: true

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 4

                                        Repeater {
                                            model: rcBaseCard.rcIngredientItems.slice(0, 7)
                                            delegate: RowLayout {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                spacing: 6

                                                Rectangle {
                                                    width: 5
                                                    height: 5
                                                    radius: 2.5
                                                    color: settledColors.colPrimary
                                                    Layout.alignment: Qt.AlignTop
                                                    Layout.topMargin: 4
                                                }
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: String(modelData)
                                                    font.pixelSize: 10
                                                    color: settledColors.colOnLayer1
                                                    wrapMode: Text.WordWrap
                                                    elide: Text.ElideRight
                                                    maximumLineCount: 2
                                                }
                                            }
                                        }

                                        // Optional Chef Notes / Summary when ingredients list is brief
                                        StyledText {
                                            visible: rcBaseCard.rcIngredientItems.length <= 3 && collectionViewRoot._cleanExcerpt(baseCardDelegate.modelData.description || baseCardDelegate.modelData.plot || "").length > 0
                                            Layout.fillWidth: true
                                            Layout.topMargin: 4
                                            text: collectionViewRoot._cleanExcerpt(baseCardDelegate.modelData.description || baseCardDelegate.modelData.plot || "")
                                            font.pixelSize: 9
                                            font.italic: true
                                            color: settledColors.colSubtext
                                            wrapMode: Text.WordWrap
                                            elide: Text.ElideRight
                                            maximumLineCount: 3
                                        }

                                        Item { Layout.fillHeight: true }
                                    }
                                }

                                // 4. Footer Hint
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: rcBaseCard.rcMacroChips.length > 0 ? rcBaseCard.rcMacroChips.slice(0, 3).join(" · ") : "Open recipe steps & notes"
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 9
                                        color: settledColors.colSubtext
                                        elide: Text.ElideRight
                                    }
                                    MaterialSymbol {
                                        text: "arrow_forward"
                                        iconSize: 12
                                        color: settledColors.colPrimary
                                    }
                                }
                            }
                        }
                    }

                    // ── 6. EXERCISES: BODYBUILDING ATLAS CARD (`Bodybuilding.base` & `02_Components.css` L1332–1620 `.ex-card`) ──
                    Rectangle {
                        id: exBaseCard
                        objectName: "nexusExerciseBaseCard_" + String(baseCardDelegate.index)
                        visible: baseCardDelegate.isExerciseCard
                        anchors.fill: parent
                        radius: 14
                        color: "#0b0f14"
                        border.width: 1
                        border.color: baseCardHover.hovered
                            ? Qt.rgba(settledColors.colPrimary.r, settledColors.colPrimary.g, settledColors.colPrimary.b, 0.56)
                            : Qt.rgba(1, 1, 1, 0.10)
                        clip: true

                        property bool exDemoPlaying: false
                        readonly property string rawLevel: String(baseCardDelegate.modelData.level || baseCardDelegate.modelData.difficulty || "intermediate").trim().toLowerCase()
                        readonly property string normLevel: (rawLevel === "expert" || rawLevel === "advanced")
                            ? "advanced"
                            : (rawLevel === "beginner" ? "beginner" : "intermediate")
                        readonly property string levelBadgeText: normLevel === "advanced"
                            ? "Advanced"
                            : (normLevel === "beginner" ? "Beginner" : "Intermediate")
                        readonly property color levelBadgeColor: normLevel === "advanced"
                            ? Qt.rgba(0.97, 0.46, 0.56, 1.0)
                            : (normLevel === "beginner" ? Qt.rgba(0.62, 0.81, 0.42, 1.0) : Qt.rgba(0.88, 0.69, 0.41, 1.0))
                        readonly property string primaryMuscleText: {
                            const m = String(baseCardDelegate.modelData.muscleGroup || baseCardDelegate.modelData.genre || "").trim();
                            if (!m)
                                return "Full Body";
                            return m.replace(/[_-]+/g, " ").replace(/\b\w/g, c => c.toUpperCase());
                        }
                        readonly property string equipmentText: {
                            const eq = String(baseCardDelegate.modelData.equipment || baseCardDelegate.modelData.director || "").trim();
                            if (!eq)
                                return "Body Only";
                            return eq.replace(/[_-]+/g, " ").replace(/\b\w/g, c => c.toUpperCase());
                        }
                        readonly property string animUrl: String(baseCardDelegate.modelData.featuredImageUrl || "")

                        // Front Face: Full-bleed image + dark top/bottom gradient + .ex-card-top + .ex-card-copy
                        Item {
                            anchors.fill: parent
                            visible: !baseCardDelegate.flipped

                            Rectangle {
                                anchors.fill: parent
                                color: "#0b0f14"
                            }

                            Image {
                                id: exPosterImg
                                anchors.fill: parent
                                source: baseCardDelegate.isExerciseCard ? String(baseCardDelegate.modelData.posterUrl ?? "") : ""
                                sourceSize: Qt.size(320, 268)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                visible: Boolean(baseCardDelegate.modelData.posterUrl) && status === Image.Ready && (!exBaseCard.exDemoPlaying || !exCardAnimImg.visible)
                            }

                            AnimatedImage {
                                id: exCardAnimImg
                                anchors.fill: parent
                                source: (baseCardDelegate.isExerciseCard && exBaseCard.exDemoPlaying && exBaseCard.animUrl.length > 0) ? exBaseCard.animUrl : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                playing: exBaseCard.visible && exBaseCard.exDemoPlaying && !root.screenshotOverlayActive
                                visible: exBaseCard.exDemoPlaying && exBaseCard.animUrl.length > 0 && status === AnimatedImage.Ready
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: !exPosterImg.visible && !exCardAnimImg.visible
                                text: "fitness_center"
                                iconSize: 40
                                color: Qt.rgba(settledColors.colPrimary.r, settledColors.colPrimary.g, settledColors.colPrimary.b, 0.55)
                            }

                            // Top & bottom cinema/fitness dark shade gradient overlay (.ex-card::after)
                            Rectangle {
                                anchors.fill: parent
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.rgba(0.03, 0.05, 0.06, 0.72) }
                                    GradientStop { position: 0.34; color: Qt.rgba(0.03, 0.05, 0.06, 0.10) }
                                    GradientStop { position: 0.58; color: Qt.rgba(0.03, 0.05, 0.06, 0.16) }
                                    GradientStop { position: 1.0; color: Qt.rgba(0.03, 0.05, 0.06, 0.92) }
                                }
                            }

                            // .ex-card-top: Level pill on left + circular Play button on right
                            RowLayout {
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: 10
                                spacing: 8

                                Rectangle {
                                    height: 24
                                    width: exCardLevelRow.implicitWidth + 16
                                    radius: 12
                                    color: Qt.rgba(0.04, 0.06, 0.08, 0.76)
                                    border.width: 1
                                    border.color: Qt.rgba(exBaseCard.levelBadgeColor.r, exBaseCard.levelBadgeColor.g, exBaseCard.levelBadgeColor.b, 0.42)

                                    RowLayout {
                                        id: exCardLevelRow
                                        anchors.centerIn: parent
                                        spacing: 6

                                        Rectangle {
                                            width: 6
                                            height: 6
                                            radius: 3
                                            color: exBaseCard.levelBadgeColor
                                        }

                                        StyledText {
                                            text: exBaseCard.levelBadgeText
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            color: Qt.lighter(exBaseCard.levelBadgeColor, 1.18)
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                Rectangle {
                                    id: exCardPlayBtn
                                    objectName: "nexusExerciseBaseCardPlay_" + String(baseCardDelegate.index)
                                    visible: exBaseCard.animUrl.length > 0
                                    width: 28
                                    height: 28
                                    radius: 14
                                    color: exBaseCard.exDemoPlaying
                                        ? Qt.rgba(settledColors.colPrimary.r, settledColors.colPrimary.g, settledColors.colPrimary.b, 0.24)
                                        : Qt.rgba(0.04, 0.06, 0.08, 0.76)
                                    border.width: 1
                                    border.color: exBaseCard.exDemoPlaying
                                        ? Qt.rgba(settledColors.colPrimary.r, settledColors.colPrimary.g, settledColors.colPrimary.b, 0.62)
                                        : Qt.rgba(1, 1, 1, 0.16)

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: exBaseCard.exDemoPlaying ? "pause" : "play_arrow"
                                        iconSize: 16
                                        color: exBaseCard.exDemoPlaying ? settledColors.colPrimary : "#f5f7fa"
                                    }
                                }
                            }

                            // .ex-card-copy: Bottom title + 2-column primary muscle & equipment row
                            ColumnLayout {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 12
                                spacing: 7

                                StyledText {
                                    Layout.fillWidth: true
                                    text: String(baseCardDelegate.modelData.title ?? "")
                                    font.pixelSize: 15
                                    font.weight: Font.ExtraBold
                                    color: "#f5f7fa"
                                    wrapMode: Text.WordWrap
                                    elide: Text.ElideRight
                                    maximumLineCount: 2
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 5

                                        Canvas {
                                            Layout.preferredWidth: 13
                                            Layout.preferredHeight: 13
                                            property string muscleName: exBaseCard.primaryMuscleText
                                            property color iconColor: settledColors.colPrimary
                                            onMuscleNameChanged: if (visible) requestPaint()
                                            onIconColorChanged: if (visible) requestPaint()
                                            onVisibleChanged: if (visible) requestPaint()
                                            onPaint: {
                                                var ctx = getContext("2d");
                                                ExerciseAnatomyData.paintMiniMuscleIcon(ctx, width, height, muscleName, "rgba(210, 224, 230, 0.42)", iconColor.toString());
                                            }
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: exBaseCard.primaryMuscleText
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            color: Qt.rgba(0.89, 0.93, 0.96, 0.86)
                                            elide: Text.ElideRight
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 5

                                        Canvas {
                                            Layout.preferredWidth: 13
                                            Layout.preferredHeight: 13
                                            property string equipName: exBaseCard.equipmentText
                                            property color iconColor: settledColors.colPrimary
                                            onEquipNameChanged: if (visible) requestPaint()
                                            onIconColorChanged: if (visible) requestPaint()
                                            onVisibleChanged: if (visible) requestPaint()
                                            onPaint: {
                                                var ctx = getContext("2d");
                                                ExerciseAnatomyData.paintEquipmentIcon(ctx, width, height, equipName, iconColor.toString());
                                            }
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: exBaseCard.equipmentText
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            color: Qt.rgba(0.89, 0.93, 0.96, 0.86)
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }

                        // Exercise Back Face (`ex-card` right-click flip)
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            visible: baseCardDelegate.flipped
                            spacing: 4

                            StyledText {
                                text: "MOVEMENT LIBRARY"
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                font.letterSpacing: 1.6
                                color: settledColors.colPrimary
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: String(baseCardDelegate.modelData.title ?? "")
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                color: "#eef3f6"
                                elide: Text.ElideRight
                            }
                            Repeater {
                                model: [
                                    { "k": "PRIMARY", "v": exBaseCard.primaryMuscleText },
                                    { "k": "EQUIPMENT", "v": exBaseCard.equipmentText },
                                    { "k": "LEVEL", "v": exBaseCard.levelBadgeText },
                                    { "k": "CATEGORY", "v": String(baseCardDelegate.modelData.category || "Strength") }
                                ]
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    StyledText { Layout.preferredWidth: 68; text: modelData.k; font.family: Appearance.font.family.monospace; font.pixelSize: 9; font.weight: Font.Bold; color: settledColors.colPrimary }
                                    StyledText { Layout.fillWidth: true; text: modelData.v; font.family: Appearance.font.family.monospace; font.pixelSize: 9; color: "#dde5ea"; elide: Text.ElideRight }
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                text: String(baseCardDelegate.modelData.plot || "Click to open Movement Library exercise view...")
                                font.pixelSize: 9
                                color: "#c0c8d6"
                                wrapMode: Text.WordWrap
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // ── 7. PLACES: MAP & PLACE DOSSIER CARD (`Map.base`, `Places.base` & `02_Components.css` L1899–2269) ──
                    Rectangle {
                        objectName: "nexusPlaceBaseCard_" + String(baseCardDelegate.index)
                        visible: baseCardDelegate.isPlaceCard
                        anchors.fill: parent
                        radius: 10
                        color: settledColors.colLayer1
                        border.width: 1
                        border.color: baseCardHover.hovered ? settledColors.colPrimary : settledColors.colLayer0Border
                        clip: true

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0
                            visible: !baseCardDelegate.showBack

                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 132
                                clip: true

                                Rectangle {
                                    anchors.fill: parent
                                    color: settledColors.colLayer0
                                }

                                Image {
                                    id: placePosterImg
                                    anchors.fill: parent
                                    source: String(baseCardDelegate.modelData.posterUrl ?? "")
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    visible: Boolean(baseCardDelegate.modelData.posterUrl) && status === Image.Ready
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: !placePosterImg.visible
                                    text: "place"
                                    iconSize: 34
                                    color: settledColors.colPrimary
                                }

                                Rectangle {
                                    x: 10
                                    y: 10
                                    height: 22
                                    width: plCatTxt.implicitWidth + 12
                                    radius: 4
                                    color: settledColors.colPrimary
                                    StyledText {
                                        id: plCatTxt
                                        anchors.centerIn: parent
                                        text: String(baseCardDelegate.modelData.category || "PLACE").toUpperCase()
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 10
                                        font.weight: Font.Black
                                        color: settledColors.colOnPrimary
                                    }
                                }

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 8
                                    height: 22
                                    width: plStatTxt.implicitWidth + 12
                                    radius: 10
                                    color: Qt.rgba(settledColors.colLayer0.r, settledColors.colLayer0.g, settledColors.colLayer0.b, 0.90)
                                    border.width: 1
                                    border.color: settledColors.colPrimary
                                    StyledText {
                                        id: plStatTxt
                                        anchors.centerIn: parent
                                        text: String(baseCardDelegate.modelData.status || "VISITED").toUpperCase()
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        color: settledColors.colPrimary
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.margins: 10
                                spacing: 4

                                StyledText {
                                    Layout.fillWidth: true
                                    text: String(baseCardDelegate.modelData.title ?? "")
                                    font.pixelSize: 14
                                    font.weight: Font.Bold
                                    color: settledColors.colOnLayer1
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: String(baseCardDelegate.modelData.location || "—")
                                    font.pixelSize: 11
                                    color: settledColors.colSubtext
                                    elide: Text.ElideRight
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: collectionViewRoot._placeCoordinates(baseCardDelegate.modelData)
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 10
                                        color: settledColors.colPrimary
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        text: collectionViewRoot._starsForScore(baseCardDelegate.modelData.score)
                                        font.pixelSize: 11
                                        color: settledColors.colTertiary ?? settledColors.colPrimary
                                    }
                                }
                            }
                        }

                        // Place Back Face (`map-place-back`)
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            visible: baseCardDelegate.showBack
                            spacing: 4

                            StyledText {
                                text: "PLACE DOSSIER"
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                font.letterSpacing: 1.6
                                color: settledColors.colPrimary
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: String(baseCardDelegate.modelData.title ?? "")
                                font.pixelSize: 14
                                font.weight: Font.Bold
                                color: settledColors.colOnLayer1
                                elide: Text.ElideRight
                            }
                            Repeater {
                                model: [
                                    { "k": "CATEGORY", "v": String(baseCardDelegate.modelData.category || "Place") },
                                    { "k": "STATUS", "v": String(baseCardDelegate.modelData.status || "Visited") },
                                    { "k": "ADDRESS", "v": String(baseCardDelegate.modelData.location || "—") },
                                    { "k": "COORDS", "v": collectionViewRoot._placeCoordinates(baseCardDelegate.modelData) || "—" }
                                ]
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    StyledText { Layout.preferredWidth: 64; text: modelData.k; font.family: Appearance.font.family.monospace; font.pixelSize: 10; font.weight: Font.Bold; color: settledColors.colPrimary }
                                    StyledText { Layout.fillWidth: true; text: modelData.v; font.family: Appearance.font.family.monospace; font.pixelSize: 10; color: settledColors.colOnLayer1; elide: Text.ElideRight }
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                text: String(baseCardDelegate.modelData.plot || "Click to open place note...")
                                font.pixelSize: 10
                                color: settledColors.colSubtext
                                wrapMode: Text.WordWrap
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // ── 8A. CORNELL STUDY NOTE SHEET CARD (Two-Column Cue | Notes Layout + Summary Footer Band) ──
                    Rectangle {
                        id: cornellBaseCard
                        objectName: "nexusCornellBaseCard_" + String(baseCardDelegate.index)
                        visible: baseCardDelegate.isCornellCard
                        anchors.fill: parent
                        radius: 11
                        color: baseCardHover.hovered ? settledColors.colLayer2Hover : settledColors.colLayer1
                        border.width: 1
                        border.color: baseCardHover.hovered ? settledColors.colPrimary : settledColors.colLayer0Border
                        clip: true

                        readonly property var itemTags: Array.isArray(baseCardDelegate.modelData.tags) ? baseCardDelegate.modelData.tags : []
                        readonly property string _rawMultilineBody: String(baseCardDelegate.modelData.description || baseCardDelegate.modelData.plot || "")
                        readonly property string _extractedCourse: {
                            const m = _rawMultilineBody.match(/^\s*(?:[-*]\s*)?(?:\*\*)?(?:Course|Subject|Topic)(?:\*\*)?\s*:\s*(?:\*\*)?([^\n]+)$/im);
                            return m ? collectionViewRoot._cleanExcerpt(m[1]).slice(0, 48) : "";
                        }
                        readonly property string cleanNotes: collectionViewRoot._cleanExcerpt(
                            _rawMultilineBody.replace(/^\s*(?:[-*]\s*)?(?:\*\*)?(?:Course|Subject|Topic)(?:\*\*)?\s*:\s*[^\n]*(?:\n|$)/im, "")
                        )
                        readonly property string cueTopic: String(baseCardDelegate.modelData.category || baseCardDelegate.modelData.genre || _extractedCourse || (itemTags.length > 0 ? ("#" + itemTags[0]) : "Study Cue"))
                        readonly property int openTaskCnt: Number(baseCardDelegate.modelData.openTasks ?? 0)
                        readonly property int doneTaskCnt: Number(baseCardDelegate.modelData.doneTasks ?? 0)

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0

                            // Header Band (Course/Topic + Note Title + Review Status Pill)
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 48
                                color: settledColors.colLayer2

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    Rectangle {
                                        Layout.preferredWidth: 28
                                        Layout.preferredHeight: 28
                                        radius: 7
                                        color: Qt.alpha(settledColors.colPrimary, 0.16)
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "school"
                                            iconSize: 15
                                            color: settledColors.colPrimary
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: String(baseCardDelegate.modelData.title ?? "Cornell Note")
                                            font.pixelSize: 13
                                            font.weight: Font.Bold
                                            color: settledColors.colOnLayer0
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: cornellBaseCard.cueTopic
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 9
                                            color: settledColors.colPrimary
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Rectangle {
                                        visible: String(baseCardDelegate.modelData.status ?? "").length > 0
                                        height: 19
                                        width: cornellStTxt.implicitWidth + 10
                                        radius: 9.5
                                        color: settledColors.colSecondaryContainer
                                        StyledText {
                                            id: cornellStTxt
                                            anchors.centerIn: parent
                                            text: String(baseCardDelegate.modelData.status ?? "")
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            color: settledColors.colOnSecondaryContainer
                                        }
                                    }
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 1
                                    color: Qt.alpha(settledColors.colPrimary, 0.34)
                                }
                            }

                            // Authentic Two-Column Cornell Body: Left CUES | Accent Vertical Rule | Right NOTES
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 0

                                // Left Cues Column (~30% width)
                                ColumnLayout {
                                    Layout.preferredWidth: Math.max(72, Math.round(cornellBaseCard.width * 0.30))
                                    Layout.fillHeight: true
                                    Layout.margins: 8
                                    spacing: 4

                                    StyledText {
                                        text: "CUES"
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 8
                                        font.weight: Font.Black
                                        font.letterSpacing: 1.0
                                        color: settledColors.colPrimary
                                    }

                                    Repeater {
                                        model: cornellBaseCard.itemTags.length > 0 ? cornellBaseCard.itemTags.slice(0, 3) : [cornellBaseCard.cueTopic]
                                        delegate: Rectangle {
                                            required property string modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 18
                                            radius: 4
                                            color: settledColors.colLayer0
                                            border.width: 1
                                            border.color: settledColors.colLayer0Border
                                            StyledText {
                                                anchors.fill: parent
                                                anchors.leftMargin: 5
                                                anchors.rightMargin: 5
                                                verticalAlignment: Text.AlignVCenter
                                                text: modelData.startsWith("#") ? modelData : ("#" + modelData)
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: 9
                                                color: settledColors.colSubtext
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }

                                    Item { Layout.fillHeight: true }
                                }

                                // Iconic Cornell Vertical Margin Rule
                                Rectangle {
                                    Layout.preferredWidth: 1.5
                                    Layout.fillHeight: true
                                    color: Qt.alpha(settledColors.colPrimary, 0.42)
                                }

                                // Right Notes Column (~70% width)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.margins: 9
                                    spacing: 4

                                    StyledText {
                                        text: "NOTES"
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 8
                                        font.weight: Font.Black
                                        font.letterSpacing: 1.0
                                        color: settledColors.colSubtext
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        text: cornellBaseCard.cleanNotes.length > 0
                                            ? cornellBaseCard.cleanNotes
                                            : "Structured Cornell cues, key definitions, and lecture summary..."
                                        font.pixelSize: 11
                                        lineHeight: 1.25
                                        color: settledColors.colOnLayer1
                                        wrapMode: Text.WordWrap
                                        elide: Text.ElideRight
                                        maximumLineCount: 4
                                    }
                                }
                            }

                            // Bottom Cornell Summary Footer Strip
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                color: settledColors.colLayer0

                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: 1
                                    color: settledColors.colLayer0Border
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    StyledText {
                                        text: "SUMMARY"
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0.9
                                        color: settledColors.colPrimary
                                    }

                                    Item { Layout.fillWidth: true }

                                    RowLayout {
                                        visible: Number(baseCardDelegate.modelData.linkCount ?? 0) > 0
                                        spacing: 3
                                        MaterialSymbol { text: "hub"; iconSize: 11; color: settledColors.colSubtext }
                                        StyledText {
                                            text: String(baseCardDelegate.modelData.linkCount ?? 0)
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 9
                                            color: settledColors.colSubtext
                                        }
                                    }

                                    RowLayout {
                                        visible: (cornellBaseCard.openTaskCnt + cornellBaseCard.doneTaskCnt) > 0
                                        spacing: 3
                                        MaterialSymbol { text: "check_circle"; iconSize: 11; color: settledColors.colTertiary }
                                        StyledText {
                                            text: String(cornellBaseCard.doneTaskCnt) + "/" + String(cornellBaseCard.openTaskCnt + cornellBaseCard.doneTaskCnt)
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 9
                                            color: settledColors.colTertiary
                                        }
                                    }

                                    StyledText {
                                        visible: String(baseCardDelegate.modelData.year || baseCardDelegate.modelData.releaseDate || "").length > 0
                                        text: String(baseCardDelegate.modelData.releaseDate || baseCardDelegate.modelData.year || "")
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 9
                                        color: settledColors.colSubtext
                                    }
                                }
                            }
                        }
                    }

                    // ── 8B. ZETTELKASTEN SLIP-BOX INDEX CARD (Luhmann Zettel ID Stamp + Type Spine + Links & Tags) ──
                    Rectangle {
                        id: zettelBaseCard
                        objectName: "nexusZettelBaseCard_" + String(baseCardDelegate.index)
                        visible: baseCardDelegate.isZettelCard
                        anchors.fill: parent
                        radius: 10
                        color: baseCardHover.hovered ? settledColors.colLayer2Hover : settledColors.colLayer1
                        border.width: 1
                        border.color: baseCardHover.hovered ? zettelBaseCard.spineColor : settledColors.colLayer0Border
                        clip: true

                        readonly property string zId: {
                            const explicit = String(baseCardDelegate.modelData.zettelId ?? "").trim();
                            if (explicit.length > 0) return explicit;
                            const p = String(baseCardDelegate.modelData.title ?? baseCardDelegate.modelData.relPath ?? "");
                            const m = p.match(/\b(\d{8,14})\b/);
                            return m ? m[1] : ("ZK-" + String(baseCardDelegate.index + 1).padStart(3, "0"));
                        }
                        readonly property string zType: {
                            const raw = String(baseCardDelegate.modelData.zettelType || baseCardDelegate.modelData.status || baseCardDelegate.modelData.category || "Permanent").trim();
                            return raw.length > 0 ? raw : "Permanent";
                        }
                        readonly property color spineColor: {
                            const t = zType.toLowerCase();
                            if (t.indexOf("lit") !== -1 || t.indexOf("ref") !== -1)
                                return settledColors.colTertiary ?? settledColors.colPrimary;
                            if (t.indexOf("fleet") !== -1 || t.indexOf("draft") !== -1 || t.indexOf("seed") !== -1)
                                return settledColors.colSecondary ?? settledColors.colPrimary;
                            return settledColors.colPrimary;
                        }
                        readonly property var zTags: Array.isArray(baseCardDelegate.modelData.tags) ? baseCardDelegate.modelData.tags : []
                        readonly property string zBody: collectionViewRoot._cleanExcerpt(baseCardDelegate.modelData.description || baseCardDelegate.modelData.plot || "")

                        // Left Slip-Box Accent Spine
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 4
                            color: zettelBaseCard.spineColor
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 12
                            anchors.topMargin: 10
                            anchors.bottomMargin: 10
                            spacing: 6

                            // Index Card Top Metadata Strip: Zettel ID Stamp + Type Pill + Link Counter
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Rectangle {
                                    height: 19
                                    width: zkIdTxt.implicitWidth + 10
                                    radius: 4
                                    color: settledColors.colLayer0
                                    border.width: 1
                                    border.color: Qt.alpha(zettelBaseCard.spineColor, 0.42)
                                    StyledText {
                                        id: zkIdTxt
                                        anchors.centerIn: parent
                                        text: zettelBaseCard.zId
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        color: zettelBaseCard.spineColor
                                    }
                                }

                                Rectangle {
                                    height: 19
                                    width: zkTypeTxt.implicitWidth + 10
                                    radius: 9.5
                                    color: Qt.alpha(zettelBaseCard.spineColor, 0.16)
                                    StyledText {
                                        id: zkTypeTxt
                                        anchors.centerIn: parent
                                        text: zettelBaseCard.zType.toUpperCase()
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 8
                                        font.weight: Font.Black
                                        font.letterSpacing: 0.6
                                        color: zettelBaseCard.spineColor
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                RowLayout {
                                    spacing: 3
                                    MaterialSymbol {
                                        text: "link"
                                        iconSize: 12
                                        color: settledColors.colSubtext
                                    }
                                    StyledText {
                                        text: String(baseCardDelegate.modelData.linkCount ?? 0)
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        color: settledColors.colSubtext
                                    }
                                }
                            }

                            // Index-Card Ruled Header Line
                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Qt.alpha(zettelBaseCard.spineColor, 0.30)
                            }

                            // Atomic Idea Title (avoid repeating the Zettel ID already stamped in the badge)
                            StyledText {
                                Layout.fillWidth: true
                                text: {
                                    const rawTitle = String(baseCardDelegate.modelData.title ?? "Atomic Note").trim();
                                    const id = zettelBaseCard.zId;
                                    if (id.length >= 6 && rawTitle.startsWith(id)) {
                                        const stripped = rawTitle.slice(id.length).replace(/^[\s\-–—:|]+/, "").trim();
                                        if (stripped.length > 0) return stripped;
                                    }
                                    return rawTitle;
                                }
                                font.family: Appearance.font.family.reading || Appearance.font.family.main
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                color: settledColors.colOnLayer0
                                wrapMode: Text.WordWrap
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                lineHeight: 1.15
                            }

                            // Clean Atomic Excerpt
                            StyledText {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                text: zettelBaseCard.zBody.length > 0
                                    ? zettelBaseCard.zBody
                                    : "Atomic Zettelkasten concept card — click to inspect connections and literature links."
                                font.pixelSize: 11
                                lineHeight: 1.25
                                color: settledColors.colSubtext
                                wrapMode: Text.WordWrap
                                elide: Text.ElideRight
                                maximumLineCount: 3
                            }

                            // Bottom Tag Chips & Slip-Box Glyph
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Repeater {
                                    model: zettelBaseCard.zTags.slice(0, 3)
                                    delegate: Rectangle {
                                        required property string modelData
                                        height: 17
                                        width: Math.min(92, zkTagChipTxt.implicitWidth + 10)
                                        radius: 8.5
                                        color: settledColors.colLayer2
                                        border.width: 1
                                        border.color: settledColors.colLayer0Border
                                        StyledText {
                                            id: zkTagChipTxt
                                            anchors.centerIn: parent
                                            width: parent.width - 8
                                            horizontalAlignment: Text.AlignHCenter
                                            text: "#" + modelData.replace(/^#+/, "")
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 8
                                            color: settledColors.colPrimary
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                MaterialSymbol {
                                    text: "psychology"
                                    iconSize: 14
                                    color: Qt.alpha(zettelBaseCard.spineColor, 0.55)
                                }
                            }
                        }
                    }

                    // ── 8C. FINANCE LEDGER CARD (Transactions / Accounts / Subscriptions with Semantic Direction & Tabular Amounts) ──
                    Rectangle {
                        id: financeBaseCard
                        objectName: "nexusFinanceBaseCard_" + String(baseCardDelegate.index)
                        visible: baseCardDelegate.isFinanceCard
                        anchors.fill: parent
                        radius: 11
                        color: baseCardHover.hovered ? settledColors.colLayer2Hover : settledColors.colLayer1
                        border.width: 1
                        border.color: baseCardHover.hovered ? financeBaseCard.finAccent : settledColors.colLayer0Border
                        clip: true

                        readonly property string finRecordKind: {
                            const rk = String(baseCardDelegate.modelData.recordKind || baseCardDelegate.modelData.kind || "").toLowerCase();
                            if (rk === "account" || baseCardDelegate.modelData.balance !== undefined || collectionViewRoot.financeSubTab === "accounts")
                                return "account";
                            if (rk === "subscription" || String(baseCardDelegate.modelData.billingCycle || baseCardDelegate.modelData.cycle || "").length > 0 || collectionViewRoot.financeSubTab === "subscriptions")
                                return "subscription";
                            return "transaction";
                        }
                        readonly property string finTxType: String(baseCardDelegate.modelData.txType || baseCardDelegate.modelData.type || baseCardDelegate.modelData.status || "").toLowerCase()
                        readonly property real finNumericAmount: {
                            if (baseCardDelegate.modelData.amount !== undefined && baseCardDelegate.modelData.amount !== null)
                                return Number(baseCardDelegate.modelData.amount);
                            if (baseCardDelegate.modelData.balance !== undefined && baseCardDelegate.modelData.balance !== null)
                                return Number(baseCardDelegate.modelData.balance);
                            return NaN;
                        }
                        readonly property bool isIncome: finRecordKind === "transaction" && (finTxType.indexOf("inc") !== -1 || finTxType.indexOf("sal") !== -1 || finTxType.indexOf("dep") !== -1 || finTxType.indexOf("credit") !== -1)
                        readonly property bool isExpense: finRecordKind === "transaction" && !isIncome && (finTxType.indexOf("exp") !== -1 || finTxType.indexOf("spend") !== -1 || finTxType.indexOf("out") !== -1 || (Number.isFinite(finNumericAmount) && finNumericAmount < 0))
                        readonly property color finAccent: {
                            if (finRecordKind === "account")
                                return settledColors.colPrimary;
                            if (finRecordKind === "subscription")
                                return settledColors.colSecondary ?? settledColors.colPrimary;
                            if (isIncome)
                                return settledColors.colTertiary ?? settledColors.colPrimary;
                            if (isExpense)
                                return settledColors.colError ?? "#f38ba8";
                            return settledColors.colPrimary;
                        }
                        readonly property string finIcon: {
                            if (finRecordKind === "account")
                                return "account_balance";
                            if (finRecordKind === "subscription")
                                return "autorenew";
                            if (isIncome)
                                return "south_west";
                            if (isExpense)
                                return "north_east";
                            return "payments";
                        }
                        readonly property string finAmountText: {
                            if (!Number.isFinite(finNumericAmount))
                                return String(baseCardDelegate.modelData.status || "—");
                            const cur = String(baseCardDelegate.modelData.currency || root.nexus?.financeSummary?.currency || "");
                            const absFormatted = collectionViewRoot._formatMoney(Math.abs(finNumericAmount), cur);
                            if (finRecordKind === "transaction") {
                                if (isIncome) return "+" + absFormatted;
                                if (isExpense) return "-" + absFormatted;
                            }
                            return collectionViewRoot._formatMoney(finNumericAmount, cur);
                        }

                        // Left semantic color bar
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 4
                            color: financeBaseCard.finAccent
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 12
                            anchors.topMargin: 11
                            anchors.bottomMargin: 10
                            spacing: 8

                            // Top Row: Direction Icon Badge + Title/Merchant + Kind/Cycle Pill
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Rectangle {
                                    Layout.preferredWidth: 32
                                    Layout.preferredHeight: 32
                                    radius: 9
                                    color: Qt.alpha(financeBaseCard.finAccent, 0.16)
                                    border.width: 1
                                    border.color: Qt.alpha(financeBaseCard.finAccent, 0.34)
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: financeBaseCard.finIcon
                                        iconSize: 16
                                        color: financeBaseCard.finAccent
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: {
                                            const rawTitle = String(baseCardDelegate.modelData.title ?? "").trim();
                                            const lowerTitle = rawTitle.toLowerCase();
                                            const isGeneric = lowerTitle.length === 0
                                                || lowerTitle === "transaction notes"
                                                || lowerTitle === "transaction note"
                                                || lowerTitle === "account notes"
                                                || lowerTitle === "subscription notes"
                                                || lowerTitle === "finance entry"
                                                || lowerTitle === "untitled";
                                            const specific = String(baseCardDelegate.modelData.merchant
                                                || baseCardDelegate.modelData.description
                                                || baseCardDelegate.modelData.name
                                                || "").trim();
                                            return (!isGeneric ? rawTitle : (specific || rawTitle || "Finance Entry"));
                                        }
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                        color: settledColors.colOnLayer0
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: {
                                            const subParts = [];
                                            if (baseCardDelegate.modelData.category) subParts.push(String(baseCardDelegate.modelData.category));
                                            if (baseCardDelegate.modelData.account) subParts.push(String(baseCardDelegate.modelData.account));
                                            if (baseCardDelegate.modelData.billingCycle || baseCardDelegate.modelData.cycle) subParts.push(String(baseCardDelegate.modelData.billingCycle || baseCardDelegate.modelData.cycle));
                                            if (subParts.length === 0 && baseCardDelegate.modelData.txType) subParts.push(String(baseCardDelegate.modelData.txType));
                                            return subParts.length > 0 ? subParts.join(" · ") : financeBaseCard.finRecordKind.toUpperCase();
                                        }
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 10
                                        color: settledColors.colSubtext
                                        elide: Text.ElideRight
                                    }
                                }

                                Rectangle {
                                    height: 19
                                    width: finKindLbl.implicitWidth + 10
                                    radius: 9.5
                                    color: Qt.alpha(financeBaseCard.finAccent, 0.16)
                                    StyledText {
                                        id: finKindLbl
                                        anchors.centerIn: parent
                                        text: {
                                            if (financeBaseCard.finRecordKind === "account")
                                                return String(baseCardDelegate.modelData.type || "ACCOUNT").toUpperCase();
                                            if (financeBaseCard.finRecordKind === "subscription")
                                                return String(baseCardDelegate.modelData.billingCycle || baseCardDelegate.modelData.cycle || "SUB").toUpperCase();
                                            return financeBaseCard.isIncome ? "INCOME" : (financeBaseCard.isExpense ? "EXPENSE" : "LEDGER");
                                        }
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 8
                                        font.weight: Font.Black
                                        color: financeBaseCard.finAccent
                                    }
                                }
                            }

                            // Hero Tabular Monetary Figure Pill
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                radius: 8
                                color: settledColors.colLayer0
                                border.width: 1
                                border.color: Qt.alpha(financeBaseCard.finAccent, 0.24)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 6

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: financeBaseCard.finAmountText
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 16
                                        font.weight: Font.Bold
                                        color: financeBaseCard.finAccent
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        visible: String(baseCardDelegate.modelData.status ?? "").length > 0
                                        text: String(baseCardDelegate.modelData.status ?? "").toUpperCase()
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 9
                                        font.weight: Font.DemiBold
                                        color: settledColors.colSubtext
                                    }
                                }
                            }

                            // Bottom Ledger Metadata Row (Notes/Description + Date)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                StyledText {
                                    Layout.fillWidth: true
                                    text: collectionViewRoot._cleanExcerpt(baseCardDelegate.modelData.description || baseCardDelegate.modelData.plot || baseCardDelegate.modelData.account || "Open ledger note")
                                    font.pixelSize: 10
                                    color: settledColors.colSubtext
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    visible: String(baseCardDelegate.modelData.date || baseCardDelegate.modelData.releaseDate || baseCardDelegate.modelData.year || "").length > 0
                                    text: String(baseCardDelegate.modelData.date || baseCardDelegate.modelData.releaseDate || baseCardDelegate.modelData.year || "")
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 9
                                    color: settledColors.colSubtext
                                }
                            }
                        }
                    }

                    // ── 8D. CONTACTS / WEBSITES / CLIPPINGS GENERIC CARDS ──
                    Rectangle {
                        visible: !baseCardDelegate.isMovieCard && !baseCardDelegate.isTvCard && !baseCardDelegate.isGameCard && !baseCardDelegate.isBookCard && !baseCardDelegate.isRecipeCard && !baseCardDelegate.isExerciseCard && !baseCardDelegate.isPlaceCard && !baseCardDelegate.isCornellCard && !baseCardDelegate.isZettelCard && !baseCardDelegate.isFinanceCard
                        anchors.fill: parent
                        radius: 10
                        color: baseCardHover.hovered ? settledColors.colLayer2Hover : settledColors.colLayer0
                        border.width: 1
                        border.color: baseCardHover.hovered ? collectionViewRoot.activeCollectionMeta.accent : settledColors.colLayer0Border
                        clip: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                MaterialSymbol {
                                    text: collectionViewRoot.activeCollectionMeta.icon
                                    iconSize: 18
                                    color: collectionViewRoot.activeCollectionMeta.accent
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: String(baseCardDelegate.modelData.title ?? "")
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    color: settledColors.colOnLayer1
                                    elide: Text.ElideRight
                                }

                                Rectangle {
                                    visible: Boolean(baseCardDelegate.modelData.status || baseCardDelegate.modelData.category)
                                    height: 20
                                    width: otherBadgeTxt.implicitWidth + 12
                                    radius: 5
                                    color: settledColors.colSecondaryContainer
                                    StyledText {
                                        id: otherBadgeTxt
                                        anchors.centerIn: parent
                                        text: String(baseCardDelegate.modelData.status || baseCardDelegate.modelData.category || "")
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: collectionViewRoot.activeCollectionMeta.accent
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: Boolean(baseCardDelegate.modelData.genre || baseCardDelegate.modelData.location || baseCardDelegate.modelData.url || baseCardDelegate.modelData.director)
                                text: {
                                    const p = [];
                                    if (baseCardDelegate.modelData.genre) p.push(String(baseCardDelegate.modelData.genre));
                                    if (baseCardDelegate.modelData.director) p.push(String(baseCardDelegate.modelData.director));
                                    if (baseCardDelegate.modelData.location) p.push(String(baseCardDelegate.modelData.location));
                                    if (baseCardDelegate.modelData.url) p.push(String(baseCardDelegate.modelData.url));
                                    return p.join("  ·  ");
                                }
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 11
                                color: collectionViewRoot.activeCollectionMeta.accent
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                text: String(baseCardDelegate.modelData.plot || "Click to open note in Nexus...")
                                font.pixelSize: 11
                                color: settledColors.colSubtext
                                wrapMode: Text.WordWrap
                                elide: Text.ElideRight
                                maximumLineCount: 4
                            }
                        }
                    }

                    MouseArea {
                        id: collEntryMouse
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                const pt = mapToItem(root, mouse.x, mouse.y);
                                root.openContextMenu(pt.x, pt.y, {
                                    "type": "base-card",
                                    "title": baseCardDelegate.modelData.title || baseCardDelegate.modelData.name || baseCardDelegate.modelData.relPath,
                                    "relPath": baseCardDelegate.modelData.relPath,
                                    "noteKind": baseCardDelegate.modelData.kind || collectionCardsGrid.activeKind,
                                    "flipped": baseCardDelegate.flipped,
                                    "onFlip": () => { baseCardDelegate.flipped = !baseCardDelegate.flipped; }
                                });
                                return;
                            }
                            if (baseCardDelegate.isExerciseCard && exBaseCard.animUrl.length > 0 && !baseCardDelegate.flipped) {
                                // Check if top-right circular Play button was clicked
                                if (mouse.x >= baseCardDelegate.width - 44 && mouse.y <= 44) {
                                    exBaseCard.exDemoPlaying = !exBaseCard.exDemoPlaying;
                                    return;
                                }
                            }
                            if (root.nexus && baseCardDelegate.modelData.relPath)
                                root.nexus.openFile(baseCardDelegate.modelData.relPath, true);
                        }
                    }
                }
            }
        }

    // ── OBSIDIAN BASES TABLE VIEW (`02_Components.css` L158–277 & `Contact_Tracker.base` / `Finance.base`) ──
    Rectangle {
        id: basesTableViewContainer
        objectName: "nexusBasesTableView"
        visible: collectionViewRoot.viewMode === "table"
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 8
        color: settledColors.colLayer0
        border.width: 1
        border.color: settledColors.colLayer0Border
        clip: true

        readonly property bool isFinanceLedger: collectionViewRoot.activeCollectionMeta.id === "finance"
        readonly property var financeRows: {
            if (!isFinanceLedger)
                return [];
            const fs = root.nexus?.financeSummary ?? {};
            if (collectionViewRoot.financeSubTab === "accounts")
                return fs.accounts ?? [];
            if (collectionViewRoot.financeSubTab === "subscriptions")
                return fs.subscriptions ?? [];
            return fs.transactions ?? [];
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Bases Table Header (`--bases-table-header-background`)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                color: settledColors.colLayer1
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    StyledText {
                        Layout.preferredWidth: 190
                        text: basesTableViewContainer.isFinanceLedger
                            ? (collectionViewRoot.financeSubTab === "accounts" ? "ACCOUNT" : (collectionViewRoot.financeSubTab === "subscriptions" ? "SERVICE" : "DESCRIPTION"))
                            : (collectionViewRoot.activeCollectionMeta.id === "contacts" ? "FULL NAME" : "TITLE")
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                        color: settledColors.colSubtext
                    }
                    StyledText {
                        Layout.preferredWidth: 110
                        text: basesTableViewContainer.isFinanceLedger
                            ? (collectionViewRoot.financeSubTab === "accounts" ? "TYPE" : (collectionViewRoot.financeSubTab === "subscriptions" ? "CYCLE" : "DATE"))
                            : (collectionViewRoot.activeCollectionMeta.id === "contacts" ? "COMPANY / ROLE" : "CATEGORY / GENRE")
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                        color: settledColors.colSubtext
                    }
                    StyledText {
                        Layout.preferredWidth: 110
                        text: basesTableViewContainer.isFinanceLedger
                            ? (collectionViewRoot.financeSubTab === "accounts" ? "STATUS" : "CATEGORY")
                            : (collectionViewRoot.activeCollectionMeta.id === "contacts" ? "PHONE / EMAIL" : "CREATOR / AUTHOR")
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                        color: settledColors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: basesTableViewContainer.isFinanceLedger
                            ? "KIND"
                            : (collectionViewRoot.activeCollectionMeta.id === "contacts" ? "ADDRESS / LOCATION" : "DETAILS / NOTES")
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                        color: settledColors.colSubtext
                    }
                    StyledText {
                        Layout.preferredWidth: 100
                        horizontalAlignment: Text.AlignRight
                        text: basesTableViewContainer.isFinanceLedger ? "AMOUNT" : "STATUS / SCORE"
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                        color: settledColors.colSubtext
                    }
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: settledColors.colLayer0Border
                }
            }

            // Bases Table Rows
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cacheBuffer: 480
                model: (!collectionViewRoot.visible || collectionViewRoot.viewMode !== "table")
                    ? []
                    : (basesTableViewContainer.isFinanceLedger && basesTableViewContainer.financeRows.length > 0
                        ? basesTableViewContainer.financeRows
                        : collectionViewRoot.filteredCollectionItems)
                delegate: Rectangle {
                    id: tableRowDel
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: 34
                    color: tableRowMouse.containsMouse
                        ? settledColors.colLayer2Hover
                        : (index % 2 === 1 ? Qt.alpha(settledColors.colLayer2, 0.28) : "transparent")

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        StyledText {
                            Layout.preferredWidth: 190
                            text: String(tableRowDel.modelData.title ?? tableRowDel.modelData.description ?? tableRowDel.modelData.name ?? "")
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: settledColors.colPrimary
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.preferredWidth: 110
                            text: String(tableRowDel.modelData.genre ?? tableRowDel.modelData.category ?? tableRowDel.modelData.date ?? tableRowDel.modelData.type ?? tableRowDel.modelData.cycle ?? "—")
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: 11
                            color: settledColors.colOnLayer1
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.preferredWidth: 110
                            text: String(tableRowDel.modelData.director ?? tableRowDel.modelData.actors ?? tableRowDel.modelData.category ?? tableRowDel.modelData.status ?? "—")
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: 11
                            color: settledColors.colSubtext
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: String(tableRowDel.modelData.location ?? tableRowDel.modelData.plot ?? tableRowDel.modelData.kind ?? "")
                            font.pixelSize: 11
                            color: settledColors.colSubtext
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.preferredWidth: 100
                            horizontalAlignment: Text.AlignRight
                            text: tableRowDel.modelData.amount !== undefined
                                ? String(tableRowDel.modelData.amount)
                                : (tableRowDel.modelData.balance !== undefined
                                    ? String(tableRowDel.modelData.balance)
                                    : String(tableRowDel.modelData.status || tableRowDel.modelData.score || "—"))
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: collectionViewRoot.activeCollectionMeta.accent
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: Qt.alpha(settledColors.colLayer0Border, 0.45)
                    }

                    MouseArea {
                        id: tableRowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                const pt = mapToItem(root, mouse.x, mouse.y);
                                root.openContextMenu(pt.x, pt.y, {
                                    "type": "file",
                                    "title": tableRowDel.modelData.title || tableRowDel.modelData.name || tableRowDel.modelData.relPath,
                                    "relPath": tableRowDel.modelData.relPath,
                                    "noteKind": tableRowDel.modelData.kind || collectionViewRoot.activeCollectionMeta.id,
                                    "isDir": false
                                });
                                return;
                            }
                            if (root.nexus && tableRowDel.modelData.relPath)
                                root.nexus.openFile(tableRowDel.modelData.relPath, true);
                        }
                    }
                }
            }

            // Bases Summary Footer (`Sum` / `Count` matching `02_Components.css` L245–277 & `Finance.base`)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                color: settledColors.colLayer1
                Rectangle {
                    anchors.top: parent.top
                    width: parent.width
                    height: 1
                    color: settledColors.colLayer0Border
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 16
                    StyledText {
                        text: "COUNT  " + String(collectionViewRoot.filteredCollectionItems.length)
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: settledColors.colSubtext
                    }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        visible: basesTableViewContainer.isFinanceLedger
                        text: "INCOME: " + String(root.nexus?.financeSummary?.totalIncome ?? 0) +
                              "   ·   SPENT: " + String(root.nexus?.financeSummary?.totalSpent ?? 0) +
                              "   ·   SUM / NET: " + String(root.nexus?.financeSummary?.balance ?? 0)
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: settledColors.colPrimary
                    }
                }
            }
        }
    }
}
