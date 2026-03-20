#!/usr/bin/env python3

import json
import re
import sys
import unicodedata
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import pdfplumber


STOPWORDS = {
    "a",
    "an",
    "and",
    "at",
    "by",
    "for",
    "in",
    "of",
    "on",
    "or",
    "the",
    "to",
}


def normalize(text: str) -> str:
    text = unicodedata.normalize("NFKD", text or "").replace("³", "3")
    text = text.lower()
    text = re.sub(r"[^a-z0-9#+/.-]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def collapse_doubled_runs(text: str) -> str:
    collapsed: List[str] = []
    index = 0
    while index < len(text):
        next_index = index + 1
        while next_index < len(text) and text[next_index] == text[index]:
            next_index += 1
        run_length = next_index - index
        if run_length >= 2 and run_length % 2 == 0:
            collapsed.append(text[index] * (run_length // 2))
        else:
            collapsed.append(text[index] * run_length)
        index = next_index
    return "".join(collapsed)


def significant_tokens(text: str) -> List[str]:
    tokens: List[str] = []
    for token in normalize(text).split():
        if len(token) == 1:
            continue
        if token in STOPWORDS:
            continue
        tokens.append(token)
    return tokens


def value_matches_page(value: Optional[str], page_text: str, *, min_ratio: float = 1.0) -> bool:
    if value is None:
        return True
    normalized_value = normalize(value)
    if not normalized_value:
        return True
    normalized_page = normalize(page_text)
    if normalized_value in normalized_page:
        return True

    tokens = significant_tokens(value)
    if not tokens:
        return True
    hits = sum(1 for token in tokens if token in normalized_page)
    return (hits / len(tokens)) >= min_ratio


def compare_mix_row(name: str, row: Optional[dict], page_text: str, errors: List[str]) -> None:
    if not row:
        return
    for key in ("Qty", "Code", "Slump"):
        value = row.get(key)
        if value and not value_matches_page(value, page_text):
            errors.append(f"{name}.{key} not found in source PDF text: {value}")

    for key in ("Cust. Descr.", "Description"):
        value = row.get(key)
        if value and not value_matches_page(value, page_text, min_ratio=0.75):
            errors.append(f"{name}.{key} does not align with source PDF text: {value}")


def collect_pages(folder: Path) -> List[dict]:
    pages: List[dict] = []
    for pdf_path in sorted(folder.glob("*.pdf")):
        with pdfplumber.open(pdf_path) as pdf:
            for page_index, page in enumerate(pdf.pages, start=1):
                raw_text = page.extract_text() or ""
                collapsed_text = collapse_doubled_runs(raw_text)
                pages.append(
                    {
                        "pdf": pdf_path,
                        "page": page_index,
                        "raw_text": raw_text,
                        "collapsed_text": collapsed_text,
                    }
                )
    return pages


def page_score(page_entry: dict) -> int:
    text = normalize(page_entry["raw_text"] + "\n" + page_entry["collapsed_text"])
    score = 0
    if "ticket no" in text:
        score += 4
    if "delivery date" in text:
        score += 2
    if "delivery addr" in text:
        score += 2
    if "mix" in text:
        score += 1
    return score


def find_page_for_ticket(ticket_number: str, pages: List[dict]) -> Optional[dict]:
    candidates: List[dict] = []
    for page_entry in pages:
        combined = normalize(page_entry["raw_text"] + "\n" + page_entry["collapsed_text"])
        if ticket_number in combined:
            candidates.append(page_entry)

    if not candidates:
        return None

    candidates.sort(
        key=lambda entry: (page_score(entry), -entry["page"]),
        reverse=True,
    )
    return candidates[0]


def audit_folder(folder: Path) -> List[str]:
    messages: List[str] = [f"[{folder.name}]"]
    pages = collect_pages(folder)

    json_by_ticket: Dict[str, Path] = {}
    for json_path in sorted(folder.glob("ticket-*.json")):
        try:
            payload = json.loads(json_path.read_text(encoding="utf-8"))
        except Exception as exc:
            messages.append(f"Unreadable JSON {json_path.name}: {exc}")
            continue
        ticket_number = str(payload.get("Ticket No.") or "").strip()
        if not ticket_number:
            messages.append(f"{json_path.name}: missing Ticket No.")
            continue
        json_by_ticket[ticket_number] = json_path

    for ticket_number in sorted(json_by_ticket):
        page_entry = find_page_for_ticket(ticket_number, pages)
        if page_entry is None:
            messages.append(f"No matching PDF page found for ticket {ticket_number}: {json_by_ticket[ticket_number].name}")
            continue
        page_text = page_entry["raw_text"] + "\n" + page_entry["collapsed_text"]
        json_path = json_by_ticket[ticket_number]
        payload = json.loads(json_path.read_text(encoding="utf-8"))

        ticket_errors: List[str] = []
        if str(payload.get("Ticket No.") or "").strip() != ticket_number:
            ticket_errors.append(
                f"Ticket No. mismatch: JSON={payload.get('Ticket No.')} PDF={ticket_number}"
            )

        for key in ("Delivery Date", "Delivery Time"):
            value = payload.get(key)
            if value and not value_matches_page(value, page_text):
                ticket_errors.append(f"{key} not found in source PDF text: {value}")

        address = payload.get("Delivery Address")
        if address and not value_matches_page(address, page_text, min_ratio=0.8):
            ticket_errors.append(f"Delivery Address does not align with source PDF text: {address}")

        compare_mix_row("Mix Customer", payload.get("Mix Customer"), page_text, ticket_errors)
        compare_mix_row("Mix Additional 1", payload.get("Mix Additional 1"), page_text, ticket_errors)
        compare_mix_row("Mix Additional 2", payload.get("Mix Additional 2"), page_text, ticket_errors)

        for index, charge in enumerate(payload.get("Extra Charges") or [], start=1):
            description = charge.get("Description")
            qty = charge.get("Qty")
            if description and not value_matches_page(description, page_text, min_ratio=0.8):
                ticket_errors.append(
                    f"Extra Charges[{index}].Description does not align with source PDF text: {description}"
                )
            if qty and not value_matches_page(qty, page_text):
                ticket_errors.append(f"Extra Charges[{index}].Qty not found in source PDF text: {qty}")

        if ticket_errors:
            messages.append(
                f"Ticket {ticket_number} from {page_entry['pdf'].name} page {page_entry['page']}:"
            )
            messages.extend(f"  - {error}" for error in ticket_errors)

    if len(messages) == 1:
        messages.append("No issues found.")

    return messages


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/Users/devinhayward/Desktop/Output")
    folders = sorted(
        path
        for path in root.iterdir()
        if path.is_dir() and (any(path.glob("*.pdf")) or any(path.glob("ticket-*.json")))
    )

    report_sections = []
    for folder in folders:
        report_sections.append("\n".join(audit_folder(folder)))

    report = "\n\n".join(report_sections).rstrip() + "\n"
    sys.stdout.write(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
