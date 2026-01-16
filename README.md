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
