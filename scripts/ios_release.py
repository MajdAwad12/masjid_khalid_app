"""Prepare the signed iOS build and check the IPA exported by Xcode."""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
from urllib.parse import urlsplit


BUNDLE_ID = "com.masjidkhalidbinwaleed.masjidKhalidApp"
FIREBASE_PLIST = Path("ios/Runner/GoogleService-Info.plist")
PUBLIC_FIELDS = {"SUPPORT_MANAGER_NAME", "SUPPORT_MANAGER_PHONE", "SUPPORT_EMAIL", "PRIVACY_POLICY_URL"}


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def read_plist(path):
    with path.open("rb") as stream:
        return plistlib.load(stream)


def store_config():
    try:
        config = json.loads(os.environ.get("IOS_STORE_CONFIG_JSON", "").lstrip("\ufeff"))
    except ValueError:
        raise SystemExit("Set IOS_STORE_CONFIG_JSON to the approved public store JSON.") from None
    require(isinstance(config, dict) and set(config) == PUBLIC_FIELDS,
            "Store JSON must contain exactly the four documented public fields.")
    for key, value in config.items():
        require(isinstance(value, str) and value.strip(), f"Missing public value for {key}.")
        config[key] = value.strip()
    require(config["SUPPORT_MANAGER_NAME"].casefold() not in {"placeholder", "todo", "يُضاف اسم المسؤول لاحقًا"},
            "Use the approved public operator name.")
    require(re.fullmatch(r"[+\d][\d ()-]{6,24}", config["SUPPORT_MANAGER_PHONE"]),
            "Invalid public support phone.")
    require(re.fullmatch(r'[^\s@<>"]+@[^\s@<>"]+\.[^\s@<>"]+', config["SUPPORT_EMAIL"]),
            "Invalid public support email.")
    try:
        url = urlsplit(config["PRIVACY_POLICY_URL"])
        host = url.hostname or ""
    except ValueError:
        raise SystemExit("Invalid public policy URL.") from None
    require(url.scheme == "https" and "." in host and url.path == "/privacy"
            and not (url.username or url.password or url.query or url.fragment)
            and not re.search(r"(^|\.)(localhost|example|invalid|test|example\.(com|org|net))$", host),
            "Use the approved public HTTPS /privacy URL.")
    return config


def check_firebase():
    plist = read_plist(FIREBASE_PLIST)
    require(plist.get("BUNDLE_ID") == BUNDLE_ID and plist.get("IS_GCM_ENABLED") is True,
            "Firebase plist bundle ID or messaging configuration is incorrect.")
    dart = Path("lib/firebase_options.dart").read_text(encoding="utf-8")
    ios = re.search(r"FirebaseOptions\s+ios\s*=\s*FirebaseOptions\((.*?)\);", dart, re.S)
    require(ios, "Missing Dart iOS Firebase options.")
    fields = dict(re.findall(r"(\w+):\s*'([^']+)'", ios.group(1)))
    mapping = {"iosBundleId": "BUNDLE_ID", "apiKey": "API_KEY", "appId": "GOOGLE_APP_ID",
               "projectId": "PROJECT_ID", "messagingSenderId": "GCM_SENDER_ID",
               "storageBucket": "STORAGE_BUCKET"}
    for dart_key, plist_key in mapping.items():
        require(fields.get(dart_key) and fields[dart_key] == plist.get(plist_key),
                f"Firebase iOS configuration mismatch for {dart_key}.")


def check_profile(profile, signed, leaf_certificate):
    allowed = profile["Entitlements"]
    require(profile["ExpirationDate"].replace(tzinfo=timezone.utc) > datetime.now(timezone.utc),
            "The provisioning profile has expired.")
    require("ProvisionedDevices" not in profile and not profile.get("ProvisionsAllDevices")
            and allowed.get("beta-reports-active") is True, "Expected an App Store provisioning profile.")
    require(leaf_certificate in profile["DeveloperCertificates"], "Profile does not authorize the signer.")
    require(signed.get("com.apple.developer.team-identifier") in profile["TeamIdentifier"],
            "Signed team does not match the profile.")
    app_id = signed.get("application-identifier")
    require(app_id == allowed.get("application-identifier") and
            any(app_id == f"{prefix}.{BUNDLE_ID}" for prefix in profile["ApplicationIdentifierPrefix"]),
            "Signed application identifier does not match the explicit profile.")
    for entitlements in (allowed, signed):
        require(entitlements.get("aps-environment") == "production", "Missing production APNs entitlement.")
        require(not entitlements.get("get-task-allow"), "Debugging is enabled in the signed app or profile.")


def verify_ipa(version, build_number):
    ipas = list(Path("build/ios/ipa").glob("*.ipa"))
    require(len(ipas) == 1, "Expected one exported IPA.")
    with tempfile.TemporaryDirectory() as scratch:
        directory = Path(scratch)
        subprocess.run(["ditto", "-x", "-k", ipas[0], directory], check=True)
        apps = list((directory / "Payload").glob("*.app"))
        require(len(apps) == 1, "Expected one application in Payload.")
        app = apps[0]
        info = read_plist(app / "Info.plist")
        require(info.get("CFBundleIdentifier") == BUNDLE_ID, "Exported bundle ID mismatch.")
        require(info.get("CFBundleShortVersionString") == version
                and info.get("CFBundleVersion") == build_number, "Exported version or build number mismatch.")
        require(read_plist(app / "GoogleService-Info.plist") == read_plist(FIREBASE_PLIST),
                "Embedded Firebase plist differs from the verified source.")
        subprocess.run(["codesign", "--verify", "--deep", "--strict", app], check=True)
        details = subprocess.run(["codesign", "-dvv", app], check=True, capture_output=True)
        require(b"\nAuthority=Apple Distribution:" in details.stderr,
                "Expected an Apple Distribution signing identity.")
        signed = plistlib.loads(subprocess.check_output(["codesign", "-d", "--entitlements", "-", "--xml", app]))
        profile = plistlib.loads(subprocess.check_output(["security", "cms", "-D", "-i", app / "embedded.mobileprovision"]))
        subprocess.run(["codesign", "-d", "--extract-certificates", app], cwd=directory, check=True)
        check_profile(profile, signed, (directory / "codesign0").read_bytes())
    print(f"Verified signed App Store IPA for {BUNDLE_ID}, version {version}+{build_number}.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["check", "prepare", "verify"])
    parser.add_argument("build_number")
    parser.add_argument("config_output", type=Path, nargs="?")
    args = parser.parse_args()
    require(re.fullmatch(r"[1-9][0-9]*", args.build_number), "Use a positive integer iOS build number.")
    require((args.action == "prepare") == bool(args.config_output), "Only prepare takes an output file.")
    version = re.search(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+\s*$",
                        Path("pubspec.yaml").read_text(encoding="utf-8"), re.M)
    require(version, "Expected a Flutter marketing version and build number in pubspec.yaml.")
    check_firebase()
    if args.action == "verify":
        verify_ipa(version[1], args.build_number)
        return
    config = store_config()
    if args.action == "prepare":
        options = read_plist(Path.home() / "export_options.plist")
        require(options.get("method") in {"app-store", "app-store-connect"}
                and options.get("destination", "export") == "export"
                and options.get("manageAppVersionAndBuildNumber") is False
                and not options.get("testFlightInternalTestingOnly"),
                "Expected App Store export with the original build number.")
        with args.config_output.open("x", encoding="utf-8") as stream:
            json.dump(config, stream, ensure_ascii=False)
        print(version[1])


if __name__ == "__main__":
    main()
