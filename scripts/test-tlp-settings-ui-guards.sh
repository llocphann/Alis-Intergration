#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
helper="$repo_root/assets/helpers/inir-battery-charge-limit"
runtime="$repo_root/services/TlpRuntimeCapabilities.qml"
power="$repo_root/modules/settings/TlpPowerSettings.qml"

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    expected=$1
    actual=$2
    message=$3
    [ "$expected" = "$actual" ] || fail "$message (expected '$expected', got '$actual')"
}

assert_contains() {
    needle=$1
    file=$2
    message=$3
    grep -Fq -- "$needle" "$file" || fail "$message"
}

assert_not_contains() {
    needle=$1
    file=$2
    message=$3
    if grep -Fq -- "$needle" "$file"; then
        fail "$message"
    fi
}
sh -n "$helper" || fail 'TLP helper must remain valid POSIX shell syntax'

# Source the helper under this test basename; its guarded main() must not run.
# shellcheck disable=SC1090
. "$helper"

assert_eq CPU_BOOST_ON_AC \
    "$(tlp_settings_runtime_key CPU_BOOST_ON_AC 1.10.2)" \
    'TLP 1.10 must keep legacy AC profile keys'
assert_eq CPU_BOOST_ON_PRF \
    "$(tlp_settings_runtime_key CPU_BOOST_ON_AC 1.11.0)" \
    'TLP 1.11 must read the canonical PRF profile key'
assert_eq CPU_BOOST_ON_BAL \
    "$(tlp_settings_runtime_key CPU_BOOST_ON_BAT 1.11.0)" \
    'TLP 1.11 must read the canonical BAL profile key'
assert_eq DEVICES_TO_DISABLE_ON_PRF_NOT_IN_USE \
    "$(tlp_settings_runtime_key DEVICES_TO_DISABLE_ON_AC_NOT_IN_USE 1.11.0)" \
    'TLP 1.11 must rename embedded AC profile markers before trailing qualifiers'
assert_eq DEVICES_TO_DISABLE_ON_BAL_NOT_IN_USE \
    "$(tlp_settings_runtime_key DEVICES_TO_DISABLE_ON_BAT_NOT_IN_USE 1.11.0)" \
    'TLP 1.11 must rename embedded BAT profile markers before trailing qualifiers'
assert_eq TLP_PROFILE_AC \
    "$(tlp_settings_runtime_key TLP_PROFILE_AC 1.11.0)" \
    'profile selection keys are not suffix-renamed settings'

assert_contains 'CPU_DRIVER_OPMODE_ON_AC' "$runtime" \
    'runtime capabilities must gate CPU driver modes'
assert_contains '/sys/devices/system/cpu/intel_pstate/status' "$runtime" \
    'intel_pstate passive mode must remain detectable'
assert_contains '_kernelAtLeast(6, 4)' "$runtime" \
    'guided amd-pstate mode must be kernel-gated'
assert_contains 'INTEL_GPU_MIN_FREQ_ON_AC' "$runtime" \
    'runtime capabilities must probe Intel GPU frequency support'
assert_contains 'numberRanges' "$runtime" \
    'runtime capabilities must expose hardware number ranges'
assert_contains 'property string settingsTaskSection: "power"' "$power" \
    'TLP controls must identify themselves as part of the Power task'
for page in "$power"; do
    assert_contains 'property bool _tlpDemandRefreshed: false' "$page" \
        "$(basename "$page") must coalesce demand refreshes per visible session"
    assert_contains 'onVisibleChanged:' "$page" \
        "$(basename "$page") must refresh TLP state when shown again"
    assert_contains 'TlpRuntimeCapabilities.refresh()' "$page" \
        "$(basename "$page") must refresh runtime capabilities on demand"
    assert_contains 'TlpSettingsService.refresh()' "$page" \
        "$(basename "$page") must refresh TLP status on demand"
done
assert_contains 'title: Translation.tr("Battery & TLP")' "$power" \
    'the primary TLP card title must remain a stable search target'
assert_contains 'text: Translation.tr("Low warning")' "$power" \
    'low-battery warning controls must live in the merged Battery/TLP card'
assert_contains 'text: Translation.tr("Automatic suspend")' "$power" \
    'automatic suspend controls must live in the merged Battery/TLP card'
assert_contains 'text: Translation.tr("Full warning")' "$power" \
    'full-battery warning controls must live in the merged Battery/TLP card'
assert_not_contains 'text: Translation.tr("Battery care")' "$power" \
    'the merged Battery/TLP card must not add a redundant Battery care heading'
assert_contains 'showStatus: false' "$power" \
    'inline charge-limit controls must stay on the Automatic suspend row without a status sub-row'
assert_contains '.filter(category => String(category?.id ?? "") !== "battery-care")' "$power" \
    'Configuration categories must exclude the battery-care tab after merging it into Battery'
assert_not_contains 'columns: 5' "$power" \
    'TLP category sub-tabs must not use a rigid five-column grid'
assert_not_contains 'title: Translation.tr("Configuration categories")' "$power" \
    'TLP category sub-tabs must not be wrapped in a Configuration categories card box'
assert_not_contains 'Filter by name, parameter, or description' "$power" \
    'TLP category sub-tabs must not render a filter input box'
assert_contains 'objectName: "tlpCategoryNavigator"' "$power" \
    'TLP category sub-tabs must render as a standalone secondary tab navigator'
assert_contains 'objectName: "tlpCategoryRail"' "$power" \
    'TLP category sub-tabs must render inside a subtle Abyss task rail'
assert_contains 'objectName: "tlpCategoryTabs"' "$power" \
    'TLP category sub-tabs must use a responsive ConfigSelectionArray tab flow'
assert_contains 'taskNavigation: true' "$power" \
    'TLP category sub-tabs must use shared Settings task-navigation styling and keyboard navigation'
assert_contains 'useAbyssPillShape: false' "$power" \
    'TLP category sub-tabs must align with Abyss Panel Style task tabs'
assert_contains 'options: root.navigationCategories.map(' "$power" \
    'TLP category sub-tabs must consume the filtered ten-category model'
assert_contains 'onSelected: value => root.selectCategory(Number(value))' "$power" \
    'TLP category selection must route through root.selectCategory'
assert_not_contains 'text: Translation.tr("Config: %1").arg(TlpSettingsService.configFile)' "$power" \
    'Battery/TLP summary must not expose the managed config path in the primary card'
assert_contains ': Translation.tr("Effective values")' "$power" \
    'Battery/TLP summary must use the concise effective-values label'
assert_not_contains 'Item { Layout.fillWidth: true }' "$power" \
    'Effective values, Discard, Apply and Reset overrides must stay on one action row'
assert_contains 'BatteryChargeLimitSettings {' "$power" \
    'battery charge care must be integrated into the primary Battery/TLP card'
assert_not_contains 'Values shown below come from TLP' "$power" \
    'Battery/TLP summary must not restore the old verbose effective-configuration description'
assert_not_contains 'Apply validates every change and authenticates only once' "$power" \
    'Battery/TLP summary must keep apply guidance concise'
assert_not_contains 'Reset removes only the general iNiR TLP' "$power" \
    'Battery/TLP summary must keep reset guidance concise'

schema="$repo_root/assets/tlp/tlp-settings-schema.json"
settings_service="$repo_root/services/TlpSettingsService.qml"
jq -e '
 .schema == 1 and
 ([.categories[].settings[]] | length) == 125 and
 ([.categories[].groups[]] | length) == 62 and
 ([.categories[].groups[] | select(.description == "" or (.description | contains("\n")) or (.description | length) > 120)] | length) == 0 and
 .descriptionAttribution.license == "GPL-2.0-or-later"
' "$schema" >/dev/null || fail 'the UI schema must expose concise setting groups'
assert_contains '/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors' "$runtime" 'CPU governor choices must come from the kernel'
assert_contains '/sys/power/mem_sleep' "$runtime" 'suspend choices must come from the kernel'
assert_contains 'function groupsForCategory(category, filterText): var {' "$settings_service" 'settings service must expose grouped schema data'
assert_contains 'command.push("--charge-set"' "$settings_service" 'charge care must join the same privileged batch'
assert_eq 1 "$(grep -Fc 'const command = ["/usr/bin/pkexec", root.helperPath, "--config-apply"]' "$settings_service")" 'settings service must build one privileged Apply command'
assert_not_contains 'applyOnLeave' "$settings_service" 'settings service must require explicit Apply'

classic="$repo_root/modules/settings/TlpSettingRow.qml"
waffle="$repo_root/modules/waffle/settings/WTlpSettingRow.qml"
waffle_page="$repo_root/modules/waffle/settings/WTlpPowerSettings.qml"
for row in "$classic" "$waffle"; do
    assert_contains 'gpuFrequencyGroupKeys' "$row" \
        "$(basename "$row") must stage Intel GPU frequency groups atomically"
    assert_contains 'editorNumberRange' "$row" \
        "$(basename "$row") must use runtime numeric bounds"
    assert_contains 'next.length === 0 && root.settingKey.startsWith("PLATFORM_PROFILE_")' "$row" \
        "$(basename "$row") must turn an empty TLP 1.11 profile list into inherit/unset"
done

for page in "$waffle_page"; do
    assert_contains 'property bool _tlpDemandRefreshed: false' "$page" \
        "$(basename "$page") must coalesce demand refreshes per visible session"
    assert_contains 'onVisibleChanged:' "$page" \
        "$(basename "$page") must refresh TLP state when shown again"
    assert_contains 'TlpRuntimeCapabilities.refresh()' "$page" \
        "$(basename "$page") must refresh runtime capabilities on demand"
    assert_contains 'TlpSettingsService.refresh()' "$page" \
        "$(basename "$page") must refresh TLP status on demand"
done
assert_contains 'model: root.visibleGroups' "$waffle_page" 'Waffle settings must render schema groups'
assert_contains 'onButtonClicked: TlpSettingsService.apply()' "$waffle_page" 'Waffle settings must expose explicit Apply'
printf '%s\n' HADALIRD_TLP_UI_GUARDS_PASS
