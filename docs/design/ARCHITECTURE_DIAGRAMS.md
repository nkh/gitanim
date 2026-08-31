# Architecture Diagrams

## Pipeline Overview

```
┌──────────┐     ┌──────────────┐     ┌──────────┐     ┌──────────┐
│  Compute │ ──> │  Postprocess │ ──> │   Pace   │ ──> │ Animator │
│ (C++     │     │ (C / Perl)   │     │ (C/Perl) │     │(C/Perl/  │
│  Patience│     │ op ordering  │     │ delays + │     │ vim)     │
│  diff)   │     │ positioning  │     │ batching │     │          │
└──────────┘     └──────────────┘     └──────────┘     └──────────┘
     │                 │                   │                  │
     ▼                 ▼                   ▼                  ▼
  raw ops      positioned ops      timed op stream      rendered
  (HUNK/        (TSV with           (TSV with delays    animation
   keep/         per-op              + batch ops)        in terminal
   delete/       line,col)                               or vim
   insert)
```

## Data Flow

```
old.py ──┐
         ├──> ad_compute ──> raw_ops.txt
new.py ──┘                              │
                                         ▼
                              ad_postprocess
                              (--transform, --stream)
                                         │
                                         ▼
                              post_ops.txt (TSV)
                                         │
                                         ▼
                              ad_layer_pace
                              (--delete-pacing word)
                                         │
                                         ▼
                              timed_ops.txt (TSV)
                                         │
                    ┌────────────────────┤
                    ▼                    ▼
           ad      ad_vim (vim)
           (terminal render)       (vim render)
                    │                    │
                    ▼                    ▼
              /tmp/output.txt      vim buffer
```

## Coloring (Parallel)

```
                    ┌─────────────────┐
                    │ ad_colorize│
                    │ (vim/pygmentize)│
                    └────────┬────────┘
                             │
old.py ──────────────────────┼──────> old.colormap
                             │
new.py ──────────────────────┼──────> new.colormap
                             │
                    ┌────────┴────────┐
                    │ ad_pipeline │
                    │ (runs in parallel│
                    │  with coloring)  │
                    └────────┬────────┘
                             │
                             ▼
                    ad
                    --colormap-old old.colormap
                    --colormap-new new.colormap
```

## Timed Op Stream Format (v2 TSV)

```
# timed op stream v2
hunk_start  del_count  ins_count
op          type       line  col  char_code
delay       type       ms
batch_delete line     col   count
batch_insert line     col   code1  code2  ...
newline_delete  line
newline_insert   line  col
hunk_end
done
```
