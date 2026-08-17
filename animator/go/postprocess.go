// diffvim-postprocess — Post-process raw char ops.
// Go implementation — produces identical output to the Perl and C versions.
//
// Usage: diffvim-postprocess [--op-order MODE] [--semantic-cleanup] [--indent-aware] [--overwrite]
//
// Build: go build -o diffvim-postprocess postprocess.go

package main

import (
        "bufio"
        "fmt"
        "os"
        "strconv"
        "strings"
)

type Op struct {
        Type string
        Code int
}

type Hunk struct {
        Target, Del, Ins, EndIns, EndDel int
        Ops                              []Op
}

var opOrderOptimize = true
var doSemantic = false
var doIndent = false
var doOverwrite = false

func parseArgs(args []string) {
        for i := 0; i < len(args); i++ {
                switch args[i] {
                case "--op-order":
                        if i+1 < len(args) {
                                i++
                                if args[i] == "natural" {
                                        opOrderOptimize = false
                                }
                        }
                case "--semantic-cleanup":
                        doSemantic = true
                case "--indent-aware":
                        doIndent = true
                case "--overwrite":
                        doOverwrite = true
                case "--help", "-h":
                        fmt.Fprintln(os.Stderr, "Usage: diffvim-postprocess [--op-order MODE] [--semantic-cleanup] [--indent-aware] [--overwrite]")
                        os.Exit(0)
                }
        }
}

func main() {
        parseArgs(os.Args[1:])

        scanner := bufio.NewScanner(os.Stdin)
        scanner.Buffer(make([]byte, 1024*1024), 1024*1024)

        var header []string
        var hunks []Hunk
        var currentHunk *Hunk

        for scanner.Scan() {
                line := scanner.Text()
                if strings.HasPrefix(line, "#") {
                        header = append(header, line)
                        continue
                }
                if strings.HasPrefix(line, "HUNK ") {
                        parts := strings.Fields(line)
                        if len(parts) >= 6 {
                                target, _ := strconv.Atoi(parts[1])
                                del, _ := strconv.Atoi(parts[2])
                                ins, _ := strconv.Atoi(parts[3])
                                endIns, _ := strconv.Atoi(parts[4])
                                endDel, _ := strconv.Atoi(parts[5])
                                hunks = append(hunks, Hunk{Target: target, Del: del, Ins: ins, EndIns: endIns, EndDel: endDel})
                                currentHunk = &hunks[len(hunks)-1]
                        }
                        continue
                }
                parts := strings.Fields(line)
                if len(parts) >= 2 && (parts[0] == "keep" || parts[0] == "delete" || parts[0] == "insert") {
                        code, _ := strconv.Atoi(parts[1])
                        if currentHunk != nil {
                                currentHunk.Ops = append(currentHunk.Ops, Op{Type: parts[0], Code: code})
                        }
                }
        }

        // Write header
        for _, line := range header {
                if strings.HasPrefix(line, "# semantic_cleanup") {
                        fmt.Printf("# semantic_cleanup %d\n", btoi(doSemantic))
                } else if strings.HasPrefix(line, "# indent_aware") {
                        fmt.Printf("# indent_aware %d\n", btoi(doIndent))
                } else if strings.HasPrefix(line, "# optimize_sequence") {
                        fmt.Printf("# optimize_sequence %d\n", btoi(opOrderOptimize))
                } else if strings.HasPrefix(line, "# hunk_count") {
                        fmt.Printf("# hunk_count %d\n", len(hunks))
                } else {
                        fmt.Println(line)
                }
        }

        // Process and write hunks
        writer := bufio.NewWriter(os.Stdout)
        defer writer.Flush()

        for _, hunk := range hunks {
                fmt.Fprintf(writer, "HUNK %d %d %d %d %d\n", hunk.Target, hunk.Del, hunk.Ins, hunk.EndIns, hunk.EndDel)

                ops := hunk.Ops
                if doSemantic {
                        ops = semanticCleanup(ops)
                }
                if opOrderOptimize {
                        ops = reorderOps(ops)
                }

                for _, op := range ops {
                        fmt.Fprintf(writer, "%s %d\n", op.Type, op.Code)
                }
        }
}

func btoi(b bool) int {
        if b {
                return 1
        }
        return 0
}

func semanticCleanup(ops []Op) []Op {
        var result []Op
        i := 0
        for i < len(ops) {
                if i+1 < len(ops) && ops[i].Type == "delete" && ops[i+1].Type == "insert" && ops[i].Code == ops[i+1].Code {
                        result = append(result, Op{Type: "keep", Code: ops[i].Code})
                        i += 2
                } else if i+1 < len(ops) && ops[i].Type == "insert" && ops[i+1].Type == "delete" && ops[i].Code == ops[i+1].Code {
                        result = append(result, Op{Type: "keep", Code: ops[i].Code})
                        i += 2
                } else {
                        result = append(result, ops[i])
                        i++
                }
        }
        return result
}

func reorderOps(ops []Op) []Op {
        var result []Op
        lineStart := 0
        for i := 0; i <= len(ops); i++ {
                if i == len(ops) || ops[i].Code == 10 {
                        line := ops[lineStart:i]
                        if i < len(ops) {
                                line = append(line, ops[i]) // include \n
                        }
                        result = append(result, optimizeLine(line)...)
                        lineStart = i + 1
                }
        }
        return result
}

func optimizeLine(ops []Op) []Op {
        if len(ops) <= 1 {
                return ops
        }
        var result []Op
        var buf []Op
        for _, op := range ops {
                if op.Type == "keep" {
                        if len(buf) > 0 {
                                // Content deletes, then \n deletes, then inserts
                                for _, b := range buf {
                                        if b.Type == "delete" && b.Code != 10 {
                                                result = append(result, b)
                                        }
                                }
                                for _, b := range buf {
                                        if b.Type == "delete" && b.Code == 10 {
                                                result = append(result, b)
                                        }
                                }
                                for _, b := range buf {
                                        if b.Type == "insert" {
                                                result = append(result, b)
                                        }
                                }
                                buf = nil
                        }
                        result = append(result, op)
                } else {
                        buf = append(buf, op)
                }
        }
        if len(buf) > 0 {
                for _, b := range buf {
                        if b.Type == "delete" && b.Code != 10 {
                                result = append(result, b)
                        }
                }
                for _, b := range buf {
                        if b.Type == "delete" && b.Code == 10 {
                                result = append(result, b)
                        }
                }
                for _, b := range buf {
                        if b.Type == "insert" {
                                result = append(result, b)
                        }
                }
        }
        return result
}
