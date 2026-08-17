// diffvim-animator — Standalone terminal animation application.
//
// Reads a timed op stream (from diffvim-pace) and animates the
// transformation of an old file into a new file in the terminal.
//
// The animator is a SIMPLE playback engine:
//   - Read op from stream
//   - Apply to virtual buffer
//   - Render to terminal (or skip if --no-display)
//   - Wait the specified delay
//   - Check for user input
//   - Repeat
//
// No diff logic, no pacing decisions, no lookahead. All complex logic
// is done by the compute, postprocess, and pace tools before the
// animator runs.
//
// Usage:
//   diffvim-animator [options] <oldfile>
//   diffvim-animator [options] --no-display <oldfile> --snapshot FILE
//
// Options:
//   --timed-ops FILE   Read timed op stream from FILE (default: stdin)
//   --no-display       Process ops without rendering (for testing)
//   --speed N          Speed multiplier (default: 1.0)
//   --output FILE      Write final buffer to FILE
//   --snapshot FILE    Write buffer to FILE at end of processing
//   --scroll zz|zt|zb|none  Cursor scroll position (default: zz)
//   --help, -h         Show help
package main

import (
        "bufio"
        "fmt"
        "os"
        "strconv"
        "strings"
        "time"
)

// VirtualBuffer represents the file being animated.
type VirtualBuffer struct {
        lines   []string // line content
        cursorL int      // logical cursor line (0-indexed)
        cursorC int      // logical cursor column (0-indexed, can exceed line length)
}

func newBuffer() *VirtualBuffer {
        return &VirtualBuffer{
                lines:   []string{""},
                cursorL: 0,
                cursorC: 0,
        }
}

// LoadFile reads a file into the buffer.
func (b *VirtualBuffer) LoadFile(path string) error {
        data, err := os.ReadFile(path)
        if err != nil {
                return err
        }
        content := string(data)
        // Split into lines (handle \n)
        b.lines = strings.Split(content, "\n")
        // Remove trailing empty line if file ends with \n
        if len(b.lines) > 0 && b.lines[len(b.lines)-1] == "" {
                b.lines = b.lines[:len(b.lines)-1]
        }
        if len(b.lines) == 0 {
                b.lines = []string{""}
        }
        return nil
}

// KeepChar advances the cursor for a kept character.
func (b *VirtualBuffer) KeepChar(code int) {
        if code == 10 { // \n
                b.cursorL++
                if b.cursorL >= len(b.lines) {
                        b.cursorL = len(b.lines) - 1
                }
                b.cursorC = 0
        } else {
                b.cursorC++
        }
}

// DeleteChar removes the character at the cursor position.
func (b *VirtualBuffer) DeleteChar(code int) {
        if code == 10 {
                // Delete newline = join current line with next
                if b.cursorL < len(b.lines)-1 {
                        b.lines[b.cursorL] = b.lines[b.cursorL] + b.lines[b.cursorL+1]
                        b.lines = append(b.lines[:b.cursorL+1], b.lines[b.cursorL+2:]...)
                }
        } else {
                line := b.lines[b.cursorL]
                runes := []rune(line)
                if b.cursorC < len(runes) {
                        newRunes := make([]rune, 0, len(runes)-1)
                        newRunes = append(newRunes, runes[:b.cursorC]...)
                        newRunes = append(newRunes, runes[b.cursorC+1:]...)
                        b.lines[b.cursorL] = string(newRunes)
                }
        }
}

// InsertChar inserts a character at the cursor position and advances.
func (b *VirtualBuffer) InsertChar(code int) {
        ch := rune(code)
        if code == 10 {
                // Insert newline = split current line
                line := b.lines[b.cursorL]
                runes := []rune(line)
                before := string(runes[:b.cursorC])
                after := string(runes[b.cursorC:])
                b.lines[b.cursorL] = before
                // Insert new line after current
                newLines := make([]string, 0, len(b.lines)+1)
                newLines = append(newLines, b.lines[:b.cursorL+1]...)
                newLines = append(newLines, after)
                newLines = append(newLines, b.lines[b.cursorL+1:]...)
                b.lines = newLines
                b.cursorL++
                b.cursorC = 0
        } else {
                line := b.lines[b.cursorL]
                runes := []rune(line)
                // Create a new slice to avoid modifying the original
                newRunes := make([]rune, 0, len(runes)+1)
                newRunes = append(newRunes, runes[:b.cursorC]...)
                newRunes = append(newRunes, ch)
                newRunes = append(newRunes, runes[b.cursorC:]...)
                b.lines[b.cursorL] = string(newRunes)
                b.cursorC++
        }
}

// BatchDelete deletes n chars at the cursor position.
func (b *VirtualBuffer) BatchDelete(n int) {
        line := b.lines[b.cursorL]
        runes := []rune(line)
        end := b.cursorC + n
        if end > len(runes) {
                end = len(runes)
        }
        newRunes := make([]rune, 0, len(runes)-(end-b.cursorC))
        newRunes = append(newRunes, runes[:b.cursorC]...)
        newRunes = append(newRunes, runes[end:]...)
        b.lines[b.cursorL] = string(newRunes)
}

// BatchInsert inserts multiple chars at the cursor position.
func (b *VirtualBuffer) BatchInsert(codes []int) {
        for _, code := range codes {
                b.InsertChar(code)
        }
}

// NewlineDelete deletes the \n (joins with next line).
// When the line is empty, this just removes the empty line.
func (b *VirtualBuffer) NewlineDelete() {
        if b.cursorL < len(b.lines)-1 {
                // Join with next line
                b.lines[b.cursorL] = b.lines[b.cursorL] + b.lines[b.cursorL+1]
                b.lines = append(b.lines[:b.cursorL+1], b.lines[b.cursorL+2:]...)
        }
}

// NewlineInsert splits the line at the cursor.
func (b *VirtualBuffer) NewlineInsert() {
        b.InsertChar(10)
}

// String returns the buffer content as a string.
func (b *VirtualBuffer) String() string {
        return strings.Join(b.lines, "\n") + "\n"
}

// WriteFile writes the buffer to a file.
func (b *VirtualBuffer) WriteFile(path string) error {
        return os.WriteFile(path, []byte(b.String()), 0644)
}

// Render outputs the buffer to the terminal using ANSI escape sequences.
func (b *VirtualBuffer) Render() {
        // Clear screen and move cursor to top-left
        fmt.Print("\033[2J\033[H")

        // Determine visible range (simple: show all lines, or first N)
        maxLines := len(b.lines)
        termLines := 40 // TODO: detect terminal height
        if maxLines > termLines {
                maxLines = termLines
        }

        for i := 0; i < maxLines; i++ {
                line := b.lines[i]
                if i == b.cursorL {
                        // Highlight cursor line
                        cursorCol := b.cursorC
                        runes := []rune(line)
                        before := ""
                        at := " "
                        after := ""
                        if cursorCol < len(runes) {
                                before = string(runes[:cursorCol])
                                at = string(runes[cursorCol])
                                after = string(runes[cursorCol+1:])
                        } else {
                                before = string(runes)
                        }
                        // Render with cursor highlighted (reverse video)
                        fmt.Printf("%s\033[7m%s\033[0m%s\n", before, at, after)
                } else {
                        fmt.Println(line)
                }
        }

        // Position cursor
        fmt.Printf("\033[%d;%dH", b.cursorL+1, b.cursorC+1)
}

// Op represents a parsed timed op stream instruction.
type Op struct {
        Type   string
        Args   []string
}

func parseOpStream(r *bufio.Reader) ([]Op, error) {
        var ops []Op
        for {
                line, err := r.ReadString('\n')
                if err != nil {
                        break
                }
                line = strings.TrimSpace(line)
                if line == "" || strings.HasPrefix(line, "#") {
                        continue
                }
                parts := strings.Fields(line)
                if len(parts) == 0 {
                        continue
                }
                ops = append(ops, Op{Type: parts[0], Args: parts[1:]})
        }
        return ops, nil
}

func main() {
        var timedOpsFile string
        var noDisplay bool
        var speed float64 = 1.0
        var outputFile string
        var snapshotFile string
        var scrollMode = "zz"
        var showHelp bool

        // Simple arg parsing
        args := os.Args[1:]
        var oldFile string
        for i := 0; i < len(args); i++ {
                switch args[i] {
                case "--timed-ops":
                        i++
                        timedOpsFile = args[i]
                case "--no-display":
                        noDisplay = true
                case "--speed":
                        i++
                        speed, _ = strconv.ParseFloat(args[i], 64)
                case "--output":
                        i++
                        outputFile = args[i]
                case "--snapshot":
                        i++
                        snapshotFile = args[i]
                case "--scroll":
                        i++
                        scrollMode = args[i]
                case "--help", "-h":
                        showHelp = true
                default:
                        if !strings.HasPrefix(args[i], "-") {
                                oldFile = args[i]
                        }
                }
        }

        if showHelp {
                fmt.Fprintln(os.Stderr, "diffvim-animator — Standalone terminal animation application")
                fmt.Fprintln(os.Stderr, "")
                fmt.Fprintln(os.Stderr, "Usage: diffvim-animator [options] <oldfile>")
                fmt.Fprintln(os.Stderr, "")
                fmt.Fprintln(os.Stderr, "Options:")
                fmt.Fprintln(os.Stderr, "  --timed-ops FILE   Read timed op stream from FILE (default: stdin)")
                fmt.Fprintln(os.Stderr, "  --no-display       Process ops without rendering (for testing)")
                fmt.Fprintln(os.Stderr, "  --speed N          Speed multiplier (default: 1.0)")
                fmt.Fprintln(os.Stderr, "  --output FILE      Write final buffer to FILE")
                fmt.Fprintln(os.Stderr, "  --snapshot FILE    Write buffer to FILE at end of processing")
                fmt.Fprintln(os.Stderr, "  --scroll zz|zt|zb|none  Cursor scroll position (default: zz)")
                fmt.Fprintln(os.Stderr, "  -h, --help         Show this help")
                os.Exit(0)
        }

        if oldFile == "" {
                fmt.Fprintln(os.Stderr, "Error: oldfile is required")
                os.Exit(1)
        }

        // Load old file into buffer
        buf := newBuffer()
        if err := buf.LoadFile(oldFile); err != nil {
                fmt.Fprintf(os.Stderr, "Error loading %s: %v\n", oldFile, err)
                os.Exit(1)
        }

        // Read timed op stream
        var reader *bufio.Reader
        if timedOpsFile != "" {
                f, err := os.Open(timedOpsFile)
                if err != nil {
                        fmt.Fprintf(os.Stderr, "Error opening %s: %v\n", timedOpsFile, err)
                        os.Exit(1)
                }
                defer f.Close()
                reader = bufio.NewReader(f)
        } else {
                reader = bufio.NewReader(os.Stdin)
        }

        ops, err := parseOpStream(reader)
        if err != nil {
                fmt.Fprintf(os.Stderr, "Error parsing op stream: %v\n", err)
                os.Exit(1)
        }

        // Set up terminal for display mode
        if !noDisplay {
                // Enter raw terminal mode (simplified — no full raw mode for now)
                fmt.Print("\033[?25l") // hide cursor
                defer fmt.Print("\033[?25h\033[0m\033[2J\033[H") // restore on exit
        }
        _ = scrollMode // TODO: implement scroll positioning

        // Process ops
        for _, op := range ops {
                switch op.Type {
                case "op":
                        if len(op.Args) < 2 {
                                continue
                        }
                        opType := op.Args[0]
                        code, _ := strconv.Atoi(op.Args[1])
                        switch opType {
                        case "keep":
                                buf.KeepChar(code)
                        case "delete":
                                buf.DeleteChar(code)
                        case "insert":
                                buf.InsertChar(code)
                        }
                        if !noDisplay {
                                buf.Render()
                        }

                case "delay":
                        if len(op.Args) < 1 {
                                continue
                        }
                        ms, _ := strconv.Atoi(op.Args[0])
                        if speed > 0 {
                                ms = int(float64(ms) / speed)
                        }
                        if ms > 0 {
                                time.Sleep(time.Duration(ms) * time.Millisecond)
                        }

                case "batch_delete":
                        if len(op.Args) < 1 {
                                continue
                        }
                        n, _ := strconv.Atoi(op.Args[0])
                        buf.BatchDelete(n)
                        if !noDisplay {
                                buf.Render()
                        }

                case "batch_insert":
                        codes := make([]int, len(op.Args))
                        for i, arg := range op.Args {
                                codes[i], _ = strconv.Atoi(arg)
                        }
                        buf.BatchInsert(codes)
                        if !noDisplay {
                                buf.Render()
                        }

                case "newline_delete":
                        buf.NewlineDelete()
                        if !noDisplay {
                                buf.Render()
                        }

                case "newline_insert":
                        buf.NewlineInsert()
                        if !noDisplay {
                                buf.Render()
                        }

                case "glide":
                        // For now, just position the cursor
                        if len(op.Args) >= 1 {
                                parts := strings.Split(op.Args[0], ":")
                                if len(parts) == 2 {
                                        l, _ := strconv.Atoi(parts[0])
                                        c, _ := strconv.Atoi(parts[1])
                                        buf.cursorL = l - 1 // 1-indexed to 0-indexed
                                        buf.cursorC = c - 1
                                        if buf.cursorL < 0 {
                                                buf.cursorL = 0
                                        }
                                        if buf.cursorL >= len(buf.lines) {
                                                buf.cursorL = len(buf.lines) - 1
                                        }
                                }
                        }
                        if !noDisplay {
                                buf.Render()
                        }

                case "snapshot":
                        if len(op.Args) >= 1 {
                                if err := buf.WriteFile(op.Args[0]); err != nil {
                                        fmt.Fprintf(os.Stderr, "Error writing snapshot: %v\n", err)
                                }
                        }

                case "hunk_start", "hunk_end", "file_start":
                        // Metadata ops — no buffer action

                case "highlight", "clear_highlight", "dim":
                        // TODO: implement highlighting

                case "pause":
                        // Wait for user input (not implemented in v1)

                case "done":
                        // Animation complete

                default:
                        // Unknown op — ignore
                }
        }

        // Write snapshot if requested
        if snapshotFile != "" {
                if err := buf.WriteFile(snapshotFile); err != nil {
                        fmt.Fprintf(os.Stderr, "Error writing snapshot: %v\n", err)
                }
        }

        // Write output if requested
        if outputFile != "" {
                if err := buf.WriteFile(outputFile); err != nil {
                        fmt.Fprintf(os.Stderr, "Error writing output: %v\n", err)
                }
        }

        if !noDisplay {
                // Leave buffer visible
                fmt.Printf("\nAnimation complete. Buffer has %d lines.\n", len(buf.lines))
        }
}
