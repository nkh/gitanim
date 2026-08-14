// diffvim-compute.go — External diff computer for diffvim (Go version).
//
// Reads two files, computes line-level + char-level diff, and writes
// the result in a format that `diffvim --precomputed FILE` can consume.
//
// Supports three line-diff algorithms (lcs, myers, patience) selected
// via --algorithm or DIFFVIM_ALGORITHM, and optional semantic cleanup
// of char-level diffs via --semantic-cleanup or DIFFVIM_SEMANTIC_CLEANUP.
//
// Build: make go
// Usage: diffvim-compute-go <oldfile> <newfile> <outputfile>
//                          [--algorithm lcs|myers|patience] [--semantic-cleanup]
//
// Timing is printed to stderr.

package main

import (
        "bufio"
        "fmt"
        "io"
        "os"
        "strings"
        "time"
)

type opType int

const (
        opKeep opType = iota
        opDelete
        opInsert
)

type lineOp struct {
        typ  opType
        aIdx int
        bIdx int
}

type charOp struct {
        typ  opType
        code int // Unicode code point
}

type hunk struct {
        targetLine    int
        deletedCount  int
        insertedCount int
        isEndInsert   bool
        isEndDelete   bool
        charOps       []charOp
}

func readLines(path string) []string {
        data, err := os.ReadFile(path)
        if err != nil {
                return nil
        }
        s := string(data)
        if s == "" {
                return []string{}
        }
        lines := strings.Split(s, "\n")
        // If file ends with \n, the last element is "" — remove it to match
        // vim's readfile() behavior (vim doesn't produce a trailing empty line).
        if len(lines) > 0 && lines[len(lines)-1] == "" && strings.HasSuffix(s, "\n") {
                lines = lines[:len(lines)-1]
        }
        return lines
}

// readFileOrStdin reads an entire file (or stdin if path is "-") into a string.
func readFileOrStdin(path string) (string, error) {
        if path == "-" {
                data, err := io.ReadAll(os.Stdin)
                if err != nil {
                        return "", err
                }
                return string(data), nil
        }
        data, err := os.ReadFile(path)
        if err != nil {
                return "", err
        }
        return string(data), nil
}

// parseUnifiedDiff parses a unified diff (patch file) into oldLines and newLines.
//
// Reads from `path` (or stdin if "-").
//
// Unified diff rules:
//   - `---` prefix  → old file header, ignore.
//   - `+++` prefix  → new file header, ignore.
//   - `@@`  prefix  → hunk header, ignore (we recompute our own hunks).
//   - `\`   prefix  → diff metadata, ignore.
//   - `-`   prefix  (not `---`) → old file line; strip leading `-`.
//   - `+`   prefix  (not `+++`) → new file line; strip leading `+`.
//   - ` `   prefix  → context line; strip leading ` `; appears in BOTH.
//   - empty line    → treated as a space-prefixed empty context line.
//   - anything else → unrecognized; skip.
//
// Multiple hunks are concatenated to reconstruct the full old/new content.
func parseUnifiedDiff(path string) (oldLines, newLines []string, err error) {
        content, err := readFileOrStdin(path)
        if err != nil {
                return nil, nil, err
        }
        bytes := content
        start := 0
        for i := 0; i <= len(bytes); i++ {
                if i == len(bytes) || bytes[i] == '\n' {
                        lineLen := i - start
                        // Skip a trailing empty line (matches vim's readfile()).
                        if i == len(bytes) && lineLen == 0 {
                                break
                        }
                        line := bytes[start:i]
                        if lineLen == 0 {
                                // Empty line in the diff = empty context line in both files.
                                oldLines = append(oldLines, "")
                                newLines = append(newLines, "")
                        } else if lineLen >= 3 && string(line[:3]) == "---" {
                                // old file header — ignore
                        } else if lineLen >= 3 && string(line[:3]) == "+++" {
                                // new file header — ignore
                        } else if lineLen >= 2 && string(line[:2]) == "@@" {
                                // hunk header — ignore
                        } else if line[0] == '\\' {
                                // metadata — ignore
                        } else if line[0] == '-' {
                                // delete line — strip leading '-'
                                oldLines = append(oldLines, string(line[1:]))
                        } else if line[0] == '+' {
                                // insert line — strip leading '+'
                                newLines = append(newLines, string(line[1:]))
                        } else if line[0] == ' ' {
                                // context line — strip leading ' ', present in both
                                s := string(line[1:])
                                oldLines = append(oldLines, s)
                                newLines = append(newLines, s)
                        }
                        // else: unrecognized line (e.g. "diff --git") — skip

                        start = i + 1
                }
        }
        return oldLines, newLines, nil
}

/* Line-level LCS diff over a sub-range [aStart,aEnd) x [bStart,bEnd).
 * Produces ops with ABSOLUTE indices into a/b. */
func lineDiffRange(a []string, aStart, aEnd int, b []string, bStart, bEnd int) []lineOp {
        na, nb := aEnd-aStart, bEnd-bStart
        dp := make([][]int, na+1)
        for i := range dp {
                dp[i] = make([]int, nb+1)
        }
        for i := 1; i <= na; i++ {
                for j := 1; j <= nb; j++ {
                        if a[aStart+i-1] == b[bStart+j-1] {
                                dp[i][j] = dp[i-1][j-1] + 1
                        } else if dp[i-1][j] > dp[i][j-1] {
                                dp[i][j] = dp[i-1][j]
                        } else {
                                dp[i][j] = dp[i][j-1]
                        }
                }
        }
        var ops []lineOp
        i, j := na, nb
        for i > 0 || j > 0 {
                if i > 0 && j > 0 && a[aStart+i-1] == b[bStart+j-1] {
                        ops = append(ops, lineOp{opKeep, aStart + i - 1, bStart + j - 1})
                        i--; j--
                } else if j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j]) {
                        ops = append(ops, lineOp{opInsert, 0, bStart + j - 1})
                        j--
                } else {
                        ops = append(ops, lineOp{opDelete, aStart + i - 1, 0})
                        i--
                }
        }
        // Reverse
        for k, l := 0, len(ops)-1; k < l; k, l = k+1, l-1 {
                ops[k], ops[l] = ops[l], ops[k]
        }
        return ops
}

func lineDiff(a, b []string) []lineOp {
        return lineDiffRange(a, 0, len(a), b, 0, len(b))
}

/* --- Myers diff algorithm (O(ND)) --- */
/* Faster than LCS for small diffs. Falls back to LCS for very large N+M. */
func myersDiff(a, b []string) []lineOp {
        na, nb := len(a), len(b)
        if na+nb > 200000 {
                return lineDiff(a, b)
        }
        max := na + nb
        v := make([]int, 2*max+1)
        idx := func(k int) int { return k + max }
        /* trace stores a copy of v at the start of each depth d. */
        trace := make([][]int, max+1)

        for d := 0; d <= max; d++ {
                trace[d] = make([]int, 2*max+1)
                copy(trace[d], v)
                for k := -d; k <= d; k += 2 {
                        var x int
                        if k == -d || (k != d && v[idx(k-1)] < v[idx(k+1)]) {
                                x = v[idx(k+1)]
                        } else {
                                x = v[idx(k-1)] + 1
                        }
                        y := x - k
                        for x < na && y < nb && a[x] == b[y] {
                                x++
                                y++
                        }
                        v[idx(k)] = x
                        if x >= na && y >= nb {
                                /* Backtrack from (x, y) at depth d. */
                                var ops []lineOp
                                cx, cy := na, nb
                                for dd := d; dd > 0; dd-- {
                                        vp := trace[dd]
                                        tv := func(kk int) int { return vp[idx(kk)] }
                                        k := cx - cy
                                        var prevX, prevY int
                                        var fromBelow bool
                                        if k == -dd {
                                                fromBelow = true
                                        } else if k == dd {
                                                fromBelow = false
                                        } else {
                                                fromBelow = tv(k-1) < tv(k+1)
                                        }
                                        if fromBelow {
                                                prevX = tv(k + 1)
                                                prevY = prevX - (k + 1)
                                        } else {
                                                prevX = tv(k-1) + 1
                                                prevY = prevX - (k - 1)
                                        }
                                        /* Emit diagonal keeps from (cx,cy) back to (prevX, prevY). */
                                        for cx > prevX && cy > prevY {
                                                ops = append(ops, lineOp{opKeep, cx - 1, cy - 1})
                                                cx--
                                                cy--
                                        }
                                        /* The single non-diagonal step. */
                                        if fromBelow {
                                                ops = append(ops, lineOp{opInsert, 0, cy - 1})
                                                cy--
                                        } else {
                                                ops = append(ops, lineOp{opDelete, cx - 1, 0})
                                                cx--
                                        }
                                }
                                /* Handle any diagonal keeps at the very start (depth 0). */
                                for cx > 0 && cy > 0 {
                                        ops = append(ops, lineOp{opKeep, cx - 1, cy - 1})
                                        cx--
                                        cy--
                                }
                                /* Reverse */
                                for i, j := 0, len(ops)-1; i < j; i, j = i+1, j-1 {
                                        ops[i], ops[j] = ops[j], ops[i]
                                }
                                return ops
                        }
                }
        }
        /* Fallback */
        return lineDiff(a, b)
}

/* --- Patience diff algorithm --- */
/* Anchors on unique common lines, then recurses on the gaps. */

/* Find unique common lines between a[aStart..aEnd) and b[bStart..bEnd).
 * Returns matching (aIdx, bIdx) pairs (in increasing aIdx order, then
 * filtered to the LIS of bIdx) as two parallel slices. */
func findPatienceAnchors(a []string, aStart, aEnd int, b []string, bStart, bEnd int) (outAIdx, outBIdx []int) {
        for i := aStart; i < aEnd; i++ {
                /* Check if a[i] appears exactly once in a[aStart..aEnd). */
                aCount := 0
                for k := aStart; k < aEnd; k++ {
                        if a[i] == a[k] {
                                aCount++
                        }
                }
                if aCount != 1 {
                        continue
                }
                /* Find the unique match in b[bStart..bEnd). */
                bMatch := -1
                bCount := 0
                for k := bStart; k < bEnd; k++ {
                        if a[i] == b[k] {
                                bMatch = k
                                bCount++
                        }
                }
                if bCount == 1 {
                        outAIdx = append(outAIdx, i)
                        outBIdx = append(outBIdx, bMatch)
                }
        }
        count := len(outAIdx)
        if count <= 1 {
                return
        }
        /* LIS of bIdx via patience sorting. */
        lisPrev := make([]int, count)
        lisTailIdx := make([]int, count)
        lisLen := 0
        for i := 0; i < count; i++ {
                lo, hi := 0, lisLen
                for lo < hi {
                        mid := (lo + hi) / 2
                        if outBIdx[lisTailIdx[mid]] < outBIdx[i] {
                                lo = mid + 1
                        } else {
                                hi = mid
                        }
                }
                if lo > 0 {
                        lisPrev[i] = lisTailIdx[lo-1]
                } else {
                        lisPrev[i] = -1
                }
                if lo == lisLen {
                        lisTailIdx[lisLen] = i
                        lisLen++
                } else {
                        lisTailIdx[lo] = i
                }
        }
        /* Reconstruct LIS. */
        keepA := make([]int, lisLen)
        keepB := make([]int, lisLen)
        idx := lisTailIdx[lisLen-1]
        for i := lisLen - 1; i >= 0; i-- {
                keepA[i] = outAIdx[idx]
                keepB[i] = outBIdx[idx]
                idx = lisPrev[idx]
        }
        outAIdx = keepA
        outBIdx = keepB
        return
}

func patienceDiffRange(a []string, aStart, aEnd int, b []string, bStart, bEnd int) []lineOp {
        na, nb := aEnd-aStart, bEnd-bStart
        var ops []lineOp

        if na == 0 && nb == 0 {
                return ops
        }
        if na == 0 {
                for j := 0; j < nb; j++ {
                        ops = append(ops, lineOp{opInsert, 0, bStart + j})
                }
                return ops
        }
        if nb == 0 {
                for i := 0; i < na; i++ {
                        ops = append(ops, lineOp{opDelete, aStart + i, 0})
                }
                return ops
        }

        /* Find patience anchors. */
        anchorA, anchorB := findPatienceAnchors(a, aStart, aEnd, b, bStart, bEnd)
        nAnchors := len(anchorA)

        if nAnchors == 0 {
                /* No unique common lines — fall back to LCS for this range. */
                return lineDiffRange(a, aStart, aEnd, b, bStart, bEnd)
        }

        /* Diff the gaps between anchors. */
        prevA, prevB := aStart, bStart
        for k := 0; k <= nAnchors; k++ {
                var curA, curB int
                if k < nAnchors {
                        curA = anchorA[k]
                        curB = anchorB[k]
                } else {
                        curA = aEnd
                        curB = bEnd
                }
                if curA > prevA || curB > prevB {
                        subOps := patienceDiffRange(a, prevA, curA, b, prevB, curB)
                        ops = append(ops, subOps...)
                }
                if k < nAnchors {
                        ops = append(ops, lineOp{opKeep, anchorA[k], anchorB[k]})
                        prevA = anchorA[k] + 1
                        prevB = anchorB[k] + 1
                }
        }
        return ops
}

func patienceDiff(a, b []string) []lineOp {
        return patienceDiffRange(a, 0, len(a), b, 0, len(b))
}

/* --- Diff dispatcher --- */
func computeLineDiff(a, b []string, algorithm string) []lineOp {
        switch algorithm {
        case "myers":
                return myersDiff(a, b)
        case "patience":
                return patienceDiff(a, b)
        default:
                return lineDiff(a, b)
        }
}

func charDiff(a, b string) []charOp {
        // Use Unicode runes (not bytes) for char-level diff.
        // This matches vim's split(str, '\zs') behavior.
        ac := []rune(a)
        bc := []rune(b)
        na, nb := len(ac), len(bc)
        dp := make([][]int, na+1)
        for i := range dp {
                dp[i] = make([]int, nb+1)
        }
        for i := 1; i <= na; i++ {
                for j := 1; j <= nb; j++ {
                        if ac[i-1] == bc[j-1] {
                                dp[i][j] = dp[i-1][j-1] + 1
                        } else if dp[i-1][j] > dp[i][j-1] {
                                dp[i][j] = dp[i-1][j]
                        } else {
                                dp[i][j] = dp[i][j-1]
                        }
                }
        }
        var ops []charOp
        i, j := na, nb
        for i > 0 || j > 0 {
                if i > 0 && j > 0 && ac[i-1] == bc[j-1] {
                        ops = append(ops, charOp{opKeep, int(ac[i-1])})
                        i--; j--
                } else if j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j]) {
                        ops = append(ops, charOp{opInsert, int(bc[j-1])})
                        j--
                } else {
                        ops = append(ops, charOp{opDelete, int(ac[i-1])})
                        i--
                }
        }
        for k, l := 0, len(ops)-1; k < l; k, l = k+1, l-1 {
                ops[k], ops[l] = ops[l], ops[k]
        }
        return ops
}

/* --- Semantic cleanup: merge adjacent delete+insert pairs that cancel --- */
func semanticCleanup(ops []charOp) []charOp {
        if len(ops) < 2 {
                return ops
        }
        out := make([]charOp, 0, len(ops))
        i := 0
        for i < len(ops) {
                if i+1 < len(ops) {
                        /* delete X followed by insert X -> keep X */
                        if ops[i].typ == opDelete && ops[i+1].typ == opInsert && ops[i].code == ops[i+1].code {
                                out = append(out, charOp{opKeep, ops[i].code})
                                i += 2
                                continue
                        }
                        /* insert X followed by delete X -> keep X */
                        if ops[i].typ == opInsert && ops[i+1].typ == opDelete && ops[i].code == ops[i+1].code {
                                out = append(out, charOp{opKeep, ops[i].code})
                                i += 2
                                continue
                        }
                }
                out = append(out, ops[i])
                i++
        }
        return out
}

/* --- Op-sequence optimization: consolidate interleaved del/ins --- */
func optimizeSequence(ops []charOp) []charOp {
        if len(ops) < 4 {
                return ops
        }
        out := make([]charOp, 0, len(ops))
        i := 0
        for i < len(ops) {
                if ops[i].typ != opKeep && ops[i].code != 10 {
                        for i < len(ops) {
                                if ops[i].typ == opKeep {
                                        break
                                }
                                if ops[i].code == 10 {
                                        break
                                }
                                out = append(out, ops[i])
                                i++
                        }
                } else {
                        out = append(out, ops[i])
                        i++
                }
        }
        return out
}

/* --- Left-to-right: sort ops within each line by type --- */
func leftToRight(ops []charOp) []charOp {
        if len(ops) < 2 {
                return ops
        }
        out := make([]charOp, 0, len(ops))
        i := 0
        for i < len(ops) {
                lineStart := i
                for i < len(ops) && ops[i].code != 10 {
                        i++
                }
                lineEnd := i
                for k := lineStart; k < lineEnd; k++ {
                        if ops[k].typ == opKeep {
                                out = append(out, ops[k])
                        }
                }
                for k := lineStart; k < lineEnd; k++ {
                        if ops[k].typ == opDelete {
                                out = append(out, ops[k])
                        }
                }
                for k := lineStart; k < lineEnd; k++ {
                        if ops[k].typ == opInsert {
                                out = append(out, ops[k])
                        }
                }
                if i < len(ops) {
                        out = append(out, ops[i])
                        i++
                }
        }
        return out
}

/* --- Word-level diff --- */
/* Splits text into tokens (maximal runs of non-whitespace + maximal runs of
 * whitespace), runs LCS at the token level, then expands each token to
 * individual char ops. Produces more natural typing patterns than char-level
 * LCS because consecutive chars within a word are grouped.
 *
 * Matches vimscript s:WordDiff + s:SplitWords. */

func isWsByte(c byte) bool {
        /* Vim's \s matches [ \t\n\r\f\v] */
        return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f'
}

/* Token: byte offset + length into the source string. */
type token struct {
        start int
        len   int
}

/* Split text into tokens: maximal runs of whitespace OR maximal runs of
 * non-whitespace. E.g. "hello world" -> ["hello", " ", "world"]. */
func splitWords(text string) []token {
        var toks []token
        textLen := len(text)
        i := 0
        for i < textLen {
                start := i
                if isWsByte(text[i]) {
                        for i < textLen && isWsByte(text[i]) {
                                i++
                        }
                } else {
                        for i < textLen && !isWsByte(text[i]) {
                                i++
                        }
                }
                toks = append(toks, token{start, i - start})
        }
        return toks
}

func tokenEq(a string, ta token, b string, tb token) bool {
        return ta.len == tb.len && a[ta.start:ta.start+ta.len] == b[tb.start:tb.start+tb.len]
}

func wordDiff(a, b string) []charOp {
        ta := splitWords(a)
        tb := splitWords(b)
        na, nb := len(ta), len(tb)

        /* LCS at token level */
        dp := make([][]int, na+1)
        for i := range dp {
                dp[i] = make([]int, nb+1)
        }
        for i := 1; i <= na; i++ {
                for j := 1; j <= nb; j++ {
                        if tokenEq(a, ta[i-1], b, tb[j-1]) {
                                dp[i][j] = dp[i-1][j-1] + 1
                        } else if dp[i-1][j] > dp[i][j-1] {
                                dp[i][j] = dp[i-1][j]
                        } else {
                                dp[i][j] = dp[i][j-1]
                        }
                }
        }

        /* Backtrack at token level, collecting (type, is_a, tok_idx) in reverse. */
        type tokenOp struct {
                typ    opType
                isA    bool
                tokIdx int
        }
        tops := make([]tokenOp, 0, na+nb)
        i, j := na, nb
        for i > 0 || j > 0 {
                if i > 0 && j > 0 && tokenEq(a, ta[i-1], b, tb[j-1]) {
                        tops = append(tops, tokenOp{opKeep, true, i - 1})
                        i--
                        j--
                } else if j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j]) {
                        tops = append(tops, tokenOp{opInsert, false, j - 1})
                        j--
                } else {
                        tops = append(tops, tokenOp{opDelete, true, i - 1})
                        i--
                }
        }
        /* Reverse token ops so chars within each token are in forward order. */
        for k, l := 0, len(tops)-1; k < l; k, l = k+1, l-1 {
                tops[k], tops[l] = tops[l], tops[k]
        }

        /* Expand each token to char ops (UTF-8 runes). */
        var ops []charOp
        for _, top := range tops {
                var text string
                var tok token
                if top.isA {
                        text = a
                        tok = ta[top.tokIdx]
                } else {
                        text = b
                        tok = tb[top.tokIdx]
                }
                slice := text[tok.start : tok.start+tok.len]
                /* Decode UTF-8 runes from the slice. For invalid sequences, emit the
                 * raw byte as a code point (matching the C implementation). */
                pos := 0
                for pos < len(slice) {
                        c := slice[pos]
                        var cp int
                        var advance int
                        if c < 0x80 {
                                cp = int(c)
                                advance = 1
                        } else if (c&0xE0) == 0xC0 && pos+1 < len(slice) && (slice[pos+1]&0xC0) == 0x80 {
                                cp = (int(c&0x1F) << 6) | int(slice[pos+1]&0x3F)
                                advance = 2
                        } else if (c&0xF0) == 0xE0 && pos+2 < len(slice) &&
                                (slice[pos+1]&0xC0) == 0x80 && (slice[pos+2]&0xC0) == 0x80 {
                                cp = (int(c&0x0F) << 12) | (int(slice[pos+1]&0x3F) << 6) | int(slice[pos+2]&0x3F)
                                advance = 3
                        } else if (c&0xF8) == 0xF0 && pos+3 < len(slice) &&
                                (slice[pos+1]&0xC0) == 0x80 && (slice[pos+2]&0xC0) == 0x80 && (slice[pos+3]&0xC0) == 0x80 {
                                cp = (int(c&0x07) << 18) | (int(slice[pos+1]&0x3F) << 12) |
                                        (int(slice[pos+2]&0x3F) << 6) | int(slice[pos+3]&0x3F)
                                advance = 4
                        } else {
                                cp = int(c) /* invalid, treat as single byte */
                                advance = 1
                        }
                        ops = append(ops, charOp{top.typ, cp})
                        pos += advance
                }
        }
        return ops
}

/* Strip leading whitespace (spaces and tabs) from a line.
 * Used by --indent-aware so lines that differ only in indentation are
 * treated as "keep" at the line level. */
func normalizeIndent(line string) string {
        start := 0
        for start < len(line) && (line[start] == ' ' || line[start] == '\t') {
                start++
        }
        return line[start:]
}

func main() {
        tStart := time.Now()

        algorithm := os.Getenv("DIFFVIM_ALGORITHM")
        if algorithm == "" {
                algorithm = "lcs"
        }
        doSemantic := strings.HasPrefix(os.Getenv("DIFFVIM_SEMANTIC_CLEANUP"), "1")
        doWordDiff := strings.HasPrefix(os.Getenv("DIFFVIM_WORD_DIFF"), "1")
        doIndentAware := strings.HasPrefix(os.Getenv("DIFFVIM_INDENT_AWARE"), "1")
        /* DIFFVIM_OPTIMIZE_SEQUENCE defaults on; only "0" turns it off */
        doOptimize := !strings.HasPrefix(os.Getenv("DIFFVIM_OPTIMIZE_SEQUENCE"), "0")
        doL2R := strings.HasPrefix(os.Getenv("DIFFVIM_LEFT_TO_RIGHT"), "1")

        /* Parse args:
         *   Two-file mode: <oldfile> <newfile> <outputfile> [options]
         *   Diff mode:     --diff <patchfile> <outputfile> [options]
         * Options: --algorithm lcs|myers|patience, --semantic-cleanup,
         *          --word-diff, --indent-aware. May appear in any position. */
        diffMode := false
        var positionals []string
        for i := 1; i < len(os.Args); i++ {
                if os.Args[i] == "--algorithm" && i+1 < len(os.Args) {
                        algorithm = os.Args[i+1]
                        i++
                } else if os.Args[i] == "--semantic-cleanup" {
                        doSemantic = true
                } else if os.Args[i] == "--word-diff" {
                        doWordDiff = true
                } else if os.Args[i] == "--indent-aware" {
                        doIndentAware = true
                } else if os.Args[i] == "--optimize-sequence" {
                        doOptimize = true
                } else if os.Args[i] == "--no-optimize-sequence" {
                        doOptimize = false
                } else if os.Args[i] == "--left-to-right" {
                        doL2R = true
                } else if os.Args[i] == "--diff" {
                        diffMode = true
                } else {
                        positionals = append(positionals, os.Args[i])
                }
        }

        var outfile string
        var oldLines, newLines []string
        tReadStart := time.Now()
        if diffMode {
                if len(positionals) < 2 {
                        fmt.Fprintf(os.Stderr, "Usage: %s --diff <patchfile> <outputfile> [--algorithm lcs|myers|patience] [--semantic-cleanup] [--word-diff] [--indent-aware]\n", os.Args[0])
                        fmt.Fprintf(os.Stderr, "   or: %s --diff - <outputfile> [options]   (read diff from stdin)\n", os.Args[0])
                        os.Exit(1)
                }
                diffFile := positionals[0]
                outfile = positionals[1]
                var err error
                oldLines, newLines, err = parseUnifiedDiff(diffFile)
                if err != nil {
                        fmt.Fprintf(os.Stderr, "Error: cannot read diff file %s: %v\n", diffFile, err)
                        os.Exit(1)
                }
        } else {
                if len(positionals) < 3 {
                        fmt.Fprintf(os.Stderr, "Usage: %s <oldfile> <newfile> <outputfile> [--algorithm lcs|myers|patience] [--semantic-cleanup] [--word-diff] [--indent-aware]\n", os.Args[0])
                        fmt.Fprintf(os.Stderr, "   or: %s --diff <patchfile> <outputfile> [options]\n", os.Args[0])
                        os.Exit(1)
                }
                oldfile := positionals[0]
                newfile := positionals[1]
                outfile = positionals[2]
                oldLines = readLines(oldfile)
                newLines = readLines(newfile)
        }

        tReadEnd := time.Now()

        if len(oldLines) == 0 && len(newLines) == 0 {
                fmt.Fprintln(os.Stderr, "Error: both files empty or unreadable")
                os.Exit(1)
        }

        /* If indent_aware, build normalized copies of the lines for the line-level
         * diff. The indices returned by computeLineDiff are the same (since
         * normalization doesn't change line count), so we can use them to access
         * the ORIGINAL (non-normalized) lines when building hunk text. */
        var lineA, lineB []string
        if doIndentAware {
                lineA = make([]string, len(oldLines))
                lineB = make([]string, len(newLines))
                for i, l := range oldLines {
                        lineA[i] = normalizeIndent(l)
                }
                for i, l := range newLines {
                        lineB[i] = normalizeIndent(l)
                }
        } else {
                lineA = oldLines
                lineB = newLines
        }

        tDiffStart := time.Now()
        lops := computeLineDiff(lineA, lineB, algorithm)

        var hunks []hunk
        oldPos := 1
        for i := 0; i < len(lops); i++ {
                if lops[i].typ == opKeep {
                        oldPos = lops[i].aIdx + 2
                        continue
                }
                start := i
                for i < len(lops) && lops[i].typ != opKeep {
                        i++
                }
                end := i
                i--

                h := hunk{targetLine: oldPos}
                var oldText, newText strings.Builder
                for k := start; k < end; k++ {
                        switch lops[k].typ {
                        case opDelete:
                                if h.deletedCount > 0 {
                                        oldText.WriteByte('\n')
                                }
                                oldText.WriteString(oldLines[lops[k].aIdx])
                                h.deletedCount++
                                oldPos = lops[k].aIdx + 2
                        case opInsert:
                                if h.insertedCount > 0 {
                                        newText.WriteByte('\n')
                                }
                                newText.WriteString(newLines[lops[k].bIdx])
                                h.insertedCount++
                        }
                }
                ot, nt := oldText.String(), newText.String()
                if h.deletedCount == 0 {
                        ot = ""
                        if len(oldLines) == 0 {
                                /* no separator */
                        } else if h.targetLine > len(oldLines) {
                                nt = "\n" + nt
                                h.isEndInsert = true
                        } else {
                                nt += "\n"
                        }
                } else if h.insertedCount == 0 {
                        nt = ""
                        if h.targetLine+h.deletedCount-1 >= len(oldLines) {
                                ot = "\n" + ot
                                h.isEndDelete = true
                        } else {
                                ot += "\n"
                        }
                }
                h.charOps = func() []charOp {
                        if doWordDiff {
                                return wordDiff(ot, nt)
                        }
                        return charDiff(ot, nt)
                }()
                if doSemantic {
                        h.charOps = semanticCleanup(h.charOps)
                }
                if doOptimize {
                        h.charOps = optimizeSequence(h.charOps)
                }
                if doL2R {
                        h.charOps = leftToRight(h.charOps)
                }
                hunks = append(hunks, h)
        }
        tDiffEnd := time.Now()

        tWriteStart := time.Now()
        f, err := os.Create(outfile)
        if err != nil {
                fmt.Fprintf(os.Stderr, "Cannot write %s: %v\n", outfile, err)
                os.Exit(1)
        }
        w := bufio.NewWriter(f)
        fmt.Fprintln(w, "# diffvim precomputed diff v1")
        fmt.Fprintf(w, "# algorithm %s\n", algorithm)
        fmt.Fprintf(w, "# semantic_cleanup %d\n", semanticBoolToInt(doSemantic))
        fmt.Fprintf(w, "# word_diff %d\n", semanticBoolToInt(doWordDiff))
        fmt.Fprintf(w, "# indent_aware %d\n", semanticBoolToInt(doIndentAware))
        fmt.Fprintf(w, "# optimize_sequence %d\n", semanticBoolToInt(doOptimize))
        fmt.Fprintf(w, "# left_to_right %d\n", semanticBoolToInt(doL2R))
        fmt.Fprintf(w, "# hunk_count %d\n", len(hunks))
        for _, h := range hunks {
                ei, ed := 0, 0
                if h.isEndInsert { ei = 1 }
                if h.isEndDelete { ed = 1 }
                fmt.Fprintf(w, "HUNK %d %d %d %d %d\n",
                        h.targetLine, h.deletedCount, h.insertedCount, ei, ed)
                for _, op := range h.charOps {
                        var typ string
                        switch op.typ {
                        case opKeep: typ = "keep"
                        case opDelete: typ = "delete"
                        case opInsert: typ = "insert"
                        }
                        fmt.Fprintf(w, "%s %d\n", typ, op.code)
                }
        }
        w.Flush()
        f.Close()
        tWriteEnd := time.Now()

        fmt.Fprintf(os.Stderr, "compute: %.2f ms (read %.2f + diff %.2f + write %.2f)\n",
                float64(tWriteEnd.Sub(tStart).Microseconds())/1000.0,
                float64(tReadEnd.Sub(tReadStart).Microseconds())/1000.0,
                float64(tDiffEnd.Sub(tDiffStart).Microseconds())/1000.0,
                float64(tWriteEnd.Sub(tWriteStart).Microseconds())/1000.0)
        fmt.Fprintf(os.Stderr, "startup: %.2f ms\n",
                float64(tReadStart.Sub(tStart).Microseconds())/1000.0)
        fmt.Fprintf(os.Stderr, "hunks: %d, lines: %d -> %d\n",
                len(hunks), len(oldLines), len(newLines))
}

func semanticBoolToInt(b bool) int {
        if b {
                return 1
        }
        return 0
}
