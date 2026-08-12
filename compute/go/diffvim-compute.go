// diffvim-compute.go — External diff computer for diffvim (Go version).
//
// Reads two files, computes line-level + char-level LCS diff, and writes
// the result in a format that `diffvim --precomputed FILE` can consume.
//
// Build: make go
// Usage: diffvim-compute-go <oldfile> <newfile> <outputfile>
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
        targetLine   int
        deletedCount int
        insertedCount int
        isEndInsert  bool
        isEndDelete  bool
        charOps      []charOp
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

func lineDiff(a, b []string) []lineOp {
        na, nb := len(a), len(b)
        dp := make([][]int, na+1)
        for i := range dp {
                dp[i] = make([]int, nb+1)
        }
        for i := 1; i <= na; i++ {
                for j := 1; j <= nb; j++ {
                        if a[i-1] == b[j-1] {
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
                if i > 0 && j > 0 && a[i-1] == b[j-1] {
                        ops = append(ops, lineOp{opKeep, i - 1, j - 1})
                        i--; j--
                } else if j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j]) {
                        ops = append(ops, lineOp{opInsert, 0, j - 1})
                        j--
                } else {
                        ops = append(ops, lineOp{opDelete, i - 1, 0})
                        i--
                }
        }
        // Reverse
        for k, l := 0, len(ops)-1; k < l; k, l = k+1, l-1 {
                ops[k], ops[l] = ops[l], ops[k]
        }
        return ops
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

func main() {
        tStart := time.Now()
        if len(os.Args) != 4 {
                fmt.Fprintf(os.Stderr, "Usage: %s <oldfile> <newfile> <outputfile>\n", os.Args[0])
                os.Exit(1)
        }

        tReadStart := time.Now()
        oldLines := readLines(os.Args[1])
        newLines := readLines(os.Args[2])
        tReadEnd := time.Now()

        tDiffStart := time.Now()
        lops := lineDiff(oldLines, newLines)

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
                hunks = append(hunks, h)
        }
        tDiffEnd := time.Now()

        tWriteStart := time.Now()
        f, err := os.Create(os.Args[3])
        if err != nil {
                fmt.Fprintf(os.Stderr, "Cannot write %s: %v\n", os.Args[3], err)
                os.Exit(1)
        }
        w := bufio.NewWriter(f)
        fmt.Fprintln(w, "# diffvim precomputed diff v1")
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
