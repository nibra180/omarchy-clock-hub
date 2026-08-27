const test = require("node:test")
const assert = require("node:assert/strict")

process.env.TZ = "America/New_York"

const Model = require("../Model.js")

function calendarEvent(overrides) {
  return Object.assign({
    id: "event",
    summary: "Event",
    allDay: false,
    start: "2026-02-14T10:00:00-05:00",
    end: "2026-02-14T11:00:00-05:00",
    eventType: "default",
    transparency: "opaque"
  }, overrides)
}

test("clockFormats returns independent horizontal and vertical preset lists", () => {
  const horizontal = Model.clockFormats(false)
  const vertical = Model.clockFormats(true)

  assert.equal(horizontal[0], "'KW'ww · dddd, dd.MM.yyyy · HH:mm")
  assert.equal(vertical[0], "HH\n—\nmm")

  horizontal.shift()
  vertical.shift()

  assert.equal(Model.clockFormats(false).length, 8)
  assert.equal(Model.clockFormats(true).length, 4)
})

test("clockFormatRing keeps order, removes blanks, and deduplicates values", () => {
  assert.deepEqual(
    Model.clockFormatRing("custom", "HH:mm", ["HH:mm", "", "custom", "yyyy-MM-dd"]),
    ["HH:mm", "custom", "yyyy-MM-dd"]
  )
  assert.deepEqual(Model.clockFormatRing(null, undefined, []), ["HH:mm"])
})

test("nextClockFormat advances, wraps, and handles unknown values", () => {
  const ring = ["one", "two", "three"]

  assert.equal(Model.nextClockFormat(ring, "one"), "two")
  assert.equal(Model.nextClockFormat(ring, "three"), "one")
  assert.equal(Model.nextClockFormat(ring, "missing"), "one")
  assert.equal(Model.nextClockFormat([], "one"), "")
})

test("date keys use a stable local calendar identity", () => {
  assert.equal(Model.dateKey(2026, 0, 7), "2026-01-07")
  assert.equal(Model.keyForDate(new Date(2026, 10, 9, 23, 45)), "2026-11-09")
})

test("week starts accept names, abbreviations, and wrapped numbers", () => {
  assert.equal(Model.normalizedWeekStart("monday", 0), 1)
  assert.equal(Model.normalizedWeekStart(" Thu ", 0), 4)
  assert.equal(Model.normalizedWeekStart(-1, 0), 6)
  assert.equal(Model.normalizedWeekStart("8", 0), 1)
  assert.equal(Model.normalizedWeekStart("nonsense", "sunday"), 0)
  assert.equal(Model.normalizedWeekStart(null, null), 1)
})

test("week start settings and toggles use the supported names", () => {
  assert.equal(Model.weekStartSettingName(0), "sunday")
  assert.equal(Model.weekStartSettingName(1), "monday")
  assert.equal(Model.toggledWeekStart(1), 0)
  assert.equal(Model.toggledWeekStart(0), 1)
  assert.equal(Model.toggledWeekStart(6), 1)
  assert.deepEqual(Model.weekdayOrder(6), [6, 0, 1, 2, 3, 4, 5])
})

test("ISO week numbers cover year boundaries and week 53", () => {
  assert.equal(Model.isoWeek(2021, 0, 1), 53)
  assert.equal(Model.isoWeek(2021, 0, 4), 1)
  assert.equal(Model.isoWeek(2026, 11, 31), 53)
  assert.equal(Model.isoWeekLiteral(2026, 0, 1), "01")
})

test("day and year progress account for leap years", () => {
  assert.equal(Model.dayOfYear(2024, 1, 29), 60)
  assert.equal(Model.daysInYear(2024), 366)
  assert.equal(Model.daysInYear(2025), 365)
  assert.equal(Model.yearProgress(2025, 0, 1), 0)
  assert.equal(Model.yearProgressPercent(2025, 11, 31), 100)
})

test("birth years reject malformed, future, and implausible values", () => {
  assert.equal(Model.parseBirthYear(" 1988 ", 2026), 1988)
  assert.equal(Model.parseBirthYear("88", 2026), 0)
  assert.equal(Model.parseBirthYear(2027, 2026), 0)
  assert.equal(Model.parseBirthYear(1905, 2026), 0)
  assert.equal(Model.parseBirthYear(1906, 2026), 1906)
  assert.equal(Model.parseBirthYear(1988, "unknown"), 0)
})

test("age and life progress normalize invalid settings", () => {
  assert.equal(Model.ageFromBirthYear(1988, 2026), 38)
  assert.equal(Model.ageFromBirthYear(0, 2026), 0)
  assert.equal(Model.parseAge(" 38 "), 38)
  assert.equal(Model.parseAge("38.5"), 0)
  assert.equal(Model.parseAge(121), 0)
  assert.equal(Model.parseLifeExpectancy(85), 85)
  assert.equal(Model.parseLifeExpectancy("unknown"), 90)
  assert.equal(Model.lifeProgress(45, 90), 0.5)
  assert.equal(Model.lifeProgress(100, 80), 1)
  assert.equal(Model.lifeProgressPercent(45, 90), 50)
})

test("visibleGridRange returns exclusive bounds for all 42 visible days", () => {
  assert.deepEqual(Model.visibleGridRange(2026, 1, 1), {
    start: "2026-01-26",
    end: "2026-03-09"
  })
  assert.deepEqual(Model.visibleGridRange(2026, 1, 0), {
    start: "2026-02-01",
    end: "2026-03-15"
  })
  assert.deepEqual(Model.visibleGridRange(2026, 11, "monday"), {
    start: "2026-11-30",
    end: "2027-01-11"
  })
})

test("all-day events are indexed through their exclusive end date", () => {
  const events = [calendarEvent({
    id: "new-year",
    summary: "New year break",
    allDay: true,
    start: "2026-12-31",
    end: "2027-01-03"
  })]
  const original = JSON.parse(JSON.stringify(events))
  const index = Model.indexEventsByDay(events)

  assert.deepEqual(Object.keys(index), ["2026-12-31", "2027-01-01", "2027-01-02"])
  assert.equal(index["2027-01-03"], undefined)
  assert.deepEqual(index["2027-01-01"][0], events[0])
  assert.notEqual(index["2027-01-01"][0], events[0])
  assert.deepEqual(events, original)
})

test("invalid and empty event intervals are not indexed", () => {
  const index = Model.indexEventsByDay([
    calendarEvent({ id: "bad-date", allDay: true, start: "2026-02-30", end: "2026-03-02" }),
    calendarEvent({ id: "empty-day", allDay: true, start: "2026-02-14", end: "2026-02-14" }),
    calendarEvent({ id: "bad-time", start: "not-a-date", end: "2026-02-14T11:00:00-05:00" }),
    calendarEvent({ id: "empty-time", start: "2026-02-14T11:00:00-05:00", end: "2026-02-14T11:00:00-05:00" })
  ])

  assert.deepEqual(index, {})
})

test("timed events use desktop-local days and exclusive end instants", () => {
  const index = Model.indexEventsByDay([
    calendarEvent({
      id: "utc-evening",
      start: "2026-02-01T01:00:00Z",
      end: "2026-02-01T03:00:00Z"
    }),
    calendarEvent({
      id: "to-midnight",
      start: "2026-01-31T23:00:00-05:00",
      end: "2026-02-01T00:00:00-05:00"
    }),
    calendarEvent({
      id: "overnight",
      start: "2026-01-31T23:30:00-05:00",
      end: "2026-02-01T01:15:00-05:00"
    })
  ])

  assert.deepEqual(index["2026-01-31"].map((event) => event.id), [
    "utc-evening",
    "to-midnight",
    "overnight"
  ])
  assert.deepEqual(index["2026-02-01"].map((event) => event.id), ["overnight"])
})

test("local-day indexing crosses the spring DST change without losing a day", () => {
  assert.equal(new Date("2026-03-07T12:00:00").getTimezoneOffset(), 300)
  assert.equal(new Date("2026-03-08T12:00:00").getTimezoneOffset(), 240)

  const index = Model.indexEventsByDay([
    calendarEvent({
      id: "dst-all-day",
      allDay: true,
      start: "2026-03-07",
      end: "2026-03-10"
    }),
    calendarEvent({
      id: "dst-timed",
      start: "2026-03-07T23:30:00-05:00",
      end: "2026-03-09T00:30:00-04:00"
    })
  ])

  assert.deepEqual(Object.keys(index), ["2026-03-07", "2026-03-08", "2026-03-09"])
  assert.deepEqual(index["2026-03-07"].map((event) => event.id), ["dst-all-day", "dst-timed"])
  assert.deepEqual(index["2026-03-08"].map((event) => event.id), ["dst-all-day", "dst-timed"])
  assert.deepEqual(index["2026-03-09"].map((event) => event.id), ["dst-all-day", "dst-timed"])
})

test("event indexing is bounded to the requested visible range", () => {
  const event = {
    id: "long",
    summary: "Long event",
    allDay: true,
    start: "2000-01-01",
    end: "2100-01-01",
  }

  const index = Model.indexEventsByDay([event], {
    start: "2026-08-24",
    end: "2026-10-05",
  })

  assert.equal(Object.keys(index).length, 42)
  assert.equal(index["2026-08-24"][0].id, "long")
  assert.equal(index["2026-10-04"][0].id, "long")
  assert.equal(index["2026-10-05"], undefined)
})

test("eventsForDay returns an independent list and dot counts retain totals", () => {
  const events = []
  for (let i = 0; i < 5; i++) {
    events.push(calendarEvent({
      id: `all-day-${i}`,
      allDay: true,
      start: "2026-02-14",
      end: "2026-02-15"
    }))
  }
  const index = Model.indexEventsByDay(events)
  const selected = Model.eventsForDay(index, "2026-02-14")

  selected.pop()
  assert.equal(Model.eventsForDay(index, "2026-02-14").length, 5)
  assert.deepEqual(Model.eventDotSummary(index, "2026-02-14"), { count: 3, total: 5 })
  assert.deepEqual(Model.eventDotSummary(index, "2026-02-15"), { count: 0, total: 0 })
})

test("today's bar drops past timed events but keeps ongoing, future, and all-day events", () => {
  const now = new Date("2026-02-14T10:00:00-05:00")
  const events = [
    calendarEvent({ id: "past", start: "2026-02-14T08:00:00-05:00", end: "2026-02-14T09:00:00-05:00" }),
    calendarEvent({ id: "ends-now", start: "2026-02-14T09:00:00-05:00", end: "2026-02-14T10:00:00-05:00" }),
    calendarEvent({ id: "ongoing", start: "2026-02-14T09:30:00-05:00", end: "2026-02-14T10:30:00-05:00" }),
    calendarEvent({ id: "future", start: "2026-02-14T11:00:00-05:00", end: "2026-02-14T12:00:00-05:00" }),
    calendarEvent({ id: "all-day", allDay: true, start: "2026-02-14", end: "2026-02-15" })
  ]

  assert.deepEqual(
    Model.filterPastEventsForToday(events, "2026-02-14", now).map((event) => event.id),
    ["ongoing", "future", "all-day"]
  )
  assert.deepEqual(
    Model.filterPastEventsForToday(events, "2026-02-15", now).map((event) => event.id),
    ["past", "ends-now", "ongoing", "future", "all-day"]
  )
})

test("today's bar sorts ongoing events before all-day and upcoming events", () => {
  const now = new Date("2026-02-14T10:00:00-05:00")
  const events = [
    calendarEvent({ id: "future-late", start: "2026-02-14T12:00:00-05:00", end: "2026-02-14T13:00:00-05:00" }),
    calendarEvent({ id: "all-day", allDay: true, start: "2026-02-14", end: "2026-02-15" }),
    calendarEvent({ id: "ongoing-late", start: "2026-02-14T09:30:00-05:00", end: "2026-02-14T10:30:00-05:00" }),
    calendarEvent({ id: "past", start: "2026-02-14T07:00:00-05:00", end: "2026-02-14T08:00:00-05:00" }),
    calendarEvent({ id: "future-early", start: "2026-02-14T10:15:00-05:00", end: "2026-02-14T11:00:00-05:00" }),
    calendarEvent({ id: "ongoing-early", start: "2026-02-13T18:00:00-05:00", end: "2026-02-14T10:45:00-05:00" })
  ]
  const sourceOrder = events.map((event) => event.id)
  const index = Model.indexEventsByDay(events)

  assert.deepEqual(Model.barEventsForDay(index, "2026-02-14", now).map((event) => event.id), [
    "ongoing-early",
    "ongoing-late",
    "all-day",
    "future-early",
    "future-late"
  ])
  assert.deepEqual(events.map((event) => event.id), sourceOrder)
})

test("other dates sort all-day events first and timed events by start", () => {
  const events = [
    calendarEvent({ id: "timed-late", start: "2026-02-15T15:00:00-05:00", end: "2026-02-15T16:00:00-05:00" }),
    calendarEvent({ id: "all-day-late", allDay: true, start: "2026-02-15", end: "2026-02-16" }),
    calendarEvent({ id: "timed-early", start: "2026-02-15T09:00:00-05:00", end: "2026-02-15T10:00:00-05:00" }),
    calendarEvent({ id: "all-day-early", allDay: true, start: "2026-02-14", end: "2026-02-16" })
  ]

  assert.deepEqual(
    Model.sortEventsForDay(events, "2026-02-15", new Date("2026-02-14T10:00:00-05:00")).map((event) => event.id),
    ["all-day-early", "all-day-late", "timed-early", "timed-late"]
  )
})

test("monthGrid always returns six complete weeks", () => {
  const weeks = Model.monthGrid(2026, 1, 1, "2026-02-14")

  assert.equal(weeks.length, 6)
  assert.ok(weeks.every((week) => week.days.length === 7))
  assert.equal(weeks[0].days[0].key, "2026-01-26")
  assert.equal(weeks[5].days[6].key, "2026-03-08")
  assert.equal(weeks.flatMap((week) => week.days).filter((day) => day.inMonth).length, 28)
  assert.equal(weeks.flatMap((week) => week.days).filter((day) => day.today).length, 1)
})

test("monthGrid respects Sunday starts and marks weekends", () => {
  const weeks = Model.monthGrid(2026, 1, 0, "")
  const firstWeek = weeks[0]

  assert.equal(firstWeek.days[0].key, "2026-02-01")
  assert.equal(firstWeek.days[0].weekend, true)
  assert.equal(firstWeek.days[6].weekend, true)
  assert.equal(firstWeek.days[1].weekend, false)
  assert.equal(firstWeek.week, 6)
})

test("stepMonth crosses year boundaries in both directions", () => {
  assert.deepEqual(Model.stepMonth(2026, 11, 1), { year: 2027, month: 0 })
  assert.deepEqual(Model.stepMonth(2026, 0, -1), { year: 2025, month: 11 })
  assert.deepEqual(Model.stepMonth(2026, 5, 18), { year: 2027, month: 11 })
})
