# Omarchy OTP

A native Omarchy bar widget for generating TOTP codes. Open the panel to see
your accounts and click a code to copy it to the Wayland clipboard.

## Features

- Native Omarchy/Quickshell bar widget and popup
- Standard TOTP with SHA-1, SHA-256, and SHA-512
- Six-, seven-, and eight-digit codes with configurable periods
- Manual Base32 secrets and `otpauth://totp/...` URLs
- Mouse and keyboard navigation
- Automatic clipboard clearing without overwriting newer clipboard content
- No network access or third-party Python packages
- Account storage restricted to the current user
- Direct TOTP import from Bitwarden and Vaultwarden
- Instant account filtering by name or issuer for larger lists

## Requirements

- A current Omarchy installation with the plugin-based shell
- Python 3.10 or newer
- `wl-copy` and `wl-paste` from `wl-clipboard`

## Install

Once this repository has been pushed to GitHub, install it with:

```bash
omarchy plugin add https://github.com/flathack/omarchy-otp.git --enable
```

Omarchy asks where the widget should be placed. The suggested location is the
right section of the bar.

## Usage

- Left-click the key icon to open or close the code list.
- Click an account or select it with the arrow keys and press Enter to copy.
- Select the `+` button in the popup, or right-click the key icon, to open the
  account setup in a terminal.
- Middle-click the icon, or press `R` in the popup, to refresh.
- Press Escape to close the popup.
- With more than seven accounts, start typing in the focused filter field to
  narrow the list by account name or issuer. Escape clears the filter.

The CLI is bundled with the plugin. After installation, it can also be called
directly:

```bash
OTP_CLI="$HOME/.config/omarchy/plugins/steven.otp/bin/omarchy-otp"
"$OTP_CLI" add
"$OTP_CLI" show
"$OTP_CLI" remove 0
```

`add` accepts either a Base32 secret or an `otpauth://totp/...` URL. Secret
input is hidden so it does not enter shell history.

To import every TOTP entry from Bitwarden or Vaultwarden without creating an
unencrypted export file, install the official `bitwarden-cli` package, point it
at your server, and run:

```bash
OTP_CLI="$HOME/.config/omarchy/plugins/steven.otp/bin/omarchy-otp"
"$OTP_CLI" import-bitwarden
```

The command uses Bitwarden's normal terminal login/unlock prompt, skips
duplicates, creates a mode-`0600` backup, and locks a vault that it unlocked.

## Configuration

Accounts are stored outside the repository in:

```text
${XDG_CONFIG_HOME:-~/.config}/omarchy-otp/accounts.json
```

The directory is set to mode `0700` and the file to `0600`. The file contains
unencrypted TOTP secrets; anyone with access to your user account can read
them. Do not commit or share this file.

Copied codes are cleared after 30 seconds by default. The clipboard is only
cleared if it still contains the code, so newer clipboard content is preserved.
Change the timeout with:

```bash
omarchy bar set steven.otp clipboardClearSeconds 60
```

Set the value to `0` to disable automatic clearing.

## Development

Run the tests and validate the plugin manifest:

```bash
python3 -m unittest discover -s tests -v
omarchy plugin validate .
```

For local development, clone or symlink the repository to
`~/.config/omarchy/plugins/steven.otp`, then enable the widget:

```bash
omarchy plugin enable steven.otp --section right
```

Files under the local plugin directory hot-reload when saved.

## Security

The plugin runs locally and never sends account names, secrets, or generated
codes over the network. See [SECURITY.md](SECURITY.md) for the storage and
clipboard threat model.

## Limitations

- TOTP is supported; counter-based HOTP is not.
- Secrets are protected by filesystem permissions, not encryption at rest.

## License

MIT
