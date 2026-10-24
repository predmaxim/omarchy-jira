#!/bin/bash
# bash scripts/jira_test.sh — `jira download` with stubs for secret-tool, curl and xdg-user-dir.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/dl"
cat > "$tmp/bin/secret-tool" <<'S'
#!/bin/bash
printf tok
S
# curl: records its header (stdin) and url, writes "data" to the -o file.
cat > "$tmp/bin/curl" <<'S'
#!/bin/bash
out=; while (( $# > 0 )); do [[ $1 == -o ]] && { out=$2; shift; }; last=$1; shift; done
cat > "$CURL_LOG.hdr"; echo "$last" > "$CURL_LOG.url"; printf data > "$out"
S
printf '#!/bin/bash\necho %s\n' "$tmp/dl" > "$tmp/bin/xdg-user-dir"
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" CURL_LOG="$tmp/curl"
jira="$here/jira"

got=$("$jira" download https://j.ru/jira https://j.ru/jira/secure/attachment/7/a.pdf a.pdf)
[[ $got == "$tmp/dl/a.pdf" && $(cat "$got") == data ]] || { echo "FAIL: first download -> $got"; exit 1; }
grep -q 'Authorization: Bearer tok' "$tmp/curl.hdr" || { echo "FAIL: no token header"; exit 1; }
got=$("$jira" download https://j.ru/jira https://j.ru/jira/secure/attachment/7/a.pdf a.pdf)
[[ $got == "$tmp/dl/a (1).pdf" ]] || { echo "FAIL: clash -> $got"; exit 1; }
got=$("$jira" download https://j.ru/jira https://j.ru/jira/secure/attachment/8/x ../../etc/x)
[[ $got == "$tmp/dl/.._.._etc_x" ]] || { echo "FAIL: path in name -> $got"; exit 1; }
# The token only goes to the Jira it belongs to.
rm -f "$tmp/curl.url"
if "$jira" download https://j.ru/jira https://evil.ru/jira/a.pdf a.pdf 2>/dev/null; then echo "FAIL: foreign url accepted"; exit 1; fi
[[ ! -e $tmp/curl.url ]] || { echo "FAIL: curl called for foreign url"; exit 1; }
if "$jira" download https://j.ru/jira https://j.ru/jiraer/a.pdf a.pdf 2>/dev/null; then echo "FAIL: prefix trick accepted"; exit 1; fi
echo ok
