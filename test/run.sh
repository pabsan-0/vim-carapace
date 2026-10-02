#!/bin/sh
# vim-carapace test runner. Real carapace from $PATH; missing prerequisites are
# rejected (Fail), never silently skipped.
#
#   -v, --verbose   full values
#   -f, --failed    only Fail rows, full values
set -u

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
cd "$root" || exit 1

trunc=1; only_fail=0
while [ $# -gt 0 ]; do
    case $1 in
        -v|--verbose) trunc=0 ;;
        -f|--failed)  trunc=0; only_fail=1 ;;
        *) printf 'usage: %s [-v|--verbose] [-f|--failed]\n' "$0" >&2; exit 2 ;;
    esac
    shift
done

work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT INT TERM
rejects="$work/rejects.txt"; : > "$rejects"
reject() { printf 'reject\tFail\t%s\t\t\trejected\n' "$1" >> "$rejects"; }

for f in plugin/carapace.vim autoload/carapace.vim autoload/carapace/overrides.vim test/carapace.vim; do
    [ -f "$root/$f" ] || reject "missing file: $f"
done
for c in vim carapace git cat; do
    command -v "$c" >/dev/null 2>&1 || reject "missing command: $c"
done
false_bin=$(command -v false 2>/dev/null) || { false_bin=''; reject "missing command: false"; }
have_gst=0
if command -v gst-launch-1.0 >/dev/null 2>&1; then
    have_gst=1
else
    reject "missing command: gst-launch-1.0"
fi

if command -v vim >/dev/null 2>&1; then
    bin="$work/bin"; data="$work/data"
    mkdir -p "$bin" "$data"
    printf '#!/bin/sh\nexit 0\n' > "$bin/gst-launch-1.0"; chmod +x "$bin/gst-launch-1.0"
    printf 'fixture\n' > "$data/fixture.txt"

    run_vim() {
        scenario=$1; shift
        out="$work/$scenario.txt"
        env CARAPACE_TEST_ROOT="$root" \
            CARAPACE_TEST_SCENARIO="$scenario" \
            CARAPACE_TEST_RESULTS="$out" \
            CARAPACE_TEST_BINDIR="$bin" \
            CARAPACE_TEST_DATA="$data" \
            CARAPACE_TEST_FALSE="$false_bin" \
            CARAPACE_HAVE_GST="$have_gst" \
            "$@" vim -u NONE -N -es -S "$root/test/carapace.vim" >/dev/null 2>&1
        [ -f "$out" ] || printf '%s\tFail\tvim produced no results\t\t\tno results\n' "$scenario" > "$out"
    }

    unset CARAPACE_BRIDGES 2>/dev/null || true
    run_vim main
    run_vim nobin
    run_vim falsebin
    run_vim bridges CARAPACE_BRIDGES=sentinel CARAPACE_TEST_EXPECT_BRIDGES=sentinel
    run_vim bridges_custom CARAPACE_BRIDGES= CARAPACE_TEST_EXPECT_BRIDGES=zzz
fi

files="$rejects"
for f in "$work"/*.txt; do
    [ "$f" = "$rejects" ] && continue
    files="$files $f"
done

cat $files | awk -F '\t' -v trunc="$trunc" -v only_fail="$only_fail" '
function fit(s, n) { return (trunc && length(s) > n) ? substr(s, 1, n - 3) "..." : s }
function pad(s, n) { return s sprintf("%*s", n - length(s), "") }
BEGIN { w1 = length("Scenario"); w3 = length("Description"); w4 = length("Given"); w5 = length("Expected") }
{
    if (only_fail && $2 != "Fail") next
    d = fit($3, 40); g = fit($4, 32); e = fit($5, 32); o = fit($6, 40)
    n++
    a1[n] = $1; a2[n] = $2; a3[n] = d; a4[n] = g; a5[n] = e; a6[n] = o
    if (length($1) > w1) w1 = length($1)
    if (length(d)  > w3) w3 = length(d)
    if (length(g)  > w4) w4 = length(g)
    if (length(e)  > w5) w5 = length(e)
}
END {
    print pad("Scenario", w1) "  " pad("Pass", 4) "  " pad("Description", w3) "  " pad("Given", w4) "  " pad("Expected", w5) "  " "Got"
    for (i = 1; i <= n; i++)
        print pad(a1[i], w1) "  " pad(a2[i], 4) "  " pad(a3[i], w3) "  " pad(a4[i], w4) "  " pad(a5[i], w5) "  " a6[i]
}'

counts=$(cat $files | awk -F '\t' '{ if ($2 == "Pass") p++; else if ($2 == "Fail") f++ } END { print p + 0 " " f + 0 }')
pass=${counts% *}; fail=${counts#* }
printf '\n%s Pass, %s Fail\n' "$pass" "$fail"
[ "$fail" -eq 0 ] && exit 0
exit 1
