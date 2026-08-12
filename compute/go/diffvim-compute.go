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

func main() {
	tStart := time.Now()

	algorithm := os.Getenv("DIFFVIM_ALGORITHM")
	if algorithm == "" {
		algorithm = "lcs"
	}
	doSemantic := strings.HasPrefix(os.Getenv("DIFFVIM_SEMANTIC_CLEANUP"), "1")

	/* Parse args: <oldfile> <newfile> <outputfile> [--algorithm X] [--semantic-cleanup] */
	var oldfile, newfile, outfile string
	for i := 1; i < len(os.Args); i++ {
		if os.Args[i] == "--algorithm" && i+1 < len(os.Args) {
			algorithm = os.Args[i+1]
			i++
		} else if os.Args[i] == "--semantic-cleanup" {
			doSemantic = true
		} else if oldfile == "" {
			oldfile = os.Args[i]
		} else if newfile == "" {
			newfile = os.Args[i]
		} else if outfile == "" {
			outfile = os.Args[i]
		}
	}
	if oldfile == "" || newfile == "" || outfile == "" {
		fmt.Fprintf(os.Stderr, "Usage: %s <oldfile> <newfile> <outputfile> [--algorithm lcs|myers|patience] [--semantic-cleanup]\n", os.Args[0])
		os.Exit(1)
	}

	tReadStart := time.Now()
	oldLines := readLines(oldfile)
	newLines := readLines(newfile)
	tReadEnd := time.Now()

	if len(oldLines) == 0 && len(newLines) == 0 {
		fmt.Fprintln(os.Stderr, "Error: both files empty or unreadable")
		os.Exit(1)
	}

	tDiffStart := time.Now()
	lops := computeLineDiff(oldLines, newLines, algorithm)

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
		h.charOps = charDiff(ot, nt)
		if doSemantic {
			h.charOps = semanticCleanup(h.charOps)
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
