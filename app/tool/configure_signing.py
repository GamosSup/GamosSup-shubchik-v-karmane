import os
from pathlib import Path

required = (
    "SHUBCHIK_SIGNING_KEYSTORE",
    "SHUBCHIK_SIGNING_STORE_PASSWORD",
    "SHUBCHIK_SIGNING_KEY_ALIAS",
    "SHUBCHIK_SIGNING_KEY_PASSWORD",
)
if any(not os.environ.get(name) for name in required):
    raise SystemExit("Signing configuration is incomplete.")
if not Path(os.environ[required[0]]).is_file():
    raise SystemExit("Signing keystore is missing.")

path = Path("android/app/build.gradle.kts")
source = path.read_text(encoding="utf-8")
debug = 'signingConfig = signingConfigs.getByName("debug")'
if source.count(debug) != 1 or source.count("    buildTypes {") != 1:
    raise SystemExit("Unexpected Android Gradle template.")
signing = """    signingConfigs {
        create("release") {
            storeFile = file(System.getenv("SHUBCHIK_SIGNING_KEYSTORE"))
            storePassword = System.getenv("SHUBCHIK_SIGNING_STORE_PASSWORD")
            keyAlias = System.getenv("SHUBCHIK_SIGNING_KEY_ALIAS")
            keyPassword = System.getenv("SHUBCHIK_SIGNING_KEY_PASSWORD")
        }
    }

    buildTypes {"""
source = source.replace("    buildTypes {", signing)
source = source.replace(debug, 'signingConfig = signingConfigs.getByName("release")')
path.write_text(source, encoding="utf-8")
