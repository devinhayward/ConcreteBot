# ConcreteBot

ConcreteBot extracts JSON data from concrete ticket PDFs using the Apple Foundation Models framework. It splits PDF input by page and processes one page at a time.

## Setup

- macOS 26+ with Apple Intelligence enabled.

## Run

```
swift run ConcreteBot extract --pdf /path/to/tickets.pdf --pages 2-23 --out /path/to/output
```

ConcreteBot reads each page in the range and sends it to the system model for extraction. Output files are written as `ticket-<Ticket No.>.json` in the `--out` directory.

Phase 4 extraction options:
- `--model-mode auto|guided|legacy`
- `--prompt-variant adaptive|compact|minimal|none` (default `adaptive`: starts minimal and escalates to compact before repair when needed)
- `--run-report /path/to/report.json` (per-page telemetry, including Foundation Models runtime metadata such as OS/model line and context window when available)
- In `auto` mode, if guided generation only fails validation on `Mix Additional 1/2` quantity or slump fields, ConcreteBot automatically retries that page with `legacy` + `compact` before falling through to repair.
- Repair prompts now include focused field evidence derived from the page text, mix-row extraction, parsed mix hints, and indexed extra-charge rows for the specific validation paths being corrected.
- Repair sessions also expose Foundation Models tools for `getMixRow`, `getChargeRow`, and `lookupFieldEvidence`, and `--run-report` now records tool-call counts and tool names when the model uses them.

Foundation Models note:
- Apple documents a model split between `26.0-26.3` and `26.4+`. If extraction quality shifts after OS updates, compare `--run-report` output across runs and version prompt templates accordingly.

## Manual workflow

1. Print prompts (one per page) and run them in any model UI:
   ```
   swift run ConcreteBot extract --pdf /path/to/tickets.pdf --pages 2-23 --print-prompt
   ```
2. Save the JSON response(s) to a file (or pipe them in) and write outputs:
   ```
   swift run ConcreteBot extract --pdf /path/to/tickets.pdf --pages 2-23 --out /path/to/output --response-file /path/to/response.txt
   ```

Batch mode:
- concretebot batch --csv <path> [--pages <range|auto>] [--out <dir>] [--print-prompt]

CSV format (one row per PDF):
- Column 1: pdf path (required)
- Column 2: pages (optional; overrides --pages for that row)
- Header row is optional (accepted headers: pdf,pdf_path,path,file + optional pages column)
- Blank lines and lines starting with # are ignored

Example CSV:
pdf,pages
/path/to/ticket-1.pdf,1-2
/path/to/ticket-2.pdf

example - swift run ConcreteBot batch --csv /path/to/csvfile.csv --pages auto --out /path/to/out directory

Evaluation matrix (fixtures):
```
swift run ConcreteBot evaluate --fixtures Tests/ConcreteBotTests/Fixtures
```
Optional filters:
- `--model-modes auto,guided,legacy`
- `--prompt-variants adaptive,compact,minimal,none`
- `--out /path/to/evaluate_report.txt`
