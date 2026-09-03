// Pure date and format math for the clock widget and its calendar panel.
// Everything here is locale- and Qt-free so it can be unit tested under node
// (test/shell.d/clock-test.sh); the QML owns month/weekday naming through
// Qt.locale().

var MS_PER_DAY = 86400000

// Weekday indices match both JS Date.getDay() and QML's Locale.Sunday…
// Locale.Saturday, so a locale's firstDayOfWeek can be passed straight in.
var WEEKDAY_NAMES = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

// ---- Bar label formats. Right-clicking the clock walks these in order and
//      writes the result back to shell.json, so the label the bar shows and
//      the format the config stores are always the same thing.
//
// The locale-shaped time presets are each followed by their 12-hour twin, so
// the walk from a 24-hour label to the same label in AM/PM is a single right
// click rather than a lap of the ring. The ISO preset is deliberately left
// without one: ISO 8601 writes time on a 24-hour clock, so an AM/PM variant
// would contradict the only thing that format is for.
var CLOCK_FORMATS = [
  "'KW'ww · dddd, dd.MM.yyyy · HH:mm",
  "dddd h:mm AP",
  "HH:mm",
  "h:mm AP",
  "ddd d MMM HH:mm",
  "ddd d MMM h:mm AP",
  "d MMMM 'W'ww yyyy",
  "yyyy-MM-dd HH:mm"
]

// Vertical bars have room for a few stacked lines and nothing else, so the
// ring stays short. AM/PM costs a fourth line, which is why only the plain
// time carries it here.
var VERTICAL_CLOCK_FORMATS = [
  "HH\n—\nmm",
  "h\n—\nmm\nAP",
  "dd\nMMM\n'W'ww\n''yy",
  "HH\nmm"
]

function clockFormats(vertical) {
  return vertical ? VERTICAL_CLOCK_FORMATS.slice() : CLOCK_FORMATS.slice()
}

// The presets in a fixed order, plus the configured alternate and current
// format when they are something else. The order must not depend on which
// entry is current: cycling writes the result back to shell.json, and a ring
// that reshuffled itself around the current value would bounce between two
// entries instead of walking.
function clockFormatRing(configured, configuredAlt, presets) {
  var ring = []
  var candidates = (presets || []).concat([configuredAlt, configured])
  for (var i = 0; i < candidates.length; i++) {
    var format = String(candidates[i] === undefined || candidates[i] === null ? "" : candidates[i])
    if (format === "" || ring.indexOf(format) !== -1) continue
    ring.push(format)
  }
  return ring.length > 0 ? ring : ["HH:mm"]
}

// Next entry after `current`. An unknown current format (a hand-written one
// that is not in the ring) starts the walk at the top.
function nextClockFormat(ring, current) {
  if (!ring || ring.length === 0) return ""
  var index = ring.indexOf(String(current === undefined || current === null ? "" : current))
  return ring[(index + 1) % ring.length]
}

// Two-digit ISO week, substituted into a format's 'ww' token before Qt
// formats it -- Qt has no ISO week specifier of its own.
function isoWeekLiteral(year, month, day) {
  return pad2(isoWeek(year, month, day))
}

function pad2(value) {
  var n = Number(value)
  return (n < 10 ? "0" : "") + n
}

// Stable "yyyy-MM-dd" identity for a day, so a grid cell can be compared
// against today without dragging Date objects through bindings.
function dateKey(year, month, day) {
  return year + "-" + pad2(Number(month) + 1) + "-" + pad2(day)
}

function keyForDate(date) {
  return dateKey(date.getFullYear(), date.getMonth(), date.getDate())
}

function coerceWeekStart(value) {
  if (value === undefined || value === null) return null
  if (typeof value === "number")
    return isFinite(value) ? ((Math.round(value) % 7) + 7) % 7 : null

  var text = String(value).replace(/^\s+|\s+$/g, "").toLowerCase()
  if (text === "") return null

  for (var i = 0; i < WEEKDAY_NAMES.length; i++)
    if (WEEKDAY_NAMES[i] === text || WEEKDAY_NAMES[i].substr(0, 3) === text) return i

  var parsed = parseInt(text, 10)
  return isFinite(parsed) ? ((parsed % 7) + 7) % 7 : null
}

// Configured week start, falling back to the locale's own first day when
// the setting is missing or nonsense.
function normalizedWeekStart(value, fallback) {
  var configured = coerceWeekStart(value)
  if (configured !== null) return configured
  var fallbackStart = coerceWeekStart(fallback)
  return fallbackStart === null ? 1 : fallbackStart
}

function weekStartSettingName(index) {
  return WEEKDAY_NAMES[normalizedWeekStart(index, 1)]
}

// The toggle flips between the two conventions people actually switch
// between. A calendar configured to any other start (Saturday, say) is
// shown as-is and lands on Monday the first time it is toggled.
function toggledWeekStart(index) {
  return normalizedWeekStart(index, 1) === 1 ? 0 : 1
}

function weekdayOrder(weekStart) {
  var start = normalizedWeekStart(weekStart, 1)
  var out = []
  for (var i = 0; i < 7; i++) out.push((start + i) % 7)
  return out
}

// ISO-8601 week number: the week owning the Thursday of that date's
// Monday-based week. Mirrors the clock widget's 'ww' format token.
function isoWeek(year, month, day) {
  var date = new Date(Date.UTC(year, month, day))
  var weekday = date.getUTCDay() || 7
  date.setUTCDate(date.getUTCDate() + 4 - weekday)
  var yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
  return Math.ceil(((date.getTime() - yearStart.getTime()) / MS_PER_DAY + 1) / 7)
}

function dayOfYear(year, month, day) {
  return Math.round((Date.UTC(year, month, day) - Date.UTC(year, 0, 1)) / MS_PER_DAY) + 1
}

function daysInYear(year) {
  return dayOfYear(year, 11, 31)
}

// Share of the year already behind you: whole days completed over days in
// the year, so January 1 reads 0% and December 31 reads 100%.
function yearProgress(year, month, day) {
  var total = daysInYear(year)
  if (total <= 0) return 0
  return Math.max(0, Math.min(1, (dayOfYear(year, month, day) - 1) / total))
}

function yearProgressPercent(year, month, day) {
  return Math.round(yearProgress(year, month, day) * 100)
}

// Memento mori. The default span is a round number rather than anything from
// an actuarial table: the point of the bar is the reminder, not the
// arithmetic, and whoever wants a different number can say so.
var DEFAULT_LIFE_EXPECTANCY = 90

// A birth year rather than an age, so the bar keeps counting on its own
// instead of going stale the moment it is entered. 0 means "not set", which
// is also what a blank, malformed, future, or implausibly distant year means.
function parseBirthYear(value, currentYear) {
  var now = Math.round(Number(currentYear))
  if (!isFinite(now)) return 0
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d{4}$/.test(text)) return 0
  var year = parseInt(text, 10)
  if (!isFinite(year) || year > now || year < now - 120) return 0
  return year
}

// Whole years, the way people say their age: born in 1979 makes you 47 for
// all of 2026, whichever side of your birthday today falls.
function ageFromBirthYear(birthYear, currentYear) {
  var born = parseBirthYear(birthYear, currentYear)
  if (born <= 0) return 0
  return Math.round(Number(currentYear)) - born
}

// 0 means "not set", which is also what a blank, negative, fractional, or
// absurd entry means — the life bar simply stays hidden.
function parseAge(value) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d+$/.test(text)) return 0
  var years = parseInt(text, 10)
  if (!isFinite(years) || years <= 0 || years > 120) return 0
  return years
}

// Unset or nonsense falls back to the default rather than to zero, so the
// bar always has something to measure against.
function parseLifeExpectancy(value) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d+$/.test(text)) return DEFAULT_LIFE_EXPECTANCY
  var years = parseInt(text, 10)
  if (!isFinite(years) || years <= 0 || years > 150) return DEFAULT_LIFE_EXPECTANCY
  return years
}

function lifeProgress(age, expectancy) {
  var years = parseAge(age)
  var span = parseLifeExpectancy(expectancy)
  if (years <= 0 || span <= 0) return 0
  return Math.max(0, Math.min(1, years / span))
}

function lifeProgressPercent(age, expectancy) {
  return Math.round(lifeProgress(age, expectancy) * 100)
}

function utcCalendarDate(year, month, day) {
  var date = new Date(0)
  date.setUTCHours(0, 0, 0, 0)
  date.setUTCFullYear(Number(year), Number(month), Number(day))
  return date
}

function keyForUtcDate(date) {
  return dateKey(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate())
}

function dateOnlyValue(value) {
  var match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(value || ""))
  if (!match) return null

  var year = Number(match[1])
  var month = Number(match[2]) - 1
  var day = Number(match[3])
  var date = utcCalendarDate(year, month, day)
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month || date.getUTCDate() !== day) return null
  return date
}

// The date-only bounds of the fixed calendar grid. `end` is exclusive, which
// matches Google Calendar's timeMax and all-day end-date conventions.
function visibleGridRange(year, month, weekStart) {
  var first = utcCalendarDate(year, month, 1)
  var start = normalizedWeekStart(weekStart, 1)
  var leading = (first.getUTCDay() - start + 7) % 7
  first.setUTCDate(first.getUTCDate() - leading)

  var end = utcCalendarDate(first.getUTCFullYear(), first.getUTCMonth(), first.getUTCDate() + 42)
  return { start: keyForUtcDate(first), end: keyForUtcDate(end) }
}

function copyEvent(event) {
  return {
    id: event.id,
    summary: event.summary,
    allDay: event.allDay === true,
    start: event.start,
    end: event.end,
    eventType: event.eventType,
    transparency: event.transparency
  }
}

function addEventToDay(index, key, event) {
  if (!index[key]) index[key] = []
  index[key].push(event)
}

function eventIndexRange(range) {
  if (!range || typeof range !== "object") return null
  var start = dateOnlyValue(range.start)
  var end = dateOnlyValue(range.end)
  if (!start || !end || start.getTime() >= end.getTime()) return null
  return { start: start, end: end }
}

function indexAllDayEvent(index, event, range) {
  var cursor = dateOnlyValue(event.start)
  var end = dateOnlyValue(event.end)
  if (!cursor || !end || cursor.getTime() >= end.getTime()) return
  if (range) {
    if (cursor.getTime() < range.start.getTime())
      cursor = new Date(range.start.getTime())
    if (end.getTime() > range.end.getTime())
      end = new Date(range.end.getTime())
  }

  var days = 0
  while (cursor.getTime() < end.getTime() && days < 370) {
    addEventToDay(index, keyForUtcDate(cursor), event)
    cursor.setUTCDate(cursor.getUTCDate() + 1)
    days++
  }
}

function localDateFromKey(key) {
  var value = dateOnlyValue(key)
  return value ? new Date(value.getUTCFullYear(), value.getUTCMonth(), value.getUTCDate(), 12) : null
}

function indexTimedEvent(index, event, range) {
  var start = new Date(event.start)
  var end = new Date(event.end)
  if (!isFinite(start.getTime()) || !isFinite(end.getTime()) || start.getTime() >= end.getTime()) return

  // End instants are exclusive. Subtracting one millisecond keeps an event
  // ending at local midnight off the following day.
  var last = new Date(end.getTime() - 1)
  var firstKey = keyForDate(start)
  var lastKey = keyForDate(last)
  if (range) {
    var rangeStartKey = keyForUtcDate(range.start)
    var rangeLast = new Date(range.end.getTime())
    rangeLast.setUTCDate(rangeLast.getUTCDate() - 1)
    var rangeLastKey = keyForUtcDate(rangeLast)
    if (firstKey < rangeStartKey) firstKey = rangeStartKey
    if (lastKey > rangeLastKey) lastKey = rangeLastKey
  }
  if (firstKey > lastKey) return

  var cursor = localDateFromKey(firstKey)
  var days = 0
  while (cursor && days < 370) {
    var key = keyForDate(cursor)
    addEventToDay(index, key, event)
    if (key === lastKey) return
    cursor.setDate(cursor.getDate() + 1)
    days++
  }
}

// Build local-day buckets without changing the source array or its events.
// All-day dates stay date-only; JS Date converts timed instants to desktop time.
// An optional visible range bounds pathological multi-year events.
function indexEventsByDay(events, visibleRange) {
  var index = {}
  var source = Array.isArray(events) ? events : []
  var range = eventIndexRange(visibleRange)

  for (var i = 0; i < source.length; i++) {
    if (!source[i] || typeof source[i] !== "object") continue
    var event = copyEvent(source[i])
    if (event.allDay) indexAllDayEvent(index, event, range)
    else indexTimedEvent(index, event, range)
  }
  return index
}

function eventsForDay(index, dayKey) {
  if (!index || !Array.isArray(index[dayKey])) return []
  return index[dayKey].slice()
}

function eventDotSummary(index, dayKey) {
  var total = eventsForDay(index, dayKey).length
  return { count: Math.min(3, total), total: total }
}

function dateValue(value) {
  var date = value instanceof Date ? new Date(value.getTime()) : new Date(value)
  return isFinite(date.getTime()) ? date : null
}

// Past timed entries disappear from today's bar. All-day, ongoing, and future
// entries remain, and browsing another date never applies the current time.
function filterPastEventsForToday(events, dayKey, now) {
  var source = Array.isArray(events) ? events : []
  var current = dateValue(now)
  if (!current || String(dayKey) !== keyForDate(current)) return source.slice()

  return source.filter(function(event) {
    if (event.allDay === true) return true
    var end = dateValue(event.end)
    return end !== null && end.getTime() > current.getTime()
  })
}

function compareValues(left, right) {
  if (left < right) return -1
  if (left > right) return 1
  return 0
}

function eventStartValue(event) {
  if (event.allDay === true) return String(event.start || "")
  var start = dateValue(event.start)
  return start ? start.getTime() : Infinity
}

function eventTieBreak(left, right) {
  var byStart = compareValues(eventStartValue(left), eventStartValue(right))
  if (byStart !== 0) return byStart
  var bySummary = compareValues(String(left.summary || ""), String(right.summary || ""))
  return bySummary !== 0 ? bySummary : compareValues(String(left.id || ""), String(right.id || ""))
}

function todayEventGroup(event, now) {
  if (event.allDay === true) return 1
  var start = dateValue(event.start)
  var end = dateValue(event.end)
  if (start && end && start.getTime() <= now.getTime() && end.getTime() > now.getTime()) return 0
  if (start && start.getTime() > now.getTime()) return 2
  return 3
}

function sortEventsForDay(events, dayKey, now) {
  var sorted = Array.isArray(events) ? events.slice() : []
  var current = dateValue(now)
  var today = current !== null && String(dayKey) === keyForDate(current)

  sorted.sort(function(left, right) {
    if (today) {
      var byGroup = todayEventGroup(left, current) - todayEventGroup(right, current)
      if (byGroup !== 0) return byGroup
    } else {
      var byAllDay = (left.allDay === true ? 0 : 1) - (right.allDay === true ? 0 : 1)
      if (byAllDay !== 0) return byAllDay
    }
    return eventTieBreak(left, right)
  })
  return sorted
}

function barEventsForDay(index, dayKey, now) {
  var events = eventsForDay(index, dayKey)
  return sortEventsForDay(filterPastEventsForToday(events, dayKey, now), dayKey, now)
}

// Always six rows of seven days. A fixed grid keeps the popup exactly the
// same height in every month, so stepping through the year never makes the
// panel jump under the pointer.
function monthGrid(year, month, weekStart, todayKey) {
  var start = normalizedWeekStart(weekStart, 1)
  var leading = (new Date(year, month, 1).getDay() - start + 7) % 7
  var cursor = new Date(year, month, 1 - leading)
  var today = String(todayKey || "")
  var weeks = []

  for (var w = 0; w < 6; w++) {
    var days = []
    var thursday = null
    for (var d = 0; d < 7; d++) {
      var cellYear = cursor.getFullYear()
      var cellMonth = cursor.getMonth()
      var cellDay = cursor.getDate()
      var weekday = cursor.getDay()
      var key = dateKey(cellYear, cellMonth, cellDay)
      if (weekday === 4) thursday = { year: cellYear, month: cellMonth, day: cellDay }
      days.push({
        key: key,
        year: cellYear,
        month: cellMonth,
        day: cellDay,
        weekday: weekday,
        inMonth: cellMonth === month && cellYear === year,
        weekend: weekday === 0 || weekday === 6,
        today: key === today
      })
      cursor.setDate(cursor.getDate() + 1)
    }
    // Number every row by the ISO week owning its Thursday. That is the
    // definition itself for Monday-start weeks, and the only answer that
    // stays stable for the other starts, where a row straddles two ISO
    // weeks but shares all of Monday through Thursday with one of them.
    var anchor = thursday || days[0]
    weeks.push({
      week: isoWeek(anchor.year, anchor.month, anchor.day),
      days: days
    })
  }
  return weeks
}

function stepDay(year, month, day, delta) {
  var target = utcCalendarDate(year, month, Number(day) + Number(delta))
  return {
    year: target.getUTCFullYear(),
    month: target.getUTCMonth(),
    day: target.getUTCDate()
  }
}

// ---- Media sources -----------------------------------------------------
// The MPRIS service hands out a list of players; the hub has to label each
// one and step through them. Both are plain string and index work, so they
// live here instead of in the QML.

// Stable carousel order. The service sorts playing sources to the front, so
// pausing one moves it and shifts every index behind it. Ordering by player
// key instead keeps each source in the slot it had, for as long as it exists.
function orderedMediaSources(players, keyOf) {
  var list = []
  if (!players) return list

  for (var i = 0; i < players.length; i++) {
    if (players[i]) list.push(players[i])
  }

  if (typeof keyOf !== "function") return list

  return list.sort(function(a, b) {
    var left = String(keyOf(a) || "")
    var right = String(keyOf(b) || "")
    return left < right ? -1 : (left > right ? 1 : 0)
  })
}

function mediaSourceApp(player) {
  if (!player) return ""

  var entry = String(player.desktopEntry || "").replace(/\.desktop$/, "").trim()
  if (entry !== "") return entry

  return String(player.dbusName || "")
    .replace(/^org\.mpris\.MediaPlayer2\./, "")
    .replace(/\.instance[0-9]+$/, "")
    .trim()
}

function mediaSourceLabel(player) {
  if (!player) return ""

  var title = String(player.trackTitle || "").trim()
  if (title !== "") return title

  var identity = String(player.identity || "").trim()
  if (identity !== "") return identity

  return mediaSourceApp(player)
}

// Second line of a source card. Never repeats the label, so a player that is
// only known by its app name gets no detail at all.
function mediaSourceDetail(player) {
  if (!player) return ""

  var artist = String(player.trackArtist || "").trim()
  if (artist !== "") return artist

  var app = mediaSourceApp(player)
  if (app === "") return ""

  return app.toLowerCase() === mediaSourceLabel(player).toLowerCase() ? "" : app
}

function mediaTimeLabel(seconds) {
  var value = Math.max(0, Math.floor(Number(seconds) || 0))
  var minutes = Math.floor(value / 60)
  var rest = value % 60
  return minutes + ":" + (rest < 10 ? "0" : "") + rest
}

// Wrapping step through a list. Returns -1 for an empty list so callers can
// tell "nothing to focus" from "focus the first entry".
function cycleIndex(index, delta, length) {
  var total = Math.max(0, Math.floor(Number(length) || 0))
  if (total === 0) return -1

  var start = Math.floor(Number(index) || 0)
  if (!isFinite(start) || start < 0) start = 0

  var step = Math.floor(Number(delta) || 0)
  return (((start + step) % total) + total) % total
}

function stepMonth(year, month, delta) {
  var target = new Date(year, Number(month) + Number(delta), 1)
  return { year: target.getFullYear(), month: target.getMonth() }
}

if (typeof module !== "undefined") {
  module.exports = {
    dateKey: dateKey,
    keyForDate: keyForDate,
    normalizedWeekStart: normalizedWeekStart,
    weekStartSettingName: weekStartSettingName,
    toggledWeekStart: toggledWeekStart,
    weekdayOrder: weekdayOrder,
    isoWeek: isoWeek,
    dayOfYear: dayOfYear,
    daysInYear: daysInYear,
    yearProgress: yearProgress,
    yearProgressPercent: yearProgressPercent,
    parseAge: parseAge,
    parseBirthYear: parseBirthYear,
    ageFromBirthYear: ageFromBirthYear,
    parseLifeExpectancy: parseLifeExpectancy,
    lifeProgress: lifeProgress,
    lifeProgressPercent: lifeProgressPercent,
    visibleGridRange: visibleGridRange,
    indexEventsByDay: indexEventsByDay,
    eventsForDay: eventsForDay,
    eventDotSummary: eventDotSummary,
    filterPastEventsForToday: filterPastEventsForToday,
    sortEventsForDay: sortEventsForDay,
    barEventsForDay: barEventsForDay,
    monthGrid: monthGrid,
    stepDay: stepDay,
    stepMonth: stepMonth,
    clockFormats: clockFormats,
    clockFormatRing: clockFormatRing,
    nextClockFormat: nextClockFormat,
    isoWeekLiteral: isoWeekLiteral,
    orderedMediaSources: orderedMediaSources,
    mediaSourceApp: mediaSourceApp,
    mediaSourceLabel: mediaSourceLabel,
    mediaSourceDetail: mediaSourceDetail,
    mediaTimeLabel: mediaTimeLabel,
    cycleIndex: cycleIndex
  }
}
