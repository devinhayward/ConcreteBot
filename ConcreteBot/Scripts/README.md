# ConcreteBot

## November concrete report

This repo includes a one-off script to compile a November mix report from the
"LineItems" tab of the checked ticket spreadsheets.

### Usage

```bash
python Scripts/nov_report.py \
  --input "/Users/devinhayward/Library/CloudStorage/OneDrive-Personal/01-Active ToddGlen Projects/01-Park Properties ToddGlen/600 Lolita Gardens/Estimating/Costs to Complete/Lolita_CostToComplete_Jan_2026/Concrete Tickets/15. Nov 2025/Nov_All_Data" \
  --output "/Users/devinhayward/Library/CloudStorage/OneDrive-Personal/01-Active ToddGlen Projects/01-Park Properties ToddGlen/600 Lolita Gardens/Estimating/Costs to Complete/Lolita_CostToComplete_Jan_2026/Concrete Tickets/15. Nov 2025/Nov_All_Data/Nov_Report.csv"
```

### Notes
- The report is split into **Main Mixes** and **Additional Mixes** sections.
- Main Mixes include only `Item Type = Mix Customer`.
- Additional Mixes include all other `Item Type` values (e.g., Enviro, Super P).
- The mix label comes from the **Item Description** column only.
- Grouping is by Location + Level + Item Description + Qty Unit (and Item Type in the Additional section).
- Rows are sorted by Level first, then Location.
- Total cost uses `Cost` when present; otherwise `Qty Value * Unit Rate`.
- The `Unit Rate` column is the weighted average: `Total Cost / Total Qty`.
