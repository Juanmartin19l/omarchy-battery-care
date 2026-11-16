import QtQuick
import Quickshell.Services.UPower
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.juanmartin19l.battery-care"
  ipcTarget: "io.github.juanmartin19l.battery-care"

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor("io.github.juanmartin19l.battery-care") : null
  readonly property bool available: svc ? svc.available : false
  readonly property string chargeType: svc ? svc.chargeType : ""
  readonly property bool oneShot: svc ? svc.oneShot : false
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.45)

  // Nerd Font / Material Design glyphs.
  readonly property var icons: ({
    Fast: "󰂄",       // battery_charging
    Standard: "󰁹",   // battery
    Long_Life: "󱈑",  // battery_heart_variant
    OneShot: "󰂅"     // battery_charging_100
  })

  function glyph(mode) { return icons[mode] || icons.Standard }

  function modeColor(mode) {
    if (mode === "Fast") return Color.accent
    if (mode === "Long_Life") return svc ? svc.healthyColor : fg
    if (mode === "Standard") return dim
    return fg
  }

  readonly property string barGlyph: oneShot ? icons.OneShot : glyph(chargeType)
  readonly property color barColor: oneShot ? Color.accent : modeColor(chargeType)

  readonly property bool batteryPresent: !!(UPower.displayDevice && UPower.displayDevice.isPresent)
  readonly property int percent: batteryPresent ? Math.round(UPower.displayDevice.percentage * 100) : 0
  readonly property string stateText: {
    if (!batteryPresent) return ""
    if (UPower.onBattery) return strings.t("state.discharging")
    var s = UPower.displayDevice.state
    if (s === UPowerDeviceState.Charging) return strings.t("state.charging")
    if (chargeType === "Long_Life" && percent < 100) return strings.t("state.held")
    return strings.t("state.full")
  }

  readonly property var modes: ["Fast", "Standard", "Long_Life"]

  onOpenedChanged: if (svc) svc.panelOpen = opened

  visible: available
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barGlyph
    active: root.chargeType === "Long_Life"
    useActiveColor: false
    foreground: root.barColor
    tooltipText: root.oneShot ? strings.t("tip.oneshot") : strings.t("tip." + (root.chargeType || "Standard"))
    onPressed: function(b) {
      if (!root.svc) return
      if (b === Qt.RightButton) {
        if (root.chargeType === "Long_Life") root.svc.startOneShot()
        else root.svc.setChargeType("Long_Life")
      } else {
        root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.available
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        PanelHero {
          foreground: root.fg
          fontFamily: root.bar.fontFamily
          title: strings.t("title")
          meta: root.batteryPresent
            ? strings.t("percentState").replace("%1", Commons.I18n.formatNumber(root.percent)).replace("%2", root.stateText)
            : strings.t("noBattery")
          iconComponent: Text {
            textFormat: Text.PlainText
            text: root.barGlyph
            color: root.barColor
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
          }
        }

        Text {
          visible: root.svc && !root.svc.writable
          width: parent.width
          textFormat: Text.PlainText
          text: strings.t("setup.missing")
          color: Color.urgent
          wrapMode: Text.Wrap
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        PanelSectionHeader {
          text: strings.t("section.mode")
          foreground: root.fg
          fontFamily: root.bar.fontFamily
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Repeater {
            model: root.modes

            delegate: Column {
              required property string modelData
              width: (parent.width - parent.spacing * 2) / 3
              spacing: Style.space(6)

              Button {
                width: parent.width
                iconText: root.glyph(modelData)
                iconSize: Style.font.title
                text: strings.t("mode." + modelData)
                fontSize: Style.font.bodySmall
                foreground: root.modeColor(modelData)
                fontFamily: root.bar.fontFamily
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: !root.oneShot && root.chargeType === modelData
                onClicked: root.svc.setChargeType(modelData)
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: strings.t("hint." + modelData)
                color: root.dim
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
              }
            }
          }
        }

        PanelSeparator { foreground: root.fg }

        Item {
          width: parent.width
          implicitHeight: Math.max(oneShotLabels.implicitHeight, oneShotSwitch.implicitHeight)

          Column {
            id: oneShotLabels
            anchors.left: parent.left
            anchors.right: oneShotSwitch.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: strings.t("oneshot.title")
              color: root.fg
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.oneShot ? strings.t("oneshot.active") : strings.t("oneshot.hint")
              color: root.oneShot ? Color.accent : root.dim
              wrapMode: Text.Wrap
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          ToggleSwitch {
            id: oneShotSwitch
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            foreground: root.fg
            checked: root.oneShot
            onToggled: root.oneShot ? root.svc.cancelOneShot() : root.svc.startOneShot()
          }
        }

        PanelSeparator { foreground: root.fg }

        Row {
          width: parent.width
          spacing: Style.space(20)

          InfoPair {
            width: (parent.width - parent.spacing) / 2
            label: strings.t("cycles")
            value: root.svc && root.svc.cycleCount >= 0 ? Commons.I18n.formatNumber(root.svc.cycleCount) : "—"
          }

          InfoPair {
            width: (parent.width - parent.spacing) / 2
            label: strings.t("health")
            value: root.svc && root.svc.healthPct > 0 ? Commons.I18n.formatNumber(root.svc.healthPct) + "%" : "—"
          }
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""
    spacing: Style.space(8)

    Text {
      textFormat: Text.PlainText
      text: label
      color: root.fg
      opacity: 0.6
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Item {
      width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2)
      height: 1
    }

    Text {
      textFormat: Text.PlainText
      text: value
      color: root.fg
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
