# Security

## Data handled by the plugin

Omarchy OTP stores account labels and TOTP secrets in
`${XDG_CONFIG_HOME:-~/.config}/omarchy-otp/accounts.json`. It does not make
network requests.

The configuration directory is forced to mode `0700` and the account file to
`0600`. Symlinks at either location are rejected. Updates use an atomic
same-directory replacement with a uniquely named temporary file.

The optional Bitwarden/Vaultwarden importer reads decrypted items directly
from the official `bw` CLI into memory. It does not create a vault export on
disk, passes the session through the child-process environment instead of the
command line, and clears that environment after the import. The account-store
backup created before an import is restricted to mode `0600` and preserves the
active store's encrypted or plaintext format.

Encrypted storage uses AES-256-GCM with a fresh 96-bit nonce for every write and
authenticated format metadata. Its random 256-bit key is stored in GNOME
Keyring through Secret Service. The key is never placed in the account file or
on a child-process command line. Migration performs an in-memory decrypt
self-check before atomically replacing each plaintext file.

This protects account files and their backups at rest. Once the desktop keyring
is unlocked, a process running as the same user may be able to request the key;
it does not protect a compromised logged-in session. Losing the keyring entry
makes the encrypted files unrecoverable. Use a hardware-backed authenticator if
either threat is in scope.

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
