# Access Log — public install

## Recommended: terminal install (avoids Gatekeeper “malware” dialog)

Unsigned builds show Apple’s warning when opened from a DMG download.  
A terminal install clears the quarantine flag after copying to Applications:

```bash
curl -fsSL https://raw.githubusercontent.com/7AkhilV/Mac-Access-Log/main/AccessLog/scripts/install.sh | zsh
```

Or with a local DMG:

```bash
chmod +x AccessLog/scripts/install.sh
./AccessLog/scripts/install.sh ~/Downloads/AccessLog-Installer.dmg
```

Then finish the setup wizard (Sign in with Google → sheet → test).

> Only use this script from a source you trust. Clearing quarantine skips Apple’s download check.

---

## Alternative: DMG (shows Gatekeeper warning)

1. Download **AccessLog-Installer.dmg** from [Releases](https://github.com/7AkhilV/Mac-Access-Log/releases)
2. Open it → drag **AccessLog** to **Applications**
3. First launch: **right-click → Open** (or System Settings → Privacy & Security → Open Anyway)
4. Setup wizard → keep the app running

Re-run setup: **Access Log → Run Setup Wizard…**

---

## For publishers / developers

### Secrets (do not commit)

```bash
cp AccessLog/Resources/GoogleOAuth.example.json AccessLog/Resources/GoogleOAuth.json
```

Fill in your Desktop OAuth `client_id` and `client_secret`.  
`GoogleOAuth.json` is gitignored.

### Build installer

```bash
./scripts/build-installer.sh
```

Upload the DMG to a GitHub Release. Users can then use `install.sh` above.

### Consent screen scopes
- `https://www.googleapis.com/auth/spreadsheets`
- `https://www.googleapis.com/auth/drive.file`
- `https://www.googleapis.com/auth/userinfo.email`
