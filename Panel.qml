import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "codeburn"
  ipcTarget: "codeburn"

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color subtleText: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.60)
  readonly property color accentColor: Color.accent
  readonly property color flameColor: "#ff7043"
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string statusCommand: {
    var resolved = Qt.resolvedUrl("status.sh").toString().replace(/^file:\/\//, "")
    return resolved !== "" ? resolved : ((Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/codeburn/status.sh")
  }
  readonly property int refreshIntervalSec: Math.max(60, Number(setting("refreshIntervalSec", 300)) || 300)

  // Reporting Periods
  property string selectedPeriod: "today"
  readonly property var periods: [
    { id: "today", label: "Today" },
    { id: "week", label: "7 Days" },
    { id: "30days", label: "30 Days" },
    { id: "month", label: "Month" },
    { id: "all", label: "6 Months" },
    { id: "lifetime", label: "Lifetime" }
  ]

  function periodLabel(id) {
    for (var i = 0; i < periods.length; i++) {
      if (periods[i].id === id) return periods[i].label
    }
    return "Today"
  }

  readonly property string selectedPeriodLabel: periodLabel(selectedPeriod)

  function selectPeriod(periodId) {
    if (selectedPeriod === periodId) return
    selectedPeriod = periodId
    refresh()
  }

  function cyclePeriod(direction) {
    var currentIndex = 0
    for (var i = 0; i < periods.length; i++) {
      if (periods[i].id === selectedPeriod) {
        currentIndex = i
        break
      }
    }
    var nextIndex = (currentIndex + direction + periods.length) % periods.length
    selectPeriod(periods[nextIndex].id)
  }

  property var statusData: null
  property bool refreshing: false
  property bool hasError: false
  property string errorMessage: ""
  property double lastUpdatedMs: 0
  property double nowMs: Date.now()

  // --- Data Accessors ---
  readonly property var current: statusData ? statusData.current : null
  readonly property real cost: current && current.cost !== undefined ? Number(current.cost) : 0
  readonly property int calls: current && current.calls !== undefined ? Number(current.calls) : 0
  readonly property int sessions: current && current.sessions !== undefined ? Number(current.sessions) : 0
  readonly property real inputTokens: current && current.inputTokens !== undefined ? Number(current.inputTokens) : 0
  readonly property real outputTokens: current && current.outputTokens !== undefined ? Number(current.outputTokens) : 0
  readonly property real cacheReadTokens: current && current.cacheReadTokens !== undefined ? Number(current.cacheReadTokens) : 0
  readonly property real cacheHitPercent: current && current.cacheHitPercent !== undefined ? Number(current.cacheHitPercent) : 0
  readonly property var topModels: current && Array.isArray(current.topModels) ? current.topModels : []
  readonly property var providerDetails: current && Array.isArray(current.providerDetails) ? current.providerDetails : []
  readonly property var topActivities: current && Array.isArray(current.topActivities) ? current.topActivities : []
  readonly property var optimize: statusData && statusData.optimize ? statusData.optimize : null
  readonly property var currency: statusData && statusData.currency ? statusData.currency : ({ symbol: "$", code: "USD" })
  readonly property string currencySymbol: currency && currency.symbol ? String(currency.symbol) : "$"

  // DeepSeek peak schedule is whatever the CLI put on `deepseek`. Do not derive phase from the clock.
  readonly property var deepseekRaw: {
    var block = statusData ? statusData.deepseek : null
    if (!block || typeof block !== "object" || Array.isArray(block)) return null
    return block
  }
  readonly property string deepseekPhase: {
    if (!deepseekRaw) return ""
    var phase = deepseekRaw.phase
    if (phase === "peak" || phase === "off-peak") return phase
    return ""
  }
  readonly property color deepseekTone: deepseekPhase === "off-peak" ? accentColor : flameColor
  readonly property var deepseekNextChangeMs: {
    if (!deepseekRaw) return null
    var raw = deepseekRaw.nextChangeAt
    if (raw === undefined || raw === null || String(raw).trim() === "") return null
    var ms = Date.parse(String(raw))
    if (typeof ms !== "number" || ms !== ms || ms <= 0) return null
    return ms
  }
  readonly property var deepseekModels: buildDeepseekModels(deepseekRaw)
  readonly property bool showDeepSeek: isOnline && (deepseekPhase !== "" || deepseekModels.length > 0)
  readonly property string deepseekFlipLine: buildDeepseekFlipLine(deepseekPhase, deepseekNextChangeMs, nowMs)
  readonly property string deepseekWhenLine: buildDeepseekWhenLine(deepseekNextChangeMs)
  readonly property string deepseekWindowsLine: buildDeepseekWindowsLine(deepseekRaw)
  readonly property string deepseekHolidayLine: buildDeepseekHolidayLine(deepseekRaw)
  readonly property string deepseekFootnote: buildDeepseekFootnote(deepseekRaw)
  readonly property string barPhaseText: (!isOnline || deepseekPhase === "") ? "" : deepseekPhase
  readonly property var deepseekRateRows: [
    { field: "inputCacheHitPerMillion", label: "Cache hit" },
    { field: "inputCacheMissPerMillion", label: "Cache miss" },
    { field: "outputPerMillion", label: "Output" }
  ]
  property double deepseekRefreshForMs: -1

  readonly property bool isOnline: !hasError && statusData !== null
  readonly property string barCostText: isOnline ? formatCost(cost) : "--"
  readonly property string barStatusText: "󰈸 " + barCostText
  readonly property string barTooltipText: {
    var base = isOnline
      ? ("CodeBurn (" + selectedPeriodLabel + "): " + formatCost(cost) + " · " + calls + " calls · " + sessions + " sessions")
      : "CodeBurn: status unavailable"
    if (barPhaseText !== "") {
      base += " · DeepSeek " + barPhaseText
      if (deepseekFlipLine !== "") base += " · " + deepseekFlipLine
    }
    return base + " (right-click to refresh)"
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function formatCost(val) {
    var num = Number(val || 0)
    if (num === 0) return currencySymbol + "0.00"
    if (num < 0.01) return "<" + currencySymbol + "0.01"
    return currencySymbol + num.toFixed(2)
  }

  function formatTokens(n) {
    var num = Number(n || 0)
    if (num >= 1000000000) return (num / 1000000000).toFixed(1) + "B"
    if (num >= 1000000) return (num / 1000000).toFixed(1) + "M"
    if (num >= 1000) return (num / 1000).toFixed(1) + "k"
    return String(Math.round(num))
  }

  function formatNumber(n) {
    var num = Number(n || 0)
    return num.toLocaleString()
  }

  function finiteNumber(value) {
    if (value === undefined || value === null || value === "") return NaN
    var n = Number(value)
    if (!isFinite(n)) return NaN
    return n
  }

  // USD per 1M tokens. Keep at least two decimals so a JSON 0.3 still reads as $0.30,
  // and keep extra digits when the published rate needs them ($0.044, $0.006).
  function formatUsdPerMillion(value) {
    var n = finiteNumber(value)
    if (n !== n) return "—"
    var negative = n < 0
    var abs = Math.abs(n)
    var digits = (abs > 0 && abs < 0.000001) ? 8 : 6
    var fixed = abs.toFixed(digits)
    var bits = fixed.split(".")
    var frac = bits.length > 1 ? bits[1] : ""
    frac = frac.replace(/0+$/, "")
    while (frac.length < 2) frac += "0"
    return (negative ? "-" : "") + "$" + bits[0] + "." + frac
  }

  function hasRate(rates, key) {
    if (!rates || typeof rates !== "object" || Array.isArray(rates)) return false
    var n = finiteNumber(rates[key])
    return n === n
  }

  function rateText(rates, key) {
    if (!hasRate(rates, key)) return "—"
    return formatUsdPerMillion(rates[key])
  }

  function formatDuration(ms) {
    var totalMin = Math.floor(Number(ms) / 60000)
    if (!(totalMin >= 1)) return "less than a minute"
    var days = Math.floor(totalMin / 1440)
    var hours = Math.floor(totalMin / 60) % 24
    var mins = totalMin % 60
    if (days > 0) return days + "d " + hours + "h"
    if (hours > 0) return hours + "h " + mins + "m"
    return mins + "m"
  }

  function formatClock(ms, utc) {
    var d = new Date(ms)
    var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    var hh = utc ? d.getUTCHours() : d.getHours()
    var mm = utc ? d.getUTCMinutes() : d.getMinutes()
    var dayIndex = utc ? d.getUTCDay() : d.getDay()
    var pad = function(n) { return (n < 10 ? "0" : "") + n }
    var day = days[dayIndex] || ""
    return day + " " + pad(hh) + ":" + pad(mm)
  }

  function buildDeepseekFlipLine(phase, nextMs, now) {
    if (typeof nextMs !== "number" || nextMs !== nextMs) return ""
    var target = phase === "peak" ? "off-peak" : (phase === "off-peak" ? "peak" : "the next phase")
    if (Number(now) >= nextMs) return "Switch to " + target + " is due — refresh to update"
    return "Switches to " + target + " in " + formatDuration(nextMs - Number(now))
  }

  function buildDeepseekWhenLine(nextMs) {
    if (typeof nextMs !== "number" || nextMs !== nextMs) return ""
    return formatClock(nextMs, false) + " local · " + formatClock(nextMs, true) + " UTC"
  }

  function buildDeepseekWindowsLine(block) {
    if (!block || typeof block !== "object" || Array.isArray(block)) return ""
    var days = ""
    if (block.peakDaysUtc !== undefined && block.peakDaysUtc !== null && String(block.peakDaysUtc).trim() !== "")
      days = String(block.peakDaysUtc).trim()
    var parts = []
    if (Array.isArray(block.peakWindowsUtc)) {
      for (var i = 0; i < block.peakWindowsUtc.length; i++) {
        var span = block.peakWindowsUtc[i]
        if (!span || typeof span !== "object" || Array.isArray(span)) continue
        if (span.start === undefined || span.start === null || span.end === undefined || span.end === null) continue
        var start = String(span.start).trim()
        var end = String(span.end).trim()
        if (start === "" || end === "") continue
        parts.push(start + "–" + end)
      }
    }
    var clock = parts.join(", ")
    var tz = ""
    if (block.timezone !== undefined && block.timezone !== null && String(block.timezone).trim() !== "")
      tz = String(block.timezone).trim()
    if (clock !== "" && tz !== "") clock = clock + " " + tz
    if (days !== "" && clock !== "") return "Peak windows " + days + " · " + clock
    if (clock !== "") return "Peak windows " + clock
    if (days !== "") return "Peak days " + days
    return ""
  }


  function buildDeepseekHolidayLine(block) {
    if (!block || typeof block !== "object" || Array.isArray(block)) return ""
    var nh = block.nextHoliday
    var start = ""
    var end = ""
    if (nh && typeof nh === "object" && !Array.isArray(nh)) {
      if (nh.start !== undefined && nh.start !== null) start = String(nh.start).trim()
      if (nh.end !== undefined && nh.end !== null) end = String(nh.end).trim()
    }
    if (block.holiday === true) {
      if (end !== "") return "Chinese public holiday through " + end + " UTC"
      return "UTC date is a Chinese public holiday"
    }
    if (start === "") return ""
    if (end !== "" && end !== start) return "Next Chinese holiday · " + start + " – " + end + " UTC"
    return "Next Chinese holiday · " + start + " UTC"
  }

  function aliasSummary(list) {
    if (!Array.isArray(list)) return ""
    var names = []
    for (var i = 0; i < list.length; i++) {
      if (list[i] === undefined || list[i] === null) continue
      var text = String(list[i]).trim()
      if (text === "") continue
      names.push(text)
    }
    if (names.length === 0) return ""
    var shown = names.slice(0, 3)
    var summary = shown.join(", ")
    if (names.length > shown.length) summary += " +" + (names.length - shown.length)
    return summary
  }

  function usableRateCard(rates) {
    return hasRate(rates, "inputCacheHitPerMillion")
      || hasRate(rates, "inputCacheMissPerMillion")
      || hasRate(rates, "outputPerMillion")
  }

  function buildDeepseekModels(block) {
    if (!block || typeof block !== "object" || Array.isArray(block) || !Array.isArray(block.models)) return []
    var out = []
    var limit = block.models.length
    if (limit > 12) limit = 12
    for (var i = 0; i < limit; i++) {
      var model = block.models[i]
      if (!model || typeof model !== "object" || Array.isArray(model)) continue
      var label = ""
      if (model.label !== undefined && model.label !== null && String(model.label).trim() !== "")
        label = String(model.label).trim()
      else if (model.id !== undefined && model.id !== null && String(model.id).trim() !== "")
        label = String(model.id).trim()
      if (label === "") continue
      var peak = usableRateCard(model.peak) ? model.peak : null
      var offPeak = usableRateCard(model.offPeak) ? model.offPeak : null
      if (!peak && !offPeak) continue
      var id = ""
      if (model.id !== undefined && model.id !== null) id = String(model.id).trim()
      out.push({
        label: label,
        id: id,
        aliases: aliasSummary(model.alsoBilledAs),
        peak: peak || {},
        offPeak: offPeak || {}
      })
    }
    return out
  }

  function formatFactor(value) {
    var n = finiteNumber(value)
    if (n !== n || n <= 0) return ""
    var rounded = Math.round(n * 1000) / 1000
    return String(rounded) + "×"
  }

  function providerDisplayName(id) {
    if (id === "dsh") return "DeepSeek Harness (dsh)"
    if (id === "claude") return "Claude (claude)"
    return id
  }

  function buildDeepseekFootnote(block) {
    if (!block || typeof block !== "object" || Array.isArray(block)) return ""
    var bits = []
    if (Array.isArray(block.appliesToProviders)) {
      var names = []
      for (var i = 0; i < block.appliesToProviders.length; i++) {
        var entry = block.appliesToProviders[i]
        if (entry === undefined || entry === null) continue
        var id = String(entry).trim()
        if (id === "") continue
        names.push(providerDisplayName(id))
      }
      if (names.length === 1) bits.push("Applies to " + names[0])
      else if (names.length === 2) bits.push("Applies to " + names[0] + " and " + names[1])
      else if (names.length > 2) bits.push("Applies to " + names.slice(0, names.length - 1).join(", ") + ", and " + names[names.length - 1])
    }
    var factor = formatFactor(block.offPeakFactor)
    if (factor !== "") bits.push("Off-peak is " + factor + " peak")
    if (block.missingTimestamp === "peak") bits.push("Calls with no timestamp bill at peak")
    return bits.join(" · ")
  }

  function timeAgo(ms) {
    if (!ms || ms <= 0) return ""
    var diffSec = Math.max(0, Math.floor((nowMs - ms) / 1000))
    if (diffSec < 10) return "just now"
    if (diffSec < 60) return diffSec + "s ago"
    var diffMin = Math.floor(diffSec / 60)
    if (diffMin < 60) return diffMin + "m ago"
    var diffHr = Math.floor(diffMin / 60)
    return diffHr + "h ago"
  }

  function parseStatus(raw) {
    try {
      var trimmed = String(raw || "").trim()
      if (!trimmed) {
        hasError = true
        errorMessage = "Empty output from CodeBurn"
        return
      }
      var parsed = JSON.parse(trimmed)
      if (parsed && typeof parsed === "object") {
        if (parsed.error) {
          hasError = true
          errorMessage = String(parsed.error)
        } else {
          statusData = parsed
          hasError = false
          errorMessage = ""
          lastUpdatedMs = Date.now()
          nowMs = Date.now()
        }
      } else {
        hasError = true
        errorMessage = "Invalid JSON structure"
      }
    } catch (e) {
      console.warn("codeburn: JSON parse error", e)
      hasError = true
      errorMessage = "Unable to parse CodeBurn JSON output"
    }
  }

  function refresh() {
    if (statusProcess.running) return
    refreshing = true
    statusProcess.running = true
  }

  onOpenedChanged: if (opened) {
    nowMs = Date.now()
    if (Date.now() - lastUpdatedMs > 60000) {
      refresh()
    }
    if (Date.now() - quotaUpdatedMs > 60000) {
      refreshQuota()
    }
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Process {
    id: statusProcess
    command: [root.statusCommand, root.selectedPeriod]
    running: false

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseStatus(text)
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text && text.trim().length > 0) {
          console.warn("codeburn stderr:", text.trim())
        }
      }
    }

    onExited: function(exitCode) {
      root.refreshing = false
      if (exitCode !== 0) {
        root.hasError = true
        if (root.errorMessage === "") {
          root.errorMessage = "CodeBurn command exited with code " + exitCode
        }
      }
    }
  }

  Timer {
    id: pollTimer
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: tickTimer
    interval: 15000
    running: root.opened || root.showDeepSeek
    repeat: true
    onTriggered: {
      root.nowMs = Date.now()
      var next = root.deepseekNextChangeMs
      if (typeof next !== "number" || next !== next) return
      if (root.nowMs < next) return
      if (root.deepseekRefreshForMs === next) return
      if (root.refreshing || statusProcess.running) return
      root.deepseekRefreshForMs = next
      root.refresh()
    }
  }

  // ------------------------------------------------------------- QUOTA
  property var quotaData: null
  property string quotaError: ""
  property double quotaUpdatedMs: 0
  readonly property int quotaRefreshSec: 300
  readonly property var quotaProviders: {
    var list = quotaData && Array.isArray(quotaData.providers) ? quotaData.providers : []
    return list.filter(function(p) { return p && p.available === true && Array.isArray(p.windows) && p.windows.length > 0 })
  }
  readonly property bool showQuota: quotaProviders.length > 0 || quotaError !== ""

  function refreshQuota() {
    if (quotaProcess.running) return
    quotaProcess.running = true
  }

  function parseQuota(raw) {
    try {
      var trimmed = String(raw || "").trim()
      if (!trimmed) { quotaError = "Quota: empty output"; return }
      var parsed = JSON.parse(trimmed)
      if (parsed && parsed.error) { quotaError = "Quota: " + String(parsed.error); return }
      if (!parsed || !Array.isArray(parsed.providers)) { quotaError = "Quota: unexpected output"; return }
      quotaData = parsed
      quotaError = ""
      quotaUpdatedMs = Date.now()
    } catch (e) {
      quotaError = "Quota: unable to parse CodeBurn output"
    }
  }

  function formatResetDate(iso) {
    var ms = Date.parse(iso)
    if (!(ms === ms)) return ""
    var d = new Date(ms)
    var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    var pad = function(n) { return (n < 10 ? "0" : "") + n }
    return days[d.getDay()] + " " + d.getDate() + " " + months[d.getMonth()] + " " + pad(d.getHours()) + ":" + pad(d.getMinutes())
  }

  function formatResetRelative(iso, now) {
    var ms = Date.parse(iso)
    if (!(ms === ms)) return ""
    var diff = ms - now
    if (diff <= 0) return "now"
    var totalMin = Math.floor(diff / 60000)
    var days = Math.floor(totalMin / 1440)
    var hours = Math.floor(totalMin / 60) % 24
    if (days > 0) return "in " + days + "d" + (hours > 0 ? " " + hours + "h" : "")
    if (hours > 0) return "in " + hours + "h " + (totalMin % 60) + "m"
    return "in " + Math.max(1, totalMin) + "m"
  }

  function quotaPct(w) {
    var n = Number(w && w.usedPct)
    return n === n ? Math.max(0, Math.min(100, n)) : 0
  }

  Process {
    id: quotaProcess
    command: ["timeout", "45", root.statusCommand, "quota"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseQuota(text)
    }
    onExited: function(exitCode) {
      if (exitCode === 124) root.quotaError = "Quota: CodeBurn timed out"
      else if (exitCode !== 0 && root.quotaError === "") root.quotaError = "Quota: CodeBurn exited with code " + exitCode
    }
  }

  Timer {
    id: quotaTimer
    interval: root.quotaRefreshSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshQuota()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function setPeriod(p: string): string { root.selectPeriod(p); return "ok" }
    function nextPeriod(): string { root.cyclePeriod(1); return "ok" }
    function prevPeriod(): string { root.cyclePeriod(-1); return "ok" }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barStatusText
    active: root.isOnline && root.cost > 0
    activeColor: root.accentColor
    fontSize: Style.font.bodySmall
    horizontalMargin: 4
    tooltipText: root.barTooltipText

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(690))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dx !== 0) {
          root.cyclePeriod(dx > 0 ? 1 : -1)
        } else if (dy !== 0 && panelFlick) {
          panelFlick.contentY = Math.max(0, Math.min(
            panelFlick.contentY + dy * Style.space(60),
            Math.max(0, panelFlick.contentHeight - panelFlick.height)
          ))
        }
      }
      onActivateRequested: root.refresh()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r" || text === "R") root.refresh()
        else if (text === "1") root.selectPeriod("today")
        else if (text === "2") root.selectPeriod("week")
        else if (text === "3") root.selectPeriod("30days")
        else if (text === "4") root.selectPeriod("month")
        else if (text === "5") root.selectPeriod("all")
        else if (text === "6") root.selectPeriod("lifetime")
        else if (text === "]" || text === "p") root.cyclePeriod(1)
        else if (text === "[" || text === "P") root.cyclePeriod(-1)
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: contentColumn
          width: panelFlick.width
          spacing: Style.space(12)

          // ------------------------------------------------------------- HERO
          PanelHero {
            width: parent.width
            title: "CodeBurn"
            meta: root.isOnline
              ? (root.current && root.current.label ? String(root.current.label).toUpperCase() : root.selectedPeriodLabel.toUpperCase())
              : "STATUS"
            detail: root.isOnline ? root.formatCost(root.cost) : "Offline"
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Text {
                text: "󰈸"
                color: root.isOnline ? root.flameColor : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }

            trailingControl: Component {
              PanelActionButton {
                iconText: root.refreshing ? "󱑒" : "󰑐"
                tooltipText: "Refresh status (R)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.refresh()
              }
            }
          }

          // --------------------------------------------------- PERIOD SELECTOR
          BorderSurface {
            width: parent.width
            implicitHeight: periodRow.implicitHeight + Style.space(6)
            radius: Style.cornerRadius
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
            borderSpec: Border.none()

            Row {
              id: periodRow
              anchors.centerIn: parent
              width: parent.width - Style.space(6)
              spacing: Style.space(3)

              Repeater {
                model: root.periods

                Item {
                  required property var modelData
                  required property int index

                  width: (periodRow.width - (root.periods.length - 1) * periodRow.spacing) / root.periods.length
                  implicitHeight: Style.space(24)

                  readonly property bool isSelected: root.selectedPeriod === modelData.id
                  readonly property bool isHot: segMouse.containsMouse

                  BorderSurface {
                    anchors.fill: parent
                    radius: Style.cornerRadius
                    color: isSelected
                      ? Style.selectedFillFor(root.accentColor, root.accentColor)
                      : (isHot ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent")
                    borderSpec: isSelected
                      ? Border.controlSpec("focus", root.accentColor, root.accentColor)
                      : Border.none()

                    Text {
                      anchors.centerIn: parent
                      text: modelData.label
                      color: isSelected ? root.accentColor : (isHot ? root.foreground : root.dim)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: isSelected
                    }

                    MouseArea {
                      id: segMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.selectPeriod(modelData.id)
                    }
                  }
                }
              }
            }
          }

          // ------------------------------------------------------- ERROR CARD
          BorderSurface {
            id: errorCard
            visible: !root.isOnline
            width: parent.width
            implicitHeight: errorColumn.implicitHeight + Style.space(24)
            radius: Style.cornerRadius
            color: Style.selectedFillFor(root.urgent, root.urgent)
            borderSpec: Border.controlSpec("normal", root.urgent, root.urgent)

            Column {
              id: errorColumn
              anchors.centerIn: parent
              width: parent.width - Style.space(24)
              spacing: Style.space(8)

              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(8)

                Text {
                  text: ""
                  color: root.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                }

                Text {
                  text: "CodeBurn Status Unavailable"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                }
              }

              Text {
                width: parent.width
                text: root.errorMessage !== ""
                  ? root.errorMessage
                  : "Unable to run the CodeBurn fork. Install the local build or put codeburn on PATH."
                color: root.subtleText
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
              }

              BorderSurface {
                anchors.horizontalCenter: parent.horizontalCenter
                implicitWidth: codeHint.implicitWidth + Style.space(16)
                implicitHeight: codeHint.implicitHeight + Style.space(8)
                radius: Style.cornerRadius
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
                borderSpec: Border.controlSpec("normal", root.foreground, root.accentColor)

                Text {
                  id: codeHint
                  anchors.centerIn: parent
                  text: "CodeBurn CLI"
                  color: root.accentColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }
          }

          // ---------------------------------------------------- SUMMARY METRICS
          Column {
            visible: root.isOnline
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: (root.current && root.current.label ? String(root.current.label).toUpperCase() : root.selectedPeriodLabel.toUpperCase()) + " OVERVIEW"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              SummaryCell {
                label: "Cost"
                value: root.formatCost(root.cost)
                active: root.cost > 0
                highlightColor: root.flameColor
              }

              SummaryCell {
                label: "Calls"
                value: root.formatNumber(root.calls)
                active: root.calls > 0
              }

              SummaryCell {
                label: "Sessions"
                value: root.formatNumber(root.sessions)
                active: root.sessions > 0
              }

              SummaryCell {
                label: "Cache Hit"
                value: root.cacheHitPercent > 0 ? (root.cacheHitPercent.toFixed(1) + "%") : "0%"
                active: root.cacheHitPercent > 0
                highlightColor: root.accentColor
              }
            }

            // Secondary Token Counts Pill
            BorderSurface {
              width: parent.width
              implicitHeight: tokenRow.implicitHeight + Style.space(10)
              radius: Style.cornerRadius
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)
              borderSpec: Border.none()

              Row {
                id: tokenRow
                anchors.centerIn: parent
                spacing: Style.space(14)

                Row {
                  spacing: Style.space(4)
                  Text { text: "󰁅"; color: root.subtleText; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                  Text { text: "In: " + root.formatTokens(root.inputTokens); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                }

                Text { text: "·"; color: root.dim; font.family: root.fontFamily }

                Row {
                  spacing: Style.space(4)
                  Text { text: "󰁝"; color: root.subtleText; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                  Text { text: "Out: " + root.formatTokens(root.outputTokens); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                }

                Text { text: "·"; color: root.dim; font.family: root.fontFamily }

                Row {
                  spacing: Style.space(4)
                  Text { text: "󰒲"; color: root.subtleText; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                  Text { text: "Cache: " + root.formatTokens(root.cacheReadTokens); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                }
              }
            }
          }

          // ---------------------------------------------------------- DEEPSEEK
          PanelSeparator {
            visible: root.showDeepSeek
            foreground: root.foreground
          }

          Column {
            visible: root.showDeepSeek
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "DEEPSEEK"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            BorderSurface {
              visible: root.deepseekPhase !== "" || root.deepseekFlipLine !== "" || root.deepseekWhenLine !== "" || root.deepseekWindowsLine !== "" || root.deepseekHolidayLine !== ""
              width: parent.width
              implicitHeight: deepseekPhaseColumn.implicitHeight + Style.space(20)
              radius: Style.cornerRadius
              color: root.deepseekPhase !== ""
                ? Qt.rgba(root.deepseekTone.r, root.deepseekTone.g, root.deepseekTone.b, 0.10)
                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              borderSpec: root.deepseekPhase !== ""
                ? Border.controlSpec("normal", root.deepseekTone, root.deepseekTone)
                : Border.none()

              Column {
                id: deepseekPhaseColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                spacing: Style.space(3)

                Row {
                  visible: root.deepseekPhase !== ""
                  spacing: Style.space(8)

                  Text {
                    text: root.deepseekPhase === "off-peak" ? "OFF-PEAK" : "PEAK"
                    color: root.deepseekTone
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    font.letterSpacing: 0.6
                  }

                  Text {
                    text: root.deepseekPhase === "off-peak" ? "Off-peak now" : "Peak now"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                }

                Text {
                  visible: root.deepseekFlipLine !== ""
                  width: deepseekPhaseColumn.width
                  wrapMode: Text.WordWrap
                  text: root.deepseekFlipLine
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  visible: root.deepseekWhenLine !== ""
                  width: deepseekPhaseColumn.width
                  wrapMode: Text.WordWrap
                  text: root.deepseekWhenLine
                  color: root.subtleText
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  visible: root.deepseekWindowsLine !== ""
                  width: deepseekPhaseColumn.width
                  wrapMode: Text.WordWrap
                  text: root.deepseekWindowsLine
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  visible: root.deepseekHolidayLine !== ""
                  width: deepseekPhaseColumn.width
                  wrapMode: Text.WordWrap
                  text: root.deepseekHolidayLine
                  color: root.subtleText
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            // Per-model USD rates intentionally hidden: keep only the phase/status block above.
            Text {
              visible: false
              width: parent.width
              text: "USD PER 1M TOKENS"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 0.8
            }

            Repeater {
              model: []
              DeepSeekRateCard {
                width: parent ? parent.width : 0
                modelLabel: modelData && modelData.label ? String(modelData.label) : ""
                modelId: modelData && modelData.id ? String(modelData.id) : ""
                aliases: modelData && modelData.aliases ? String(modelData.aliases) : ""
                peakRates: modelData && modelData.peak ? modelData.peak : ({})
                offPeakRates: modelData && modelData.offPeak ? modelData.offPeak : ({})
              }
            }

            Text {
              visible: false
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.deepseekFootnote
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // ------------------------------------------------------------- QUOTA
          PanelSeparator {
            visible: root.showQuota
            foreground: root.foreground
          }

          Column {
            visible: root.showQuota
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "QUOTA"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: root.quotaError !== "" && root.quotaProviders.length === 0
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.quotaError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: root.quotaProviders

              BorderSurface {
                id: quotaCard
                required property var modelData
                width: parent ? parent.width : 0
                implicitHeight: quotaColumn.implicitHeight + Style.space(16)
                radius: Style.cornerRadius
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
                borderSpec: Border.none()

                Column {
                  id: quotaColumn
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Style.space(8)
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  spacing: Style.space(6)

                  Row {
                    spacing: Style.space(8)
                    Text {
                      text: String(quotaCard.modelData.name || quotaCard.modelData.id || "Provider")
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }
                    Text {
                      visible: !!quotaCard.modelData.plan
                      text: String(quotaCard.modelData.plan || "")
                      color: root.subtleText
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Repeater {
                    model: quotaCard.modelData.windows

                    Column {
                      required property var modelData
                      width: quotaColumn.width
                      spacing: Style.space(3)

                      Item {
                        width: parent.width
                        implicitHeight: winLabel.implicitHeight
                        Text {
                          id: winLabel
                          anchors.left: parent.left
                          text: String(modelData.label || "")
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                        Text {
                          anchors.right: parent.right
                          text: (Math.round(root.quotaPct(modelData) * 10) / 10) + "% used"
                          color: root.quotaPct(modelData) >= 90 ? root.urgent : root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: true
                        }
                      }

                      Rectangle {
                        width: parent.width
                        height: Style.space(4)
                        radius: height / 2
                        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
                        Rectangle {
                          width: parent.width * root.quotaPct(modelData) / 100
                          height: parent.height
                          radius: parent.radius
                          color: root.quotaPct(modelData) >= 90 ? root.urgent : (root.quotaPct(modelData) >= 70 ? root.flameColor : root.accentColor)
                        }
                      }

                      Text {
                        visible: !!modelData.resetsAt
                        text: "Resets " + root.formatResetDate(modelData.resetsAt) + " · " + root.formatResetRelative(modelData.resetsAt, root.nowMs)
                        color: root.subtleText
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }

                  Text {
                    visible: !!quotaCard.modelData.error
                    width: quotaColumn.width
                    wrapMode: Text.WordWrap
                    text: String(quotaCard.modelData.error || "")
                    color: root.urgent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    visible: quotaCard.modelData.id === "grokbot" && Array.isArray(quotaCard.modelData.notes) && quotaCard.modelData.notes.length > 0
                    width: quotaColumn.width
                    wrapMode: Text.WordWrap
                    text: Array.isArray(quotaCard.modelData.notes) ? quotaCard.modelData.notes.join(" · ") : ""
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          // ---------------------------------------------------------- PROVIDERS
          PanelSeparator {
            visible: root.isOnline && root.providerDetails.length > 0
            foreground: root.foreground
          }

          Column {
            visible: root.isOnline && root.providerDetails.length > 0
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "PROVIDERS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.providerDetails

              Item {
                required property var modelData
                required property int index
                width: parent ? parent.width : 0
                implicitHeight: Style.space(32)

                BorderSurface {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
                  borderSpec: Border.none()

                  Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(8)

                    Text {
                      text: "󰌹"
                      color: root.accentColor
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }

                    Text {
                      text: String(modelData.label || modelData.id || "Provider")
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }
                  }

                  Text {
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.formatCost(modelData.cost)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                }
              }
            }
          }

          // --------------------------------------------------------- TOP MODELS
          PanelSeparator {
            visible: root.isOnline && root.topModels.length > 0
            foreground: root.foreground
          }

          Column {
            visible: root.isOnline && root.topModels.length > 0
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "TOP MODELS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.topModels.slice(0, 5)

              ModelRow {
                width: parent ? parent.width : 0
                modelItem: modelData
                totalCost: root.cost
              }
            }
          }

          // ------------------------------------------------- TOP ACTIVITIES
          PanelSeparator {
            visible: root.isOnline && root.topActivities.length > 0
            foreground: root.foreground
          }

          Column {
            visible: root.isOnline && root.topActivities.length > 0
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "TOP ACTIVITIES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.topActivities.slice(0, 4)

              Item {
                required property var modelData
                required property int index
                width: parent ? parent.width : 0
                implicitHeight: Style.space(26)

                Row {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(8)

                  Text {
                    text: String(modelData.name || "Activity")
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    visible: modelData.turns !== undefined && modelData.turns !== null
                    text: "(" + modelData.turns + " turns)"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.formatCost(modelData.cost)
                  color: Number(modelData.cost) > 0 ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: Number(modelData.cost) > 0
                }
              }
            }
          }

          // ------------------------------------------------------------- FOOTER
          PanelSeparator {
            foreground: root.foreground
          }

          Item {
            width: parent.width
            implicitHeight: Style.space(22)

            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Text {
                visible: root.lastUpdatedMs > 0
                text: "Updated " + root.timeAgo(root.lastUpdatedMs)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Text {
                text: "[←/→] Period  ·  [R] Refresh  ·  [Esc] Close"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------- SUBCOMPONENTS
  component SummaryCell: Rectangle {
    id: cellRoot
    property string label: ""
    property string value: ""
    property bool active: false
    property color highlightColor: root.foreground

    width: (parent.width - parent.spacing * 3) / 4
    implicitHeight: cellLabels.implicitHeight + Style.space(12)
    radius: Style.cornerRadius
    color: cellRoot.active
      ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.02)
    border.width: 1
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

    Column {
      id: cellLabels
      anchors.centerIn: parent
      spacing: Style.space(2)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: cellRoot.value
        color: cellRoot.active ? cellRoot.highlightColor : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: cellRoot.label.toUpperCase()
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 0.8
      }
    }
  }

  component ModelRow: Column {
    id: mRow
    property var modelItem: ({})
    property real totalCost: 1.0

    readonly property real itemCost: Number(modelItem.cost || 0)
    readonly property real ratio: totalCost > 0 ? Math.min(1.0, Math.max(0.0, itemCost / totalCost)) : 0

    width: parent ? parent.width : 0
    spacing: Style.space(4)

    Item {
      width: parent.width
      implicitHeight: Style.space(20)

      Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Text {
          text: String(modelItem.name || "Model")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: itemCost > 0
        }

        Text {
          visible: modelItem.calls !== undefined && modelItem.calls !== null
          text: "(" + modelItem.calls + " calls)"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.formatCost(itemCost)
        color: itemCost > 0 ? root.accentColor : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
    }

    // Visual distribution bar
    Rectangle {
      width: parent.width
      height: Style.space(4)
      radius: Style.cornerRadius
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

      Rectangle {
        width: Math.max(0, parent.width * mRow.ratio)
        height: parent.height
        radius: Style.cornerRadius
        color: root.flameColor
        opacity: 0.85
      }
    }
  }

  component DeepSeekRateCard: Column {
    id: card
    property string modelLabel: ""
    property string modelId: ""
    property string aliases: ""
    property var peakRates: ({})
    property var offPeakRates: ({})

    width: parent ? parent.width : 0
    spacing: Style.space(4)

    Text {
      width: card.width
      text: card.modelLabel
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      visible: card.modelId !== "" && card.modelId !== card.modelLabel
      width: card.width
      text: card.modelId
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Text {
      visible: card.aliases !== ""
      width: card.width
      text: "Also billed as " + card.aliases
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    BorderSurface {
      width: card.width
      implicitHeight: rateTable.implicitHeight + Style.space(10)
      radius: Style.cornerRadius
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
      borderSpec: Border.none()

      Column {
        id: rateTable
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(8)
        anchors.rightMargin: Style.space(8)
        spacing: Style.space(2)

        Row {
          width: parent.width
          spacing: Style.space(6)

          Text {
            width: Math.max(0, parent.width - parent.spacing * 2) * 0.42
            text: ""
          }

          Text {
            width: Math.max(0, parent.width - parent.spacing * 2) * 0.29
            text: "PEAK"
            horizontalAlignment: Text.AlignRight
            color: root.deepseekPhase === "peak" ? root.deepseekTone : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: root.deepseekPhase === "peak"
            font.letterSpacing: 0.6
          }

          Text {
            width: Math.max(0, parent.width - parent.spacing * 2) * 0.29
            text: "OFF-PEAK"
            horizontalAlignment: Text.AlignRight
            color: root.deepseekPhase === "off-peak" ? root.deepseekTone : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: root.deepseekPhase === "off-peak"
            font.letterSpacing: 0.6
          }
        }

        Repeater {
          model: root.deepseekRateRows

          Row {
            required property var modelData
            readonly property bool peakOn: root.hasRate(card.peakRates, modelData.field)
            readonly property bool offOn: root.hasRate(card.offPeakRates, modelData.field)
            visible: peakOn || offOn
            height: visible ? implicitHeight : 0
            width: rateTable.width
            spacing: Style.space(6)

            Text {
              width: Math.max(0, parent.width - parent.spacing * 2) * 0.42
              text: modelData && modelData.label ? String(modelData.label) : ""
              color: root.subtleText
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Text {
              width: Math.max(0, parent.width - parent.spacing * 2) * 0.29
              text: root.rateText(card.peakRates, modelData.field)
              horizontalAlignment: Text.AlignRight
              color: !parent.peakOn ? root.dim : (root.deepseekPhase === "peak" ? root.deepseekTone : root.foreground)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: root.deepseekPhase === "peak" && parent.peakOn
              elide: Text.ElideRight
            }

            Text {
              width: Math.max(0, parent.width - parent.spacing * 2) * 0.29
              text: root.rateText(card.offPeakRates, modelData.field)
              horizontalAlignment: Text.AlignRight
              color: !parent.offOn ? root.dim : (root.deepseekPhase === "off-peak" ? root.deepseekTone : root.foreground)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: root.deepseekPhase === "off-peak" && parent.offOn
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }
}
