from pathlib import Path
import xml.etree.ElementTree as ET

path = Path("android/app/src/main/AndroidManifest.xml")
namespace = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", namespace)
tree = ET.parse(path)
root = tree.getroot()
application = root.find("application")
assert application is not None
application.set(f"{{{namespace}}}allowBackup", "false")
application.set(f"{{{namespace}}}label", "Шубчик в кармане")
if not any(
    element.get(f"{{{namespace}}}name") == "android.permission.INTERNET"
    for element in root.findall("uses-permission")
):
    ET.SubElement(
        root, "uses-permission",
        {f"{{{namespace}}}name": "android.permission.INTERNET"},
    )
queries = root.find("queries")
if queries is None:
    queries = ET.SubElement(root, "queries")
tts = ET.SubElement(queries, "intent")
ET.SubElement(tts, "action", {f"{{{namespace}}}name": "android.intent.action.TTS_SERVICE"})
recognition = ET.SubElement(queries, "intent")
ET.SubElement(recognition, "action", {f"{{{namespace}}}name": "android.speech.RecognitionService"})
ET.SubElement(root, "uses-permission", {f"{{{namespace}}}name": "android.permission.RECORD_AUDIO"})
tree.write(path, encoding="utf-8", xml_declaration=True)

activity = Path("android/app/src/main/kotlin/io/github/gamossup/shubchik/MainActivity.kt")
if not activity.is_file():
    raise FileNotFoundError(f"Missing Android activity: {activity}")
activity.write_bytes(Path("tool/MainActivity.kt").read_bytes())
