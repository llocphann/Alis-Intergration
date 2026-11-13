import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

SettingsCardSection {
    id: root
    objectName: "alisIntergrationSpacedRepetitionSettings"
    settingsTaskSection: "spacedRepetition"
    expanded: true
    icon: "school"
    title: Translation.tr("Spaced Repetition")

    function ensureSpacedRepetitionInPageOrder(): void {
        const current = Array.from(Config.options?.dashboard?.pageOrder ?? ["dashboard", "music", "weeklyPlanner"])
        if (!current.includes("spacedRepetition")) {
            Config.setNestedValue("dashboard.pageOrder", current.concat(["spacedRepetition"]))
        }
    }

    SettingsGroup {
        SettingsSwitch {
        Layout.fillWidth: true
        buttonIcon: "school"
        text: Translation.tr("Enable Spaced Repetition tab")
        checked: Config.options?.dashboard?.spacedRepetition?.enable ?? true
        onCheckedChanged: {
            Config.setNestedValue("dashboard.spacedRepetition.enable", checked)
            if (checked) root.ensureSpacedRepetitionInPageOrder()
        }
    }

    ContentSubsection {
        title: Translation.tr("Daily limits & queue priority")

        ConfigRow {
            uniform: true

            ConfigSpinBox {
                Layout.fillWidth: true
                icon: "fiber_new"
                text: Translation.tr("New cards / day")
                value: Config.options?.dashboard?.spacedRepetition?.dailyNewLimit ?? 20
                from: 1
                to: 200
                stepSize: 5
                onValueChanged: Config.setNestedValue("dashboard.spacedRepetition.dailyNewLimit", value)
            }

            ConfigSpinBox {
                Layout.fillWidth: true
                icon: "repeat"
                text: Translation.tr("Reviews / day")
                value: Config.options?.dashboard?.spacedRepetition?.dailyReviewLimit ?? 100
                from: 10
                to: 500
                stepSize: 10
                onValueChanged: Config.setNestedValue("dashboard.spacedRepetition.dailyReviewLimit", value)
            }
        }

        ConfigSelectionArray {
            currentValue: Config.options?.dashboard?.spacedRepetition?.prioritizeOrder ?? "due_first"
            onSelected: value => Config.setNestedValue("dashboard.spacedRepetition.prioritizeOrder", value)
            options: [
                { displayName: Translation.tr("Due first"), icon: "schedule", value: "due_first" },
                { displayName: Translation.tr("CEFR A1→C2"), icon: "trending_up", value: "level_asc" },
                { displayName: Translation.tr("Hardest first"), icon: "local_fire_department", value: "hardest_first" },
                { displayName: Translation.tr("New first"), icon: "auto_awesome", value: "new_first" },
                { displayName: Translation.tr("Interleaved"), icon: "shuffle", value: "interleaved" }
            ]
        }
    }

    ContentSubsection {
        title: Translation.tr("SM-2+ scheduling & interval boost")

        ConfigRow {
            uniform: true

            ConfigSpinBox {
                Layout.fillWidth: true
                icon: "bolt"
                text: Translation.tr("Interval boost (%)")
                value: Config.options?.dashboard?.spacedRepetition?.boostMultiplier ?? 100
                from: 50
                to: 250
                stepSize: 10
                onValueChanged: Config.setNestedValue("dashboard.spacedRepetition.boostMultiplier", value)
            }

            ConfigSpinBox {
                Layout.fillWidth: true
                icon: "rocket_launch"
                text: Translation.tr("Easy bonus (%)")
                value: Config.options?.dashboard?.spacedRepetition?.easyBonus ?? 130
                from: 100
                to: 250
                stepSize: 5
                onValueChanged: Config.setNestedValue("dashboard.spacedRepetition.easyBonus", value)
            }
        }

        ConfigRow {
            uniform: true

            ConfigSpinBox {
                Layout.fillWidth: true
                icon: "speed"
                text: Translation.tr("Base ease")
                value: Config.options?.dashboard?.spacedRepetition?.baseEase ?? 250
                from: 130
                to: 350
                stepSize: 10
                onValueChanged: Config.setNestedValue("dashboard.spacedRepetition.baseEase", value)
            }

            ConfigSpinBox {
                Layout.fillWidth: true
                icon: "restore"
                text: Translation.tr("Lapse retention (%)")
                value: Config.options?.dashboard?.spacedRepetition?.lapseMultiplier ?? 50
                from: 0
                to: 90
                stepSize: 10
                onValueChanged: Config.setNestedValue("dashboard.spacedRepetition.lapseMultiplier", value)
            }
        }

        ConfigRow {
            uniform: true

            ConfigSpinBox {
                Layout.fillWidth: true
                icon: "warning"
                text: Translation.tr("Leech threshold")
                value: Config.options?.dashboard?.spacedRepetition?.leechThreshold ?? 6
                from: 2
                to: 20
                stepSize: 1
                onValueChanged: Config.setNestedValue("dashboard.spacedRepetition.leechThreshold", value)
            }

            ConfigSpinBox {
                Layout.fillWidth: true
                icon: "event_repeat"
                text: Translation.tr("Max interval (d)")
                value: Config.options?.dashboard?.spacedRepetition?.maximumInterval ?? 3650
                from: 7
                to: 36500
                stepSize: 30
                onValueChanged: Config.setNestedValue("dashboard.spacedRepetition.maximumInterval", value)
            }
        }

        SettingsSwitch {
            Layout.fillWidth: true
            buttonIcon: "balance"
            text: Translation.tr("Load-balance review intervals to prevent due spikes")
            checked: Config.options?.dashboard?.spacedRepetition?.loadBalance ?? true
            onCheckedChanged: Config.setNestedValue("dashboard.spacedRepetition.loadBalance", checked)
        }
    }

    ContentSubsection {
        title: Translation.tr("Vocabulary & automated CEFR syntax")

        ConfigSelectionArray {
            currentValue: Config.options?.dashboard?.spacedRepetition?.defaultLanguage ?? "en"
            onSelected: value => Config.setNestedValue("dashboard.spacedRepetition.defaultLanguage", value)
            options: [
                { displayName: Translation.tr("English (EN)"), icon: "language", value: "en" },
                { displayName: Translation.tr("Deutsch (DE)"), icon: "translate", value: "de" },
                { displayName: Translation.tr("General"), icon: "school", value: "general" }
            ]
        }

        ConfigSelectionArray {
            currentValue: {
                const raw = String(
                    Config.options?.dashboard?.spacedRepetition?.studyDirection
                    ?? Config.options?.dashboard?.spacedRepetition?.reviewMode
                    ?? "both"
                ).toLowerCase()
                if (raw === "reverse" || raw === "reverse_flashcard" || raw === "reverseflashcard"
                        || raw === "rmc" || raw === "reverse_mcq" || raw === "reversemultiplechoice")
                    return "matching"
                if (raw === "mcq" || raw === "multiple_choice" || raw === "multiplechoice")
                    return "mc"
                if (raw === "forward")
                    return "flashcard"
                return raw
            }
            onSelected: value => Config.setNestedValue("dashboard.spacedRepetition.studyDirection", value)
            options: [
                { displayName: Translation.tr("Smart Mix"), icon: "auto_awesome", value: "both" },
                { displayName: Translation.tr("Matching"), icon: "join_inner", value: "matching" },
                { displayName: Translation.tr("Multiple Choice"), icon: "quiz", value: "mc" },
                { displayName: Translation.tr("Cloze Reading"), icon: "edit_note", value: "cloze" },
                { displayName: Translation.tr("Flashcard"), icon: "style", value: "flashcard" }
            ]
        }

        ConfigRow {
            uniform: true

            SettingsSwitch {
                Layout.fillWidth: true
                buttonIcon: "workspace_premium"
                text: Translation.tr("Auto CEFR level (A1–C2)")
                checked: Config.options?.dashboard?.spacedRepetition?.autoLookupLevel ?? true
                onCheckedChanged: Config.setNestedValue("dashboard.spacedRepetition.autoLookupLevel", checked)
            }

            SettingsSwitch {
                Layout.fillWidth: true
                buttonIcon: "travel_explore"
                text: Translation.tr("Online dictionary lookup")
                checked: Config.options?.dashboard?.spacedRepetition?.autoLookupOnline ?? true
                onCheckedChanged: Config.setNestedValue("dashboard.spacedRepetition.autoLookupOnline", checked)
            }
        }

        SettingsSwitch {
            Layout.fillWidth: true
            buttonIcon: "short_text"
            text: Translation.tr("Auto-generate cloze blanks from example sentences")
            checked: Config.options?.dashboard?.spacedRepetition?.autoCloze ?? true
            onCheckedChanged: Config.setNestedValue("dashboard.spacedRepetition.autoCloze", checked)
        }
    }
    }
}
