#!/bin/bash
# <xbar.title>GitLab unresolved threads</xbar.title>
# <xbar.desc>Unresolved review threads on my open merge requests, grouped by group and project.</xbar.desc>
# <xbar.author>OwnWeb</xbar.author>
# <xbar.dependencies>glab,jq</xbar.dependencies>
# <xbar.abouturl>https://github.com/OwnWeb/swiftbar-gitlab-threads</xbar.abouturl>
# <swiftbar.refreshOnOpen>true</swiftbar.refreshOnOpen>

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Keeps instance-specific settings out of the repository.
readonly CONFIG_FILE="$HOME/.config/swiftbar-gitlab-threads.conf"
# shellcheck source=/dev/null
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

readonly GITLAB_HOST="${GITLAB_HOST:-$(glab config get host)}"
readonly BOT_AUTHOR="${BOT_AUTHOR:-coderabbitai}"
readonly DASHBOARD_URL="https://$GITLAB_HOST/dashboard/merge_requests"

# SwiftBar addresses a plugin by its file name stripped of the refresh interval
# and extension, so renaming the file keeps the self-refresh working.
plugin_file=$(basename "$0")
readonly PLUGIN_NAME="${plugin_file%%.*}"
readonly STATE_DIR="$HOME/.cache/swiftbar-gitlab-threads"
readonly CACHE_FILE="$STATE_DIR/menu"
readonly ERROR_FILE="$STATE_DIR/error"
readonly CACHE_MAX_AGE_SECONDS=30
readonly RETRY_ATTEMPTS=2
readonly RETRY_DELAY_SECONDS=3
readonly TITLE_MAX_CHARS=45
readonly PREVIEW_MAX_CHARS=70
readonly ERROR_MAX_CHARS=200
readonly SECONDS_PER_MINUTE=60
readonly SECONDS_PER_HOUR=3600

read -r -d '' OPEN_MERGE_REQUESTS_QUERY <<'GRAPHQL'
query {
  currentUser {
    authoredMergeRequests(state: opened) {
      nodes {
        iid
        title
        webUrl
        project {
          name
          webUrl
          group { fullPath webUrl }
        }
        discussions {
          nodes {
            resolvable
            resolved
            notes { nodes { url body author { username } } }
          }
        }
      }
    }
  }
}
GRAPHQL

build_menu() {
  local response attempt

  for attempt in $(seq "$RETRY_ATTEMPTS"); do
    response=$(glab api graphql --hostname "$GITLAB_HOST" -f query="$OPEN_MERGE_REQUESTS_QUERY" 2>&1) && break
    [ "$attempt" -lt "$RETRY_ATTEMPTS" ] && sleep "$RETRY_DELAY_SECONDS"
  done

  if ! jq -e .data.currentUser <<<"$response" >/dev/null 2>&1; then
    printf '%s' "${response:0:$ERROR_MAX_CHARS}"
    return 1
  fi

  jq -r \
    --arg bot "$BOT_AUTHOR" \
    --arg dashboard "$DASHBOARD_URL" \
    --argjson titleMax "$TITLE_MAX_CHARS" \
    --argjson previewMax "$PREVIEW_MAX_CHARS" '

    # CodeRabbit wraps its verification scripts in <details> and fenced blocks,
    # which would otherwise fill the preview with shell commands.
    def strip_markup:
      gsub("(?s)<details>.*?</details>"; " ")
      | gsub("(?s)```.*?```"; " ")
      | gsub("(?s)<[^>]*>"; " ")
      | gsub("[_*`>#\\[\\]]"; "")
      | gsub("\\|"; "/")
      | gsub("\\s+"; " ")
      | sub("^ +"; "") | sub(" +$"; "");

    # CodeRabbit opens each remark with a badge line such as
    # "_⚠️ Potential issue_ | _🟠 Major_ | _⚡ Quick win_". Only the severity
    # colour is worth the horizontal space the whole line would cost.
    def badge_lines: [split("\n")[] | select(test("^\\s*_.*_\\s*$"))] | join(" ");
    def body_lines: [split("\n")[] | select(test("^\\s*_.*_\\s*$") | not)] | join("\n");
    def severity: (badge_lines | capture("(?<found>🔴|🟠|🟡|🟢)").found + " ") // "";

    def truncate($max): if length > $max then .[0:$max] + "…" else . end;

    # A trailing note that is pure tooling noise leaves nothing readable,
    # so the thread falls back to the remark that opened it.
    def preview($notes):
      ($notes[-1].body | body_lines | strip_markup) as $latest
      | (if ($latest | length) > 10 then $notes[-1] else $notes[0] end) as $source
      | ($source.body | severity) + ($source.body | body_lines | strip_markup | truncate($previewMax));

    def pending_threads:
      [.discussions.nodes[]
       | select(.resolvable and (.resolved | not))
       | .notes.nodes as $notes
       | {
           author: $notes[-1].author.username,
           url: ($notes[-1].url // $notes[0].url),
           preview: preview($notes),
         }];

    # Every path starts with the same top-level namespace, which carries no
    # information: "acme/clients/foo" reads better as "clients / foo".
    def group_label: split("/") | .[1:] | join(" / ");

    [.data.currentUser.authoredMergeRequests.nodes[]
     | . + { pending: pending_threads }
     | select(.pending | length > 0)
     | {
         group: (.project.group.fullPath | group_label),
         groupUrl: "\(.project.group.webUrl)/-/merge_requests",
         project: .project.name,
         projectUrl: "\(.project.webUrl)/-/merge_requests",
         iid: .iid,
         title: (.title | strip_markup | truncate($titleMax)),
         webUrl: .webUrl,
         pending: .pending,
       }]                                                                    as $merge_requests
    | ([$merge_requests[].pending[].author] | map(select(. == $bot)) | length)   as $bot_count
    | ([$merge_requests[].pending[].author] | map(select(. != $bot)) | length)   as $human_count
    | ($merge_requests
       | group_by(.group)
       | map({
           name: .[0].group,
           url: .[0].groupUrl,
           total: ([.[].pending[]] | length),
           projects: (group_by(.project) | map({ name: .[0].project, url: .[0].projectUrl, merge_requests: . })),
         })
       | sort_by(-.total))                                                      as $groups

    | if ($bot_count + $human_count) == 0 then
        "✓"
      else
        "🔀 \($merge_requests | length)",
        "---",
        "🐰 \($bot_count)  ·  👤 \($human_count) | href=\($dashboard) size=12",
        ($groups[]
         | "---",
           "\(.name)  (\(.total)) | href=\(.url) size=13",
           (.projects[]
            | "  \(.name) | href=\(.url) size=12 color=#888888",
              (.merge_requests[]
               | "  !\(.iid) (\(.pending | length)) \(.title) | href=\(.webUrl)",
                 (.pending[] | "-- \(.author): \(.preview) | href=\(.url)"))))
      end
  ' <<<"$response"
}

file_age_seconds() {
  local modified_at
  modified_at=$(stat -f %m "$1" 2>/dev/null) || return 1
  echo $(( $(date +%s) - modified_at ))
}

format_age() {
  local seconds=$1

  if [ "$seconds" -lt "$SECONDS_PER_MINUTE" ]; then
    echo "${seconds}s ago"
  elif [ "$seconds" -lt "$SECONDS_PER_HOUR" ]; then
    echo "$(( seconds / SECONDS_PER_MINUTE ))m ago"
  else
    echo "$(( seconds / SECONDS_PER_HOUR ))h ago"
  fi
}

print_status() {
  echo "---"

  if [ -f "$CACHE_FILE" ]; then
    echo "Last check at $(date -r "$CACHE_FILE" +%H:%M:%S) ($(format_age "$(file_age_seconds "$CACHE_FILE")")) | size=12 color=#888888"
  fi

  if [ -f "$ERROR_FILE" ]; then
    echo "⚠️ Failed at $(date -r "$ERROR_FILE" +%H:%M:%S): $(tr -d '\n' < "$ERROR_FILE") | size=12 color=red"
  fi

  echo "Refresh now | bash=\"$0\" param1=--fetch terminal=false size=12"
}

# Refreshing the plugin re-runs this script, which would fetch again and loop
# forever. The freshness check breaks that: the rerun finds a young cache.
mkdir -p "$STATE_DIR"

if [ "$1" = "--fetch" ]; then
  if menu=$(build_menu); then
    printf '%s\n' "$menu" > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
    rm -f "$ERROR_FILE"
  else
    # The cache keeps the last known state: a failed check must not blank the menu.
    printf '%s' "$menu" > "$ERROR_FILE"
  fi
  open -g "swiftbar://refreshplugin?name=$PLUGIN_NAME"
  exit 0
fi

if [ -s "$CACHE_FILE" ]; then
  if [ -f "$ERROR_FILE" ]; then
    head -1 "$CACHE_FILE" | sed 's/$/ ⚠️/'
    tail -n +2 "$CACHE_FILE"
  else
    cat "$CACHE_FILE"
  fi
else
  [ -f "$ERROR_FILE" ] && echo "⚠️" || echo "⏳"
fi

print_status

cache_age=$(file_age_seconds "$CACHE_FILE") || cache_age=$(( CACHE_MAX_AGE_SECONDS + 1 ))
if [ "$cache_age" -gt "$CACHE_MAX_AGE_SECONDS" ]; then
  nohup "$0" --fetch >/dev/null 2>&1 &
fi
