#!/usr/bin/env python3
"""Build a combined floor report from monthly concrete report CSVs."""

import argparse
import csv
import re
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Tuple


DEFAULT_INPUT_DIR = Path(
    "/Users/devinhayward/Library/CloudStorage/OneDrive-Personal/"
    "01-Active ToddGlen Projects/01-Park Properties ToddGlen/"
    "600 Lolita Gardens/Estimating/Costs to Complete/"
    "Lolita_CostToComplete_Feb_2026/Concrete Tickets/Combined Reports_Mar172026"
)

SECTION_HEADERS = {
    "Main Mixes": [
        "Source Report",
        "Level",
        "Location",
        "Item Type",
        "Mix Description",
        "Ticket Count",
        "Total Qty",
        "Qty Unit",
        "Unit Rate",
        "Total Cost",
    ],
    "Additional Mixes": [
        "Source Report",
        "Level",
        "Location",
        "Item Type",
        "Mix Description",
        "Ticket Count",
        "Total Qty",
        "Qty Unit",
        "Unit Rate",
        "Total Cost",
    ],
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create a floor report from monthly concrete report CSVs."
    )
    parser.add_argument(
        "--input-dir",
        default=str(DEFAULT_INPUT_DIR),
        help="Directory containing monthly report CSVs and floor reports.",
    )
    parser.add_argument(
        "--level",
        required=True,
        help="Level to extract, for example 14 or P4.",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Output CSV path. Defaults to <input-dir>/<level>th_Floor_Report.csv for numeric levels.",
    )
    return parser.parse_args()


def month_sort_key(path: Path) -> Tuple[int, int, str]:
    match = re.search(r"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*[_-]?(\d{4})", path.name)
    if not match:
        return (9999, 99, path.name)
    month_name, year_text = match.groups()
    month_order = {
        "Jan": 1,
        "Feb": 2,
        "Mar": 3,
        "Apr": 4,
        "May": 5,
        "Jun": 6,
        "Jul": 7,
        "Aug": 8,
        "Sep": 9,
        "Oct": 10,
        "Nov": 11,
        "Dec": 12,
    }
    return (int(year_text), month_order[month_name], path.name)


def parse_number(value: str) -> float:
    stripped = (value or "").strip().replace(",", "")
    return float(stripped) if stripped else 0.0


def format_number(value: float) -> str:
    return f"{value:.2f}"


def output_name_for_level(level: str) -> str:
    if level.isdigit():
        suffix = "th"
        if not 10 <= (int(level) % 100) <= 20:
            suffix = {1: "st", 2: "nd", 3: "rd"}.get(int(level) % 10, "th")
        return f"{level}{suffix}_Floor_Report.csv"
    return f"{level}_Floor_Report.csv"


def parse_report(path: Path) -> Dict[str, List[List[str]]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.reader(handle))

    sections: Dict[str, List[List[str]]] = {"Main Mixes": [], "Additional Mixes": []}
    current_section = None

    for row in rows:
        if row == ["Main Mixes"]:
            current_section = "Main Mixes"
            continue
        if row == ["Additional Mixes"]:
            current_section = "Additional Mixes"
            continue
        if not row or current_section is None:
            continue
        if row[0] in ("Level", "Source Report", "Summary Totals", "Section", "All Sections"):
            continue
        sections[current_section].append(row)

    return sections


def source_reports(input_dir: Path) -> List[Path]:
    reports = []
    for path in input_dir.glob("*.csv"):
        if "_Floor_Report" in path.name:
            continue
        reports.append(path)
    return sorted(reports, key=month_sort_key)


def build_floor_report(input_dir: Path, level: str) -> List[List[str]]:
    level_text = str(level).strip()
    section_rows: Dict[str, List[List[str]]] = {"Main Mixes": [], "Additional Mixes": []}
    section_summaries: Dict[str, Dict[str, Dict[str, float]]] = {
        "Main Mixes": defaultdict(lambda: {"line_items": 0, "ticket_count": 0, "total_qty": 0.0, "total_cost": 0.0}),
        "Additional Mixes": defaultdict(lambda: {"line_items": 0, "ticket_count": 0, "total_qty": 0.0, "total_cost": 0.0}),
    }

    for report_path in source_reports(input_dir):
        parsed = parse_report(report_path)
        for section_name in ("Main Mixes", "Additional Mixes"):
            for row in parsed[section_name]:
                if len(row) < 9 or row[0].strip() != level_text:
                    continue
                out_row = [report_path.name] + row[:9]
                section_rows[section_name].append(out_row)
                summary = section_summaries[section_name][report_path.name]
                summary["line_items"] += 1
                summary["ticket_count"] += int(parse_number(row[4]))
                summary["total_qty"] += parse_number(row[5])
                summary["total_cost"] += parse_number(row[8])

    all_line_items = 0
    all_ticket_count = 0
    all_total_qty = 0.0
    all_total_cost = 0.0

    level_title = f"{level_text}th Floor Report" if level_text.isdigit() else f"{level_text} Floor Report"
    output_rows: List[List[str]] = [[level_title], []]

    for section_name in ("Main Mixes", "Additional Mixes"):
        output_rows.append([section_name])
        output_rows.append(SECTION_HEADERS[section_name])
        output_rows.extend(section_rows[section_name])
        output_rows.append([])

    output_rows.append(["Summary Totals"])
    output_rows.append(["Section", "Source Report", "Line Items", "Ticket Count", "Total Qty", "Total Cost"])

    for section_name in ("Main Mixes", "Additional Mixes"):
        for report_name, summary in section_summaries[section_name].items():
            output_rows.append([
                section_name,
                report_name,
                str(int(summary["line_items"])),
                str(int(summary["ticket_count"])),
                format_number(summary["total_qty"]),
                format_number(summary["total_cost"]),
            ])
            all_line_items += int(summary["line_items"])
            all_ticket_count += int(summary["ticket_count"])
            all_total_qty += summary["total_qty"]
            all_total_cost += summary["total_cost"]

    output_rows.append([
        "All Sections",
        "All Reports",
        str(all_line_items),
        str(all_ticket_count),
        format_number(all_total_qty),
        format_number(all_total_cost),
    ])

    return output_rows


def write_csv(path: Path, rows: List[List[str]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerows(rows)


def main() -> int:
    args = parse_args()
    input_dir = Path(args.input_dir).expanduser()
    output_path = Path(args.output).expanduser() if args.output else input_dir / output_name_for_level(args.level)

    if not input_dir.is_dir():
        raise SystemExit(f"Input directory not found: {input_dir}")

    rows = build_floor_report(input_dir, args.level)
    write_csv(output_path, rows)
    print(f"Report written to: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
