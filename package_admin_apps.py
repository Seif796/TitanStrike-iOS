import zipfile
import hashlib
import base64
import struct
import datetime
import pathlib
import shutil
import plistlib
from cryptography.hazmat.primitives.serialization import pkcs7, Encoding
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import hashes
from cryptography import x509

def unpack_pck_files(pck_path: pathlib.Path) -> dict[str, bytes]:
    data = pck_path.read_bytes()
    file_count = struct.unpack('<I', data[96:100])[0]
    pos = 100
    files = {}
    for _ in range(file_count):
        path_len = struct.unpack('<I', data[pos:pos+4])[0]
        pos += 4
        pad = (4 - (path_len % 4)) % 4
        path_bytes = data[pos:pos+path_len]
        pos += path_len + pad
        path_str = path_bytes.split(b'\x00')[0].decode('utf-8', errors='replace')
        offset, size = struct.unpack('<QQ', data[pos:pos+16])
        pos += 16
        md5 = data[pos:pos+16]
        pos += 16
        flag = struct.unpack('<I', data[pos:pos+4])[0]
        pos += 4
        files[path_str] = data[offset:offset+size]
    return files

def sign_apk_v1(apk_entries: dict[str, bytes]) -> dict[str, bytes]:
    # 1. Generate RSA key & self-signed cert
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = issuer = x509.Name([
        x509.NameAttribute(x509.NameOID.COMMON_NAME, 'Admin Manager'),
        x509.NameAttribute(x509.NameOID.ORGANIZATION_NAME, 'TitanStrike')
    ])
    now = datetime.datetime.now(datetime.timezone.utc)
    cert = x509.CertificateBuilder()\
        .subject_name(subject)\
        .issuer_name(issuer)\
        .public_key(key.public_key())\
        .serial_number(x509.random_serial_number())\
        .not_valid_before(now - datetime.timedelta(days=1))\
        .not_valid_after(now + datetime.timedelta(days=36500))\
        .sign(key, hashes.SHA256())

    # Filter out existing META-INF
    filtered = {k: v for k, v in apk_entries.items() if not k.startswith('META-INF/')}

    manifest_lines = [
        "Manifest-Version: 1.0",
        "Created-By: 1.0 (AdminManager)"
    ]
    sf_lines = [
        "Signature-Version: 1.0",
        "Created-By: 1.0 (AdminManager)"
    ]

    manifest_body = "\r\n".join(manifest_lines) + "\r\n\r\n"
    
    entry_hashes = {}
    for name in sorted(filtered.keys()):
        h = base64.b64encode(hashlib.sha256(filtered[name]).digest()).decode('ascii')
        entry_block = f"Name: {name}\r\nSHA-256-Digest: {h}\r\n\r\n"
        manifest_body += entry_block
        entry_h = base64.b64encode(hashlib.sha256(entry_block.encode('utf-8')).digest()).decode('ascii')
        entry_hashes[name] = entry_h

    manifest_bytes = manifest_body.encode('utf-8')
    manifest_digest = base64.b64encode(hashlib.sha256(manifest_bytes).digest()).decode('ascii')
    
    sf_body = "\r\n".join(sf_lines) + f"\r\nSHA-256-Digest-Manifest: {manifest_digest}\r\n\r\n"
    for name in sorted(filtered.keys()):
        sf_body += f"Name: {name}\r\nSHA-256-Digest: {entry_hashes[name]}\r\n\r\n"
    sf_bytes = sf_body.encode('utf-8')

    # PKCS7 sign CERT.SF
    builder = pkcs7.PKCS7SignatureBuilder().set_data(sf_bytes)
    builder = builder.add_signer(cert, key, hashes.SHA256())
    rsa_bytes = builder.sign(Encoding.DER, [pkcs7.PKCS7Options.Binary])

    filtered['META-INF/MANIFEST.MF'] = manifest_bytes
    filtered['META-INF/CERT.SF'] = sf_bytes
    filtered['META-INF/CERT.RSA'] = rsa_bytes
    return filtered

def build_admin_manager_apk(src_apk: pathlib.Path, pck_path: pathlib.Path, out_apk: pathlib.Path):
    print(f"[*] Packaging Admin Manager APK: {out_apk.name}...")
    pck_files = unpack_pck_files(pck_path)
    print(f"    - Extracted {len(pck_files)} files from PCK")

    entries = {}
    with zipfile.ZipFile(src_apk, 'r') as z:
        for info in z.infolist():
            entries[info.filename] = z.read(info.filename)

    # Replace / inject assets from PCK
    for res_path, data in pck_files.items():
        if res_path.startswith("res://"):
            asset_path = "assets/" + res_path[len("res://"):]
            entries[asset_path] = data

    # Also include the PCK itself in assets
    pck_raw = pck_path.read_bytes()
    entries["assets/AdminManager.pck"] = pck_raw
    entries["assets/TitanStrike.pck"] = pck_raw
    entries["assets/main.pck"] = pck_raw

    # Sign APK
    signed_entries = sign_apk_v1(entries)

    # Write out signed APK with no/deflate compression
    with zipfile.ZipFile(out_apk, 'w', compression=zipfile.ZIP_DEFLATED) as z_out:
        # Put META-INF first per standard JAR practice
        for k in sorted(signed_entries.keys(), key=lambda x: (not x.startswith('META-INF/'), x)):
            z_out.writestr(k, signed_entries[k])

    print(f"[+] Successfully built signed Admin Manager APK: {out_apk} ({out_apk.stat().st_size} bytes)")

def build_admin_manager_ipa(src_ipa: pathlib.Path, pck_path: pathlib.Path, out_ipa: pathlib.Path):
    print(f"[*] Packaging Admin Manager IPA: {out_ipa.name}...")
    pck_raw = pck_path.read_bytes()
    
    entries = {}
    with zipfile.ZipFile(src_ipa, 'r') as z:
        for info in z.infolist():
            entries[info.filename] = z.read(info.filename)

    # Find Info.plist
    plist_name = None
    for name in entries:
        if name.endswith('.app/Info.plist'):
            plist_name = name
            break

    if plist_name:
        try:
            plist_data = plistlib.loads(entries[plist_name])
            plist_data['CFBundleDisplayName'] = 'Admin Manager'
            plist_data['CFBundleName'] = 'AdminManager'
            plist_data['CFBundleIdentifier'] = 'com.titanstrike.adminmanager'
            entries[plist_name] = plistlib.dumps(plist_data)
            print("    - Updated Info.plist: CFBundleDisplayName = 'Admin Manager'")
        except Exception as e:
            print("    - Notice updating plist:", e)

    # Replace TitanStrike.pck in the bundle
    replaced_pck = False
    for name in list(entries.keys()):
        if name.endswith('.app/TitanStrike.pck'):
            entries[name] = pck_raw
            replaced_pck = True
            print(f"    - Replaced PCK inside IPA: {name}")

    if not replaced_pck:
        # inject into first .app directory
        for name in entries:
            if '.app/' in name:
                app_dir = name.split('.app/')[0] + '.app/'
                entries[app_dir + 'TitanStrike.pck'] = pck_raw
                print(f"    - Injected PCK to: {app_dir + 'TitanStrike.pck'}")
                break

    with zipfile.ZipFile(out_ipa, 'w', compression=zipfile.ZIP_DEFLATED) as z_out:
        for k, v in entries.items():
            z_out.writestr(k, v)

    print(f"[+] Successfully built Admin Manager IPA: {out_ipa} ({out_ipa.stat().st_size} bytes)")

if __name__ == "__main__":
    src_apk = pathlib.Path("server/public/downloads/TitanStrike.apk")
    src_ipa = pathlib.Path("server/public/downloads/TitanStrike.ipa")
    pck_path = pathlib.Path("build/admin/AdminManager.pck")

    out_apk_dl = pathlib.Path("server/public/downloads/AdminManager.apk")
    out_ipa_dl = pathlib.Path("server/public/downloads/AdminManager.ipa")

    build_admin_manager_apk(src_apk, pck_path, out_apk_dl)
    build_admin_manager_ipa(src_ipa, pck_path, out_ipa_dl)

    # Copy to Desktop locations
    desktop_targets = [
        pathlib.Path("C:/Users/Administrator/Desktop"),
        pathlib.Path("C:/Users/Administrator/OneDrive/Desktop")
    ]

    for d in desktop_targets:
        if d.exists():
            shutil.copy2(out_apk_dl, d / "AdminManager.apk")
            shutil.copy2(out_ipa_dl, d / "AdminManager.ipa")
            print(f"[+] Copied AdminManager.apk & AdminManager.ipa to: {d}")
