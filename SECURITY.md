# Security

## Data handled by the plugin

Omarchy OTP stores account labels and TOTP secrets in
`${XDG_CONFIG_HOME:-~/.config}/omarchy-otp/accounts.json`. It does not make
network requests.

The configuration directory is forced to mode `0700` and the account file to
`0600`. Symlinks at either location are rejected. Updates use an atomic
same-directory replacement with a uniquely named temporary file.

Secrets are not encrypted at rest. A process running as the same user, malware,
or an attacker with access to the unlocked account can read them. Use a
hardware-backed authenticator if that threat is in scope.

## Clipboard behavior

Copied OTP codes are cleared after 30 seconds by default. Before clearing, the
helper checks that the clipboard still contains the same code. It never clears
content copied afterward. The timeout can be changed or disabled through the
widget setting `clipboardClearSeconds`.

Other applications running in the Wayland session may be able to read clipboard
content while a code is present.

## Reporting a vulnerability

Please open a private GitHub security advisory rather than a public issue. Do
not include real OTP secrets, generated codes, account exports, or screenshots
containing them.
