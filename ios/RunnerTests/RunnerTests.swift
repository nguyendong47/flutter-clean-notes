import Flutter
import UIKit
import XCTest
import SQLite3
@testable import Runner

class RunnerTests: XCTestCase {

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
  }

  func testToggleChecklistItemIntentEndToEnd() async throws {
    guard #available(iOS 17, *) else { return }

    // 1. Locate documents directory and notes_database.db
    let fileManager = FileManager.default
    let docsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    let dbUrl = docsUrl.appendingPathComponent("notes_database.db")

    // 2. Open or create database and seed note ID 1
    var db: OpaquePointer?
    guard sqlite3_open(dbUrl.path, &db) == SQLITE_OK else {
      XCTFail("Failed to open sqlite db at \(dbUrl.path)")
      return
    }
    defer { sqlite3_close(db) }

    let createTableSql = """
    CREATE TABLE IF NOT EXISTS notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      content TEXT NOT NULL,
      color INTEGER NOT NULL,
      createdAt TEXT NOT NULL,
      isPinned INTEGER NOT NULL DEFAULT 0,
      tags TEXT NOT NULL DEFAULT '',
      status INTEGER NOT NULL DEFAULT 0,
      reminder TEXT,
      reminderGeneration INTEGER NOT NULL DEFAULT 0
    );
    """
    sqlite3_exec(db, createTableSql, nil, nil, nil)

    let initialContent = "- [ ] Buy groceries\n- [ ] Walk the dog"
    let insertSql = """
    INSERT OR REPLACE INTO notes (id, title, content, color, createdAt, isPinned, tags, status, reminder, reminderGeneration)
    VALUES (1, 'Test Note', '\(initialContent)', 4284976729, '2026-09-26T10:00:00.000Z', 1, '', 0, NULL, 0);
    """
    guard sqlite3_exec(db, insertSql, nil, nil, nil) == SQLITE_OK else {
      XCTFail("Failed to insert test note into SQLite")
      return
    }

    // 3. Seed UserDefaults for app group
    let appGroup = "group.com.cleannotes.app"
    let userDefaults = UserDefaults(suiteName: appGroup)!
    let initialChecklistJson = """
    [{"text":"Buy groceries","done":false},{"text":"Walk the dog","done":false}]
    """
    userDefaults.set(true, forKey: "widget_has_pinned")
    userDefaults.set("1", forKey: "widget_pinned_id")
    userDefaults.set("Test Note", forKey: "widget_pinned_title")
    userDefaults.set(initialChecklistJson, forKey: "widget_pinned_checklist")
    userDefaults.set(initialChecklistJson, forKey: "widget_note_1_checklist")

    // 4. Perform ToggleChecklistItemIntent for item 0
    let intent = ToggleChecklistItemIntent(noteId: "1", index: 0)
    _ = try await intent.perform()

    // 5. Verify (a): Instant optimistic UserDefaults update
    let updatedJson = userDefaults.string(forKey: "widget_pinned_checklist") ?? ""
    XCTAssertTrue(
      updatedJson.contains("\"done\":true") || updatedJson.contains("\"done\":1"),
      "UserDefaults checklist JSON must reflect done: true, got: \(updatedJson)"
    )

    // 6. Verify (b): Background isolate persisted update to SQLite
    var persistedContent: String?
    let deadline = Date().addingTimeInterval(12.0)
    while Date() < deadline {
      var stmt: OpaquePointer?
      if sqlite3_prepare_v2(db, "SELECT content FROM notes WHERE id = 1;", -1, &stmt, nil) == SQLITE_OK {
        if sqlite3_step(stmt) == SQLITE_ROW {
          if let cStr = sqlite3_column_text(stmt, 0) {
            persistedContent = String(cString: cStr)
          }
        }
        sqlite3_finalize(stmt)
      }
      if let content = persistedContent, content.contains("- [x] Buy groceries") {
        break
      }
      try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
    }

    XCTAssertNotNil(persistedContent, "SQLite note row must exist")
    XCTAssertTrue(
      persistedContent?.contains("- [x] Buy groceries") == true,
      "SQLite note content must be updated to '- [x] Buy groceries' by Dart background worker, but was: \(persistedContent ?? "nil")"
    )
  }

}
