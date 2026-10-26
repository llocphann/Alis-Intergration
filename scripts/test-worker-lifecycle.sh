#!/usr/bin/env bash
# Preserved worker timeout/recovery guards; physical helpers use private fixtures.
set -euo pipefail
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tlp_service="$repo_root/services/TlpService.qml"
tlp_settings="$repo_root/services/TlpSettingsService.qml"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_file_contains() { grep -Fq -- "$1" "$2" || fail "$3"; }
tlp="$tlp_service"
thinkfan="$repo_root/services/ThinkFanService.qml"
tlp_caps="$repo_root/services/TlpRuntimeCapabilities.qml"
require() { grep -Fq -- "$2" "$1" || fail "$3"; }
reject() { if grep -Fq -- "$2" "$1"; then fail "$3"; fi; }
# Battery policy status/apply calls cross the privileged helper boundary. Keep
# both process paths bounded so a wedged helper or pkexec prompt cannot leave
# TLP reconciliation or Settings permanently busy.
assert_file_contains 'detectorTimeout.restart()' "$tlp_service" \
  'TLP battery status detection must arm its timeout'
assert_file_contains 'id: detectorTimeout' "$tlp_service" \
  'TLP battery status detection must define a timeout timer'
assert_file_contains 'interval: 5000' "$tlp_service" \
  'TLP battery status detection timeout must remain bounded'
assert_file_contains 'detector.timedOut = true' "$tlp_service" \
  'TLP battery status timeout must mark the process as timed out'
assert_file_contains 'detector.running = false' "$tlp_service" \
  'TLP battery status timeout must stop the helper process'
assert_file_contains 'applyTimeout.restart()' "$tlp_service" \
  'TLP battery policy apply must arm its timeout'
assert_file_contains 'id: applyTimeout' "$tlp_service" \
  'TLP battery policy apply must define a timeout timer'
assert_file_contains 'interval: 60000' "$tlp_service" \
  'TLP battery policy apply timeout must remain bounded'
assert_file_contains 'applyProcess.timedOut = true' "$tlp_service" \
  'TLP battery policy apply timeout must mark the process as timed out'
assert_file_contains 'applyProcess.running = false' "$tlp_service" \
  'TLP battery policy apply timeout must stop the helper process'
assert_file_contains 'root.busy = false' "$tlp_service" \
  'TLP battery policy apply exit must release the busy state'

# The full TLP settings surface uses the same helper for status plus privileged
# config mutations. Both paths must remain bounded, and a privileged spawn
# failure must release busy state and notify the UI without discarding staged
# edits.
assert_file_contains 'statusTimeout.restart()' "$tlp_settings" \
  'TLP settings status must arm its timeout'
assert_file_contains 'id: statusTimeout' "$tlp_settings" \
  'TLP settings status must define a timeout timer'
assert_file_contains 'statusProcess.timedOut = true' "$tlp_settings" \
  'TLP settings status timeout must mark the process as timed out'
assert_file_contains 'statusProcess.running = false' "$tlp_settings" \
  'TLP settings status timeout must stop the helper process'
assert_file_contains 'root._clearStatus("status-timeout")' "$tlp_settings" \
  'TLP settings status timeout must clear stale status'
assert_file_contains 'mutationTimeout.restart()' "$tlp_settings" \
  'TLP settings mutation must arm its timeout'
assert_file_contains 'id: mutationTimeout' "$tlp_settings" \
  'TLP settings mutation must define a timeout timer'
assert_file_contains 'mutationProcess.timedOut = true' "$tlp_settings" \
  'TLP settings mutation timeout must mark the process as timed out'
assert_file_contains 'mutationProcess.running = false' "$tlp_settings" \
  'TLP settings mutation timeout must stop the privileged helper'
assert_file_contains 'const success = exitCode === 0 && !mutationProcess.timedOut' "$tlp_settings" \
  'TLP settings timed-out mutation must not report success'
assert_file_contains 'root.mutationFinished(kind, false)' "$tlp_settings" \
  'TLP settings mutation startup failure must notify callers'
assert_file_contains 'root.busy = false' "$tlp_settings" \
  'TLP settings mutation terminal paths must release busy state'


require "$tlp" 'interval: 120000' 'battery/TLP status polling must not run every 30 seconds'
require "$tlp" 'running: root.enabled || root.managed || root.busy' 'battery/TLP status polling must sleep while charge-limit ownership is irrelevant'
require "$thinkfan" 'readonly property int _statusFreshnessMs: 30 * 1000' 'ThinkFan profile-follow events must retain a short status freshness bound'
require "$thinkfan" 'readonly property int _activePollMs: 30 * 1000' 'active ThinkFan status polling must remain responsive'
require "$thinkfan" 'readonly property int _idleSafetyPollMs: 5 * 60 * 1000' 'idle ThinkFan profile-follow polling must use a sparse safety cadence'
require "$thinkfan" 'interval: (root.active || root.busy)' 'ThinkFan polling cadence must adapt to active versus idle state'
require "$thinkfan" '? root._activePollMs : root._idleSafetyPollMs' 'ThinkFan polling must use the active and safety cadence tokens'
require "$thinkfan" 'Date.now() - root._lastStatusRefreshAt >= root._statusFreshnessMs' 'ThinkFan profile/config changes must demand-refresh stale status'
require "$thinkfan" 'function onProfileChanged(): void {' 'ThinkFan must keep event-driven power-profile following'
require "$thinkfan" 'root._handleProfileFollowEvent()' 'ThinkFan profile/config events must route through freshness-aware handling'
require "$thinkfan" 'running: root.profileFanControlEnabled || root.active || root.busy' 'ThinkFan polling must sleep while fan control is irrelevant'
require "$tlp_caps" 'readonly property int safetyRefreshIntervalMs: 30 * 60 * 1000' 'TLP runtime capability background probes must use a sparse safety cadence'
require "$tlp_caps" 'interval: root.safetyRefreshIntervalMs' 'TLP runtime capability timer must use the sparse safety cadence'
require "$tlp_caps" 'id: rdwCapabilityProbe' 'TLP RDW availability must use one combined capability probe'
require "$tlp_caps" '[ -x /usr/bin/tlp-rdw ] && ' 'TLP RDW probe must retain executable-presence semantics'
require "$tlp_caps" '/usr/bin/systemctl is-enabled --quiet NetworkManager-dispatcher.service' 'TLP RDW probe must retain dispatcher-enabled semantics'
reject "$tlp_caps" 'id: rdwBinaryProbe' 'TLP RDW refresh must not spawn a separate binary probe'
reject "$tlp_caps" 'id: rdwDispatcherProbe' 'TLP RDW refresh must not spawn a second dispatcher process'
require "$tlp_settings" 'readonly property int safetyRefreshIntervalMs: 30 * 60 * 1000' 'TLP settings background status refresh must use a sparse safety cadence'
require "$tlp_settings" 'interval: root.safetyRefreshIntervalMs' 'TLP settings timer must use the sparse safety cadence'

printf '%s\n' ALIS_INTERGRATION_WORKER_LIFECYCLE_PASS
