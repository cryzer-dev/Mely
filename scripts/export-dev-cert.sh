#!/bin/zsh
# Exports only the "Mely Dev" signing identity (certificate + private key) as a .p12 for the
# release CI, so CI-built updates keep the same signature and macOS keeps Mely's permissions.
# Usage: scripts/export-dev-cert.sh <out.p12>   prints the password to stdout.
# Keep the file out of the repo (*.p12 is ignored) and delete it once the secrets are set.
# macOS asks once to allow the export from the login keychain.
set -euo pipefail
OUT=${1:?usage: export-dev-cert.sh <out.p12>}
PASS=$(uuidgen)
SCRIPT=$(mktemp -t export-identity).swift
trap 'rm -f "$SCRIPT"' EXIT
cat > "$SCRIPT" <<'SWIFT'
import Foundation
import Security
let args = CommandLine.arguments
let query: [String: Any] = [kSecClass as String: kSecClassIdentity, kSecMatchLimit as String: kSecMatchLimitAll,
                            kSecReturnRef as String: true]
var result: CFTypeRef?
guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let all = result as? [SecIdentity] else {
    FileHandle.standardError.write(Data("No identities\n".utf8)); exit(1)
}
let mine = all.first { identity in
    var cert: SecCertificate?
    SecIdentityCopyCertificate(identity, &cert)
    return cert.flatMap { SecCertificateCopySubjectSummary($0) as String? } == "Mely Dev"
}
guard let identity = mine else { FileHandle.standardError.write(Data("No “Mely Dev” identity\n".utf8)); exit(1) }
var params = SecItemImportExportKeyParameters()
params.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
params.passphrase = Unmanaged.passUnretained(args[2] as CFString)
var data: CFData?
let status = SecItemExport(identity, .formatPKCS12, [], &params, &data)
guard status == errSecSuccess, let data else { FileHandle.standardError.write(Data("Export failed: \(status)\n".utf8)); exit(1) }
try (data as Data).write(to: URL(fileURLWithPath: args[1]))
SWIFT
swift "$SCRIPT" "$OUT" "$PASS"
chmod 600 "$OUT"
echo "$PASS"
