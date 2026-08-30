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
- No network access during normal OTP generation
- Account storage restricted to the current user
- Direct TOTP import from Bitwarden and Vaultwarden
- Instant account filtering by name or issuer for larger lists
- Optional AES-256-GCM encryption backed by GNOME Keyring
- Stable account IDs and serialized store updates for safe concurrent actions

## Requirements

- A current Omarchy installation with the plugin-based shell
- Python 3.10 or newer
- `wl-copy` and `wl-paste` from `wl-clipboard`
- For encrypted storage: `python-cryptography` and `secret-tool` from `libsecret`

## Install

Once this repository has been pushed to GitHub, install it with:

```bash
omarchy plugin add https://github.com/flathack/omarchy-otp.git --enable
```

Omarchy asks where the widget should be placed. The suggested location is the
right section of the bar.

## Uninstall

Remove the installed plugin with:

```bash
omarchy plugin remove flathack.otp
```

The encrypted account store and its GNOME Keyring key are intentionally kept
so reinstalling the plugin restores access. To remove all local OTP data as a
separate, deliberate step, move the store to the desktop trash first and then
clear its key:

```bash
gio trash "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-otp"
secret-tool clear application omarchy-otp purpose account-store
```

After the key is cleared, any remaining encrypted store or backup is
unrecoverable.

## Usage

- Left-click the key icon to open or close the code list.
- Click an account or select it with the arrow keys and press Enter to copy.
- Press Delete with an account selected, then confirm, to remove it.
- Select the `+` button in the popup, or right-click the key icon, to open the
  account setup in a terminal.
- Middle-click the icon, or press `R` in the popup, to refresh.
- Press Escape to close the popup.
- With more than seven accounts, start typing in the focused filter field to
  narrow the list by account name or issuer. Escape clears the filter.

The CLI is bundled with the plugin. After installation, it can also be called
directly:

```bash
OTP_CLI="$HOME/.config/omarchy/plugins/flathack.otp/bin/omarchy-otp"
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
OTP_CLI="$HOME/.config/omarchy/plugins/flathack.otp/bin/omarchy-otp"
"$OTP_CLI" import-bitwarden
```

The command uses Bitwarden's normal terminal login/unlock prompt, skips
duplicates, creates a mode-`0600` backup, and locks a vault that it unlocked.

## Configuration

Accounts are stored outside the repository in:

```text
${XDG_CONFIG_HOME:-~/.config}/omarchy-otp/accounts.json
```

The directory is set to mode `0700` and the file to `0600`. Plaintext storage
remains available for minimal installations. Version 0.4 automatically assigns
stable UUIDs to older account entries on first use and creates a protected
backup before migrating them. A mode-`0600` lock file serializes updates so
simultaneous panel and CLI actions cannot overwrite each other.

To encrypt the active store and
all existing plugin-created backups with AES-256-GCM, run:

```bash
OTP_CLI="$HOME/.config/omarchy/plugins/flathack.otp/bin/omarchy-otp"
"$OTP_CLI" encrypt-store
```

The randomly generated 256-bit key is stored in GNOME Keyring, not beside the
account file. Future changes and backups preserve the encrypted format. The
keyring normally unlocks with the desktop login. Losing the keyring entry makes
the encrypted account files unrecoverable.

To deliberately return the store and backups to plaintext, run
`"$OTP_CLI" decrypt-store` and confirm the warning.

Copied codes are cleared after 30 seconds by default. The clipboard is only
cleared if it still contains the code, so newer clipboard content is preserved.
Change the timeout with:

```bash
omarchy bar set flathack.otp clipboardClearSeconds 60
```

Set the value to `0` to disable automatic clearing.

## Development

Run the tests and validate the plugin manifest:

```bash
python3 -m unittest discover -s tests -v
omarchy plugin validate .
```

The suite includes store migration and locking tests plus source-level panel
contracts for filtering, keyboard scrolling, confirmed deletion, stable IDs,
and action feedback.

For local development, clone or symlink the repository to
`~/.config/omarchy/plugins/flathack.otp`, then enable the widget:

```bash
omarchy plugin enable flathack.otp --section right
```

Files under the local plugin directory hot-reload when saved.

## Security

The plugin runs locally and never sends account names, secrets, or generated
codes over the network. See [SECURITY.md](SECURITY.md) for the storage and
clipboard threat model.

## Limitations

- TOTP is supported; counter-based HOTP is not.
- Keyring encryption protects files at rest, not against processes running as
  the same user after the desktop keyring has been unlocked.

## License

MIT
