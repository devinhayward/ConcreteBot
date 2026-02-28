Regression fixtures live in subfolders here.

Each fixture folder must contain:
- page_text.txt        Raw PDF page text (from the PDF text layer).
- model_response.txt   The raw model response (as returned by the model).
- expected.json        The final expected JSON output.

Example layout:
Fixtures/
  95820135/
    page_text.txt
    model_response.txt
    expected.json
