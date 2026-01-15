# ConcreteBot

ConcreteBot extracts JSON data from concrete ticket PDFs via the ChatGPT web UI.

## Setup

1. Install Playwright dependencies in this repo:
   ```
   npm install
   ```
2. Ensure you can log into https://chatgpt.com in a browser.

## Run

First run in non-headless mode so you can log in and grant file upload permissions:

```
swift run ConcreteBot extract --pdf /path/to/tickets.pdf --pages 2-23 --out /path/to/output --profile ~/.concretebot/playwright
```

If you hit login challenges, run with a real browser channel and manual login:

```
swift run ConcreteBot extract --pdf /path/to/tickets.pdf --pages 2-23 --out /path/to/output --profile ~/.concretebot/playwright --channel chrome --manual-login
```

Manual workflow (use this if UI automation is blocked):

1. Print the prompt and run it in your normal browser UI.
   ```
   swift run ConcreteBot extract --pdf /path/to/tickets.pdf --pages 2-23 --print-prompt
   ```
2. Save the JSON response to a file (or pipe it in) and write outputs:
   ```
   swift run ConcreteBot extract --pdf /path/to/tickets.pdf --pages 2-23 --out /path/to/output --response-file /path/to/response.txt
   ```

Subsequent runs can add `--headless` if desired:

```
swift run ConcreteBot extract --pdf /path/to/tickets.pdf --pages 2-23 --out /path/to/output --profile ~/.concretebot/playwright --headless
```

Output files are written as `ticket-<Ticket No.>.json` in the `--out` directory.
