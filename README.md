# ConcreteBot

ConcreteBot extracts JSON data from concrete ticket PDFs using the Apple Foundation Models framework. It splits PDF input by page and processes one page at a time.

## Setup

- macOS 26+ with Apple Intelligence enabled.

## Run

```
swift run ConcreteBot extract --pdf /path/to/tickets.pdf --pages 2-23 --out /path/to/output
```

ConcreteBot reads each page in the range and sends it to the system model for extraction. Output files are written as `ticket-<Ticket No.>.json` in the `--out` directory.

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