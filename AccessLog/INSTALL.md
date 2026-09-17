# Access Log — public install

## For end users

1. Open **AccessLog-Installer.dmg** → drag **AccessLog** to **Applications**
2. Open **AccessLog**
3. Setup wizard:
   - **Sign in with Google**
   - **Create a new Access Log sheet** or paste a Sheet link
   - **Run connection test**
4. Keep the app running

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

### Consent screen scopes
- `https://www.googleapis.com/auth/spreadsheets`
- `https://www.googleapis.com/auth/drive.file`
- `https://www.googleapis.com/auth/userinfo.email`
