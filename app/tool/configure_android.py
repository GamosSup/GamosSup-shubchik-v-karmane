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
tree.write(path, encoding="utf-8", xml_declaration=True)
