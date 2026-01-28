Regression fixtures live in subfolders here.

Each fixture folder must contain:
- page_text.txt        Raw PDF page text (from the PDF text layer).
- model_response.txt   The raw model response (as returned by the model).
- expected.json        The final expected JSON output.

Optional override files (used by the regression runner if present):
- mix_text.txt            Overrides MIX section text (between MIX and INSTRUCTIONS).
- mix_row_lines.txt       Overrides parsed MIX row lines.
- mix_parsed_hints.txt    Overrides derived mix hints (Row 1/2/3 blocks).
- extra_charges_text.txt  Overrides EXTRA CHARGES section text.

To generate the override files from a PDF:
- concretebot prompt-overrides --pdf <path> --pages <range> --out <fixture-dir>

Example layout:
Fixtures/
  95820135/
    page_text.txt
    model_response.txt
    expected.json