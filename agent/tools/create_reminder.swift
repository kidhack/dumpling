#!/usr/bin/env swift
/// Dumpling — create a reminder via EventKit.
/// Usage: create_reminder --title "..." --notes "..." --due "2026-05-03" --list "Now" --tag "music"

import EventKit
import Foundation

// ── Argument parsing ──────────────────────────────────────────────────────────

var title = "Reminder"
var notes: String? = nil
var dueString: String? = nil
var listName = "Now"
var tag: String? = nil

var args = CommandLine.arguments.dropFirst()
while !args.isEmpty {
    let flag = args.removeFirst()
    guard let value = args.first else { break }
    args.removeFirst()
    switch flag {
    case "--title": title = value
    case "--notes": notes = value
    case "--due":   dueString = value
    case "--list":  listName = value
    case "--tag":   tag = value
    default: break
    }
}

// ── Create reminder ───────────────────────────────────────────────────────────

let store = EKEventStore()
let sem = DispatchSemaphore(value: 0)

store.requestFullAccessToReminders { granted, error in
    guard granted else {
        fputs("ERROR: Reminders access denied — \(error?.localizedDescription ?? "unknown")\n", stderr)
        sem.signal()
        return
    }

    let reminder = EKReminder(eventStore: store)
    reminder.title = title

    // Append tag as hashtag — Reminders auto-converts #tagname to a real tag
    var notesWithTag = notes ?? ""
    if let t = tag {
        let hashtag = "#\(t.replacingOccurrences(of: " ", with: "-"))"
        notesWithTag = notesWithTag.isEmpty ? hashtag : "\(notesWithTag)\n\(hashtag)"
    }
    if !notesWithTag.isEmpty { reminder.notes = notesWithTag }

    // Due date
    if let d = dueString {
        let fmts = ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for fmt in fmts {
            df.dateFormat = fmt
            if let date = df.date(from: d) {
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
                reminder.dueDateComponents = comps
                break
            }
        }
    }

    // List
    let lists = store.calendars(for: .reminder)
    reminder.calendar = lists.first(where: { $0.title == listName })
        ?? store.defaultCalendarForNewReminders()

    do {
        try store.save(reminder, commit: true)
        print("SUCCESS: \(reminder.title ?? "")")
    } catch {
        fputs("ERROR: \(error.localizedDescription)\n", stderr)
    }
    sem.signal()
}
sem.wait()
