"""Post a Gemini code review for the current pull request diff.

Reads the PR diff, asks Gemini to review it, and writes the review to the
path given by REVIEW_OUTPUT. The workflow posts that file as a PR comment.
"""

import os
import subprocess
import sys

from google import genai
from google.genai import errors, types

# Paths that add diff noise without adding review value.
EXCLUDED = [
    ":(exclude)*.pbxproj",
    ":(exclude)*.xcworkspacedata",
    ":(exclude)Package.resolved",
    ":(exclude)*.lock",
    ":(exclude)*.svg",
]

PROMPT = """You are reviewing a pull request diff for an iOS expense tracker
written in Swift/SwiftUI.

Focus on, in order:
1. Security issues (injection, auth flaws, unsafe deserialization, secrets in code)
2. Bugs and edge cases (nil handling, concurrency, off-by-one, silent failures)
3. Code quality and maintainability

Rules:
- Only report problems you can point at in the diff. Do not speculate about
  code you cannot see, and do not restate what the change does.
- Prefix each finding with a severity: **Critical**, **High**, **Medium**, **Low**.
- Give the file and, where you can, the line.
- Skip style nitpicks that a formatter would catch.
- If you find nothing worth raising, reply with exactly: No issues found.

Diff:
```diff
{diff}
```
"""


def run(*args: str) -> str:
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"command failed: {' '.join(args)}\n{result.stderr}")
    return result.stdout


def get_diff(base_sha: str, head_sha: str, max_chars: int) -> str:
    diff = run("git", "diff", "-M", f"{base_sha}...{head_sha}", "--", ".", *EXCLUDED)
    if len(diff) > max_chars:
        diff = diff[:max_chars] + "\n\n[diff truncated: PR exceeds the review size limit]"
    return diff


def main() -> None:
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        sys.exit("GEMINI_API_KEY is empty. Check the repo's Actions secrets.")

    output_path = os.environ.get("REVIEW_OUTPUT", "review_output.md")
    diff = get_diff(
        os.environ["BASE_SHA"],
        os.environ["HEAD_SHA"],
        int(os.environ.get("MAX_DIFF_CHARS", "400000")),
    )

    if not diff.strip():
        print("No reviewable changes in this diff.")
        return

    client = genai.Client(
        api_key=api_key,
        http_options=types.HttpOptions(
            timeout=180_000,  # milliseconds
            retry_options=types.HttpRetryOptions(
                attempts=5,
                initial_delay=2.0,
                max_delay=30.0,
                exp_base=2.0,
                jitter=1.0,
                # 429 quota, 500/502/503/504 capacity and gateway failures.
                http_status_codes=[429, 500, 502, 503, 504],
            ),
        ),
    )

    models = [
        m.strip()
        for m in os.environ.get("GEMINI_MODELS", "gemini-3.7-flash,gemini-3.6-flash").split(",")
        if m.strip()
    ]

    # The newest Flash model sheds load under demand spikes, and retrying the
    # same model does not help once a spike outlasts the backoff window. Fall
    # through to an older, less contended model rather than skipping the review.
    review = ""
    for index, model in enumerate(models):
        try:
            response = client.models.generate_content(
                model=model,
                contents=PROMPT.format(diff=diff),
                config=types.GenerateContentConfig(temperature=0.0),
            )
        except errors.ServerError as exc:
            print(f"{model} unavailable after retries: {exc}", file=sys.stderr)
            if index == len(models) - 1:
                sys.exit("Every configured model was unavailable.")
            continue

        review = (response.text or "").strip()
        if review:
            print(f"Reviewed with {model}.")
            break
        print(f"{model} returned an empty review.", file=sys.stderr)

    if not review:
        sys.exit("No model produced a review.")

    with open(output_path, "w") as f:
        f.write(review)
    print(f"Review written to {output_path} ({len(review)} chars).")


if __name__ == "__main__":
    main()
