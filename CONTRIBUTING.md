# Contributing

Thanks for improving StoryGen! To keep changes clear and reviewable, please follow these rules.

## Always include REASONS for changes
- Every PR must include a "Why (reasons for change)" section explaining:
  - What was broken/missing (symptoms, logs, CI failures)
  - Root cause or most likely cause
  - Why this approach was chosen vs alternatives
- Every commit message should follow this structure:
  - type(scope): short summary
  - Blank line
  - Why: 1–3 lines with the reason/motivation
  - How: 1–3 lines with the approach

Example commit:
```
fix(backend): bind to Cloud Run PORT and upgrade Python base

Why: Revision failed to listen on $PORT; Cloud Run reported container not ready.
How: Switch to python:3.12-slim, set PYTHONUNBUFFERED, use gunicorn JSON CMD, bind :${PORT}.
```

## Development workflow
1. Create a feature/bugfix branch.
2. Write small, focused commits with clear messages (include Why and How).
3. Ensure CI passes (build, lint, tests, smoke tests).
4. Open a PR using the template and fill all sections.

## Code style and quality
- Prefer smallest change that solves the problem.
- Add/adjust tests when public behavior changes.
- Update docs when user-facing behavior or ops steps change.

## Security and secrets
- Do not hardcode secrets. Use Secret Manager or GitHub Secrets.
- Do not include sensitive logs in PRs.

## Questions
Open an issue if you're unsure about scope or approach.
