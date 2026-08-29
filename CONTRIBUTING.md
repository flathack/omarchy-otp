# Contributing

Contributions are welcome. Keep changes focused and avoid adding network access
or third-party runtime dependencies without explaining the security impact.

Before opening a pull request, run:

```bash
python3 -m unittest discover -s tests -v
omarchy plugin validate .
```

Never add real TOTP secrets or account files to fixtures, screenshots, issues,
or commits. RFC 6238 public test vectors are safe to use in automated tests.
