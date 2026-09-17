# Access Log (macOS)

Native Mac app: after login/unlock, collect **Name** + **Purpose**, store in SQLite, sync to the user’s Google Sheet via **Sign in with Google**.

## Security — before you push / clone

**Never commit:**
- `AccessLog/Resources/GoogleOAuth.json` (real OAuth client secret)
- `client_secret*.json`
- `quega-dev*.json` / service-account keys
- `credentials.json`

These are listed in `.gitignore`.

If those files were ever shared or committed, **rotate** the OAuth client secret and service-account key in Google Cloud.

### Local OAuth setup (required to build/run)

```bash
cp AccessLog/Resources/GoogleOAuth.example.json AccessLog/Resources/GoogleOAuth.json
# Edit GoogleOAuth.json with your Desktop OAuth client_id + client_secret
```

## Run from Xcode

1. Open `AccessLog.xcodeproj`
2. Ensure `GoogleOAuth.json` exists (see above)
3. Run (⌘R)
4. Complete the setup wizard (Sign in with Google → sheet → test)

## Public installer

```bash
./scripts/build-installer.sh
```

Creates `build/AccessLog-Installer.dmg` (gitignored).

See [INSTALL.md](INSTALL.md) for end-user steps.
