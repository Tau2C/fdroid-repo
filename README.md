# Personal F-Droid Repository on GitHub Pages

This repository hosts personal Android applications through F-Droid.

## Repository Address

Add this repository URL into the F-Droid app on your device:

```text
https://Tau2C.github.io/fdroid-repo/fdroid/repo
```

## Setup Instructions

### 1. Generate Signing Key

Run the script to create a keystore:

```bash
./scripts/generate-keystore.sh
```

### 2. Configure GitHub Secrets

Encode the keystore file:

```bash
base64 -w 0 keystore.p12
```

Add these secrets in GitHub (`Settings -> Secrets and variables -> Actions`):
- `FDROID_KEYSTORE_BASE64`: Base64 string of `keystore.p12`.
- `FDROID_KEYSTORE_PASSWORD`: Keystore password.
- `FDROID_KEY_PASSWORD`: Key password.

### 3. Enable GitHub Pages

Go to `Settings -> Pages` in your GitHub repository:
- Source: `GitHub Actions`

### 4. Add Applications

1. Place your `.apk` files into the `repo/` directory.
2. Push your changes to the `master` branch.
3. GitHub Actions builds index metadata and publishes the repository.
