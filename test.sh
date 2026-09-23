#!/bin/bash
# Exercises the seen/unseen rule against the real plugin, without network access:
# a fresh payload keeps the script from fetching.
set -euo pipefail

readonly PLUGIN="$(cd "$(dirname "$0")" && pwd)/gitlab-threads.1m.sh"
readonly MERGE_REQUEST_URL="https://gitlab.example.com/acme/api/-/merge_requests/7"
readonly LAST_NOTE_ID=500

STATE_DIR=$(mktemp -d)
export STATE_DIR GITLAB_HOST=gitlab.example.com
trap 'rm -rf "$STATE_DIR"' EXIT

cat > "$STATE_DIR/payload.json" <<JSON
[{"group":"clients / acme","groupUrl":"g","project":"API","projectUrl":"p",
  "iid":"7","title":"Add retries","webUrl":"$MERGE_REQUEST_URL","lastNoteId":$LAST_NOTE_ID,
  "lastActivityAt":"2026-01-02T10:00:00Z",
  "threads":[{"author":"coderabbitai","url":"$MERGE_REQUEST_URL#note_$LAST_NOTE_ID","noteId":$LAST_NOTE_ID,"createdAt":"2026-01-02T10:00:00Z","preview":"Guard the retry"}]}]
JSON

# Piping into head would close the pipe under the plugin and trip pipefail.
menu() { "$PLUGIN"; }

assert_title() {
  local expected=$1 description=$2 title
  title=$(menu); title=${title%%$'\n'*}
  [ "$title" = "$expected" ] || { echo "FAIL: $description (expected '$expected', got '$title')"; exit 1; }
  echo "ok: $description"
}

assert_title "🔀 1" "an unseen merge request shows in the menu bar"

"$PLUGIN" --mark "$MERGE_REQUEST_URL" "$LAST_NOTE_ID"
assert_title "✓" "marking it seen empties the inbox"
case "$(menu)" in *"👁 Seen (1)"*) ;; *) echo "FAIL: seen submenu is missing"; exit 1;; esac
echo "ok: the seen submenu lists it"

"$PLUGIN" --mark "$MERGE_REQUEST_URL" $(( LAST_NOTE_ID - 1 ))
assert_title "🔀 1" "a newer comment brings it back"

"$PLUGIN" --mark "$MERGE_REQUEST_URL" $(( LAST_NOTE_ID + 1 ))
assert_title "✓" "resolving a thread does not bring it back"

"$PLUGIN" --unmark "$MERGE_REQUEST_URL"
assert_title "🔀 1" "moving it back to the inbox restores it"

cat > "$STATE_DIR/payload.json" <<'JSON'
[{"group":"older","groupUrl":"g1","project":"One","projectUrl":"p1","iid":"1","title":"Older",
  "webUrl":"https://x/mr/1","lastNoteId":1,"lastActivityAt":"2026-01-01T00:00:00Z",
  "threads":[{"author":"bob","url":"https://x/mr/1#note_1","noteId":1,"createdAt":"2026-01-01T00:00:00Z","preview":"a"},
             {"author":"bob","url":"https://x/mr/1#note_2","noteId":2,"createdAt":"2025-12-31T00:00:00Z","preview":"b"}]},
 {"group":"newer","groupUrl":"g2","project":"Two","projectUrl":"p2","iid":"2","title":"Newer",
  "webUrl":"https://x/mr/2","lastNoteId":3,"lastActivityAt":"2026-06-01T00:00:00Z",
  "threads":[{"author":"bob","url":"https://x/mr/2#note_3","noteId":3,"createdAt":"2026-06-01T00:00:00Z","preview":"c"}]}]
JSON

# The group holding the most recent comment leads, even with fewer threads.
groups=$(menu | grep 'size=13' | cut -d' ' -f1 | tr '\n' ' ')
[ "$groups" = "newer older " ] || { echo "FAIL: groups are not sorted by recency (got '$groups')"; exit 1; }
echo "ok: groups lead with the most recent comment"

threads=$(menu | grep -c '^-- bob:')
[ "$threads" = 3 ] || { echo "FAIL: expected 3 thread lines, got $threads"; exit 1; }
echo "ok: every thread is listed"
