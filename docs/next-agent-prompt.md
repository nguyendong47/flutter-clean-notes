# Prompt bàn giao cho AI agent tiếp theo

Bạn đang tiếp quản dự án Flutter tại:

```text
H:\source\flutter-clean-notes
```

## Mục tiêu

Hoàn tất kiểm chứng và phát hành nội bộ cho redesign **Aurora Glass** của ứng
dụng Clean Notes. Không mở rộng phạm vi, không push remote, và không làm mất
thay đổi của người dùng.

## Trạng thái Git hiện tại

- Nhánh hiện tại: `main`
- HEAD: `39e0a77` (`docs: record post-merge verification`)
- `feat/aurora-glass-redesign` đã được fast-forward vào `main` và đã bị xóa.
- Linked worktree Aurora đã bị xóa.
- Remote chưa được push.
- Thay đổi người dùng đang giữ nguyên:
  - `.metadata`
  - `AGENTS.md`
  - `CLAUDE.md`
  - `.claude/skills/`
  - `.superpowers/`
  - `worktrees.txt`
- Stash bảo toàn thay đổi trước merge: `user-root-changes-before-aurora-ff-20260905`.
- Backup ngoài repo: `H:\source\flutter-clean-notes-merge-backup-20260905`.

Không dùng `git reset --hard`, `git clean`, force push, hoặc xóa stash/backup.

## Đã hoàn thành

- Aurora Glass UI responsive cho Home, Editor, Search, Library và Reminder.
- Durable reminder/outbox, migration SQLite v7, notification recovery.
- Accessibility, reduced motion, high contrast, keyboard/focus và compact layouts.
- Web SQLite/WASM, same-origin engine/font fallback và Unicode font contracts.
- Native splash/icon branding Android/iOS/desktop.
- Privacy route và disclosure về storage, reminder, transfer, network behavior.
- Transfer/import/export limits và security contracts.
- CI workflow, release docs, QA docs và branding docs.
- `flutter analyze --no-pub`: pass.
- `flutter test --no-pub --concurrency=1`: pass `637/637`.

Đọc trước các tài liệu sau:

1. `docs/agent-continuation.md`
2. `docs/superpowers/handoff.md`
3. `docs/superpowers/specs/2026-08-17-notes-ui-ux-redesign-design.md`
4. `docs/qa.md`
5. `docs/release.md`
6. `AGENTS.md` và `CLAUDE.md`

## Việc còn phải làm

Thực hiện tuần tự, ghi kết quả vào `docs/agent-continuation.md` hoặc tài liệu
QA tương ứng:

1. Chạy codegen drift check, format và analyzer trên checkout sạch:

   ```text
   flutter pub get --enforce-lockfile
   dart run build_runner build --delete-conflicting-outputs
   dart format --output=none --set-exit-if-changed lib test integration_test tool
   flutter analyze --no-pub --fatal-infos --fatal-warnings
   ```

2. Chạy lại full test suite serial.
3. Build release Web và Windows:

   ```text
   flutter build web --release --no-pub --no-web-resources-cdn
   flutter build windows --release --no-pub
   ```

4. Chạy Android signing verifier bằng toolchain local và credential tạm thời,
   không ghi credential vào repo:

   ```text
   dart run tool/verify_android_release_signing.dart --build-positive-release-artifacts
   ```

5. Khởi động AVD API 36 và chạy:

   ```text
   flutter test integration_test/aurora_smoke_test.dart -d emulator-5554 --no-pub
   ```

   Nếu chạy lần thứ hai, force-stop/relaunch để kiểm tra cold launch. Dọn
   emulator sau khi test, không xóa dữ liệu repo.

6. Chạy GitNexus analyze/index cho đúng repo, sau đó `detect_changes` compare
   với `main` nếu MCP đã trỏ đúng repository. Nếu MCP trỏ nhầm repo, báo rõ
   thay vì giả vờ có kết quả.
7. Chạy secret scan, dependency/advisory scan và kiểm tra Web browser matrix
   theo `docs/qa.md`.
8. Chỉ đánh dấu hoàn tất khi có bằng chứng exact-commit cho từng gate. Hosted
   CI và App Store/Play Store không được tuyên bố pass nếu chưa có external
   credentials, archive, device và store evidence.

## Quy tắc thay đổi mã

- Trước khi sửa function/class/method, chạy GitNexus impact upstream nếu MCP
  đúng repo; cảnh báo nếu risk HIGH/CRITICAL.
- Nếu sửa file có `@riverpod`, luôn chạy build_runner và kiểm tra `.g.dart`.
- Dùng TDD cho bug/behavior mới.
- Không chạy đồng thời các lệnh Flutter có thể sửa lockfile/generated files.
- Không đổi application ID, bundle ID, signing identity, team, version hoặc
  credential nếu chưa có thông tin owner.
- Giữ domain không phụ thuộc data/presentation.
- Không chỉnh/xóa `.claude/skills`, `.superpowers`, stash hoặc backup.

## Kết quả cần báo cáo

Báo cáo ngắn gồm:

- commit HEAD và trạng thái working tree;
- từng gate: PASS/FAIL/PENDING, lệnh và bằng chứng;
- file/code đã sửa, nếu có;
- protected files/stash/backup còn nguyên;
- blockers bên ngoài (credentials, Apple/macOS, hosted CI, store metadata);
- không push remote nếu chưa được yêu cầu rõ ràng.
