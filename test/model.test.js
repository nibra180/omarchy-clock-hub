const test = require("node:test")
const assert = require("node:assert/strict")

const Model = require("../Model.js")

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
