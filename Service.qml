import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons

// Lenovo IdeaPad charge modes through ideapad_acpi's charge_types file:
// Fast / Standard / Long_Life. Long_Life is the firmware's conservation mode,
// a fixed cap set by the firmware (~60% on IdeaPads, ~80% on some Yoga/Legion
// models) that cannot be changed from Linux.
//
// Writes go straight to sysfs; scripts/install-permissions adds a udev rule
// that makes charge_types group-writable by wheel, so no sudo is needed.
//
// "One-time full charge": switches to Standard and returns to Long_Life once
// the battery reaches 100% or the charger is unplugged mid-charge. Turned on
// while unplugged, it waits for the charger. The flag lives in a state file
// so it survives shell restarts and reboots.
Item {
  id: root

  property var shell: null

  readonly property var validModes: ["Fast", "Standard", "Long_Life"]

  property string batteryDir: ""
  readonly property string chargeTypesFile: batteryDir ? batteryDir + "/charge_types" : ""
  property bool available: false
  property bool writable: false
  property string chargeType: ""
  property int cycleCount: -1
  property int healthPct: -1
  property bool panelOpen: false

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/io.github.juanmartin19l.battery-care"
  readonly property string oneShotFile: stateDir + "/oneshot"
  property bool oneShot: false

  readonly property int percent: {
    var d = UPower.displayDevice
    return d && d.isPresent ? Math.round(d.percentage * 100) : -1
  }

  // ---------------------------------------------------------------- reads

  Process {
    id: detect
    running: true
    command: ["sh", "-c", "for b in /sys/class/power_supply/BAT*; do [ -r \"$b/charge_types\" ] && { echo \"$b\"; exit 0; }; done; exit 1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.batteryDir = text.trim()
    }
    onExited: function(code) {
      root.available = code === 0
      if (root.available) root.refresh()
    }
  }

  function refresh() {
    if (!available) return
    if (!readProc.running) readProc.running = true
    if (panelOpen && !healthProc.running) healthProc.running = true
  }

  Process {
    id: readProc
    // Prints the mode line, then "w" if this user can write the file.
    command: ["sh", "-c", "cat \"$1\" && { [ -w \"$1\" ] && echo w || echo r; }", "sh", root.chargeTypesFile]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = text.trim().split("\n")
        var m = (lines[0] || "").match(/\[([A-Za-z_]+)\]/)
        root.chargeType = m && root.validModes.indexOf(m[1]) >= 0 ? m[1] : ""
        root.writable = lines[1] === "w"
      }
    }
  }

  Process {
    id: healthProc
    command: ["sh", "-c", "cat \"$1/cycle_count\" \"$1/energy_full\" \"$1/energy_full_design\" 2>/dev/null", "sh", root.batteryDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var l = text.trim().split("\n")
        var cycles = parseInt(l[0], 10)
        var full = parseInt(l[1], 10)
        var design = parseInt(l[2], 10)
        root.cycleCount = isNaN(cycles) ? -1 : cycles
        root.healthPct = (!isNaN(full) && design > 0) ? Math.round(full / design * 100) : -1
      }
    }
  }

  onPanelOpenChanged: if (panelOpen) refresh()

  Timer {
    interval: 10000
    running: root.available
    repeat: true
    onTriggered: {
      root.refresh()
      root.checkOneShot()
    }
  }

  // --------------------------------------------------------------- writes

  property string pendingMode: ""

  function writeMode(mode) {
    if (validModes.indexOf(mode) < 0 || !available) return
    if (writeProc.running) { pendingMode = mode; return }
    writeProc.command = ["sh", "-c", "printf %s \"$1\" > \"$2\"", "sh", mode, chargeTypesFile]
    writeProc.running = true
  }

  Process {
    id: writeProc
    onExited: {
      if (root.pendingMode !== "") {
        var next = root.pendingMode
        root.pendingMode = ""
        root.writeMode(next)
      } else {
        root.refresh()
      }
    }
  }

  // Picked by the user: cancels any one-time full charge.
  function setChargeType(mode) {
    if (!writable) return
    setOneShot(false)
    writeMode(mode)
  }

  function startOneShot() {
    if (!writable) return
    setOneShot(true)
    writeMode("Standard")
  }

  function cancelOneShot() {
    if (!writable) return
    setOneShot(false)
    writeMode("Long_Life")
  }

  function setOneShot(on) {
    if (oneShot === on) return
    oneShot = on
    flagProc.command = on
      ? ["sh", "-c", "mkdir -p \"$1\" && touch \"$2\"", "sh", stateDir, oneShotFile]
      : ["rm", "-f", oneShotFile]
    flagProc.running = true
  }

  Process { id: flagProc }

  // Reaching 100% on AC ends the one-time charge. Percentage is checked
  // rather than FullyCharged alone, because a capped battery also reports
  // FullyCharged; FullyCharged counts only once Long_Life is off.
  // Enabled while unplugged, the one-time charge waits for the charger.
  function checkOneShot() {
    if (!oneShot || percent < 0 || chargeType === "" || UPower.onBattery) return
    // The mode was changed elsewhere: the cap would stop the charge short of 100%.
    if (chargeType === "Long_Life") { writeMode("Standard"); return }
    var d = UPower.displayDevice
    if (d && d.state === UPowerDeviceState.Charging) oneShotSawCharging = true
    var full = percent >= 100
      || (chargeType !== "Long_Life" && d && d.state === UPowerDeviceState.FullyCharged)
    if (full) cancelOneShot()
  }

  // Unplugging ends the one-time charge, so the next plug-in is capped again,
  // but only once it has actually charged in this session: UPower reports
  // its initial on-battery state as a change at startup, and a one-time
  // charge turned on while unplugged must keep waiting for the charger.
  property bool oneShotSawCharging: false
  onOneShotChanged: oneShotSawCharging = false

  Connections {
    target: UPower
    function onOnBatteryChanged() {
      if (root.oneShot && UPower.onBattery && root.oneShotSawCharging) root.cancelOneShot()
      else root.checkOneShot()
    }
  }

  Connections {
    target: UPower.displayDevice
    function onPercentageChanged() { root.checkOneShot() }
    function onStateChanged() { root.checkOneShot() }
  }

  Process {
    running: true
    command: ["test", "-e", root.oneShotFile]
    onExited: function(code) {
      root.oneShot = code === 0
      root.checkOneShot()
    }
  }

  // ------------------------------------------------- theme green for Long_Life

  readonly property string themeColorsFile: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
  readonly property string themeNameFile: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
  property color healthyColor: Color.foreground

  function applyHealthyColor(raw) {
    var t = String(raw || "")
    var m = t.match(/^\s*green\s*=\s*["']?(#[0-9A-Fa-f]{6})/m)
    if (!m) m = t.match(/^\s*color2\s*=\s*["']?(#[0-9A-Fa-f]{6})/m)
    healthyColor = m ? m[1] : Color.foreground
  }

  FileView {
    id: themeColors
    path: root.themeColorsFile
    watchChanges: true
    printErrors: false
    onLoaded: root.applyHealthyColor(text())
    onLoadFailed: root.applyHealthyColor("")
  }

  FileView {
    path: root.themeNameFile
    watchChanges: true
    printErrors: false
    onFileChanged: themeColors.reload()
  }
}
