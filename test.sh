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
  "threads":[{"author":"coderabbitai","url":"$MERGE_REQUEST_URL#note_$LAST_NOTE_ID","noteId":$LAST_NOTE_ID,"preview":"Guard the retry"}]}]
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
