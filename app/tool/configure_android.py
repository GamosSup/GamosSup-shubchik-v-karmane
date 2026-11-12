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
main_activity = application.find("activity")
assert main_activity is not None
ET.SubElement(main_activity, "meta-data", {
    f"{{{namespace}}}name": "flutter_deeplinking_enabled",
    f"{{{namespace}}}value": "false",
})
callback = ET.SubElement(main_activity, "intent-filter")
ET.SubElement(callback, "action", {f"{{{namespace}}}name": "android.intent.action.VIEW"})
for category in ("DEFAULT", "BROWSABLE"):
    ET.SubElement(callback, "category", {f"{{{namespace}}}name": f"android.intent.category.{category}"})
ET.SubElement(callback, "data", {
    f"{{{namespace}}}scheme": "io.github.gamossup.shubchik",
    f"{{{namespace}}}host": "auth",
    f"{{{namespace}}}path": "/callback",
})
queries = root.find("queries")
if queries is None:
    queries = ET.SubElement(root, "queries")
tts = ET.SubElement(queries, "intent")
ET.SubElement(tts, "action", {f"{{{namespace}}}name": "android.intent.action.TTS_SERVICE"})
recognition = ET.SubElement(queries, "intent")
ET.SubElement(recognition, "action", {f"{{{namespace}}}name": "android.speech.RecognitionService"})
ET.SubElement(root, "uses-permission", {f"{{{namespace}}}name": "android.permission.RECORD_AUDIO"})
for permission in (
    "android.permission.POST_NOTIFICATIONS", "android.permission.RECEIVE_BOOT_COMPLETED",
    "android.permission.READ_CALENDAR",
    "android.permission.WAKE_LOCK", "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK",
):
    ET.SubElement(root, "uses-permission", {f"{{{namespace}}}name": permission})
receiver = ET.SubElement(application, "receiver", {
    f"{{{namespace}}}name": ".ReminderReceiver",
    f"{{{namespace}}}exported": "false",
})
boot = ET.SubElement(receiver, "intent-filter")
ET.SubElement(boot, "action", {f"{{{namespace}}}name": "android.intent.action.BOOT_COMPLETED"})
widget = ET.SubElement(application, "receiver", {
    f"{{{namespace}}}name": ".PlannerWidgetProvider",
    f"{{{namespace}}}exported": "false",
})
updates = ET.SubElement(widget, "intent-filter")
ET.SubElement(updates, "action", {f"{{{namespace}}}name": "android.appwidget.action.APPWIDGET_UPDATE"})
ET.SubElement(widget, "meta-data", {
    f"{{{namespace}}}name": "android.appwidget.provider",
    f"{{{namespace}}}resource": "@xml/shubchik_widget_info",
})
service = ET.SubElement(application, "service", {
    f"{{{namespace}}}name": "com.ryanheise.audioservice.AudioService",
    f"{{{namespace}}}exported": "true",
    f"{{{namespace}}}foregroundServiceType": "mediaPlayback",
})
browse = ET.SubElement(service, "intent-filter")
ET.SubElement(browse, "action", {f"{{{namespace}}}name": "android.media.browse.MediaBrowserService"})
buttons = ET.SubElement(application, "receiver", {
    f"{{{namespace}}}name": "com.ryanheise.audioservice.MediaButtonReceiver",
    f"{{{namespace}}}exported": "true",
})
media = ET.SubElement(buttons, "intent-filter")
ET.SubElement(media, "action", {f"{{{namespace}}}name": "android.intent.action.MEDIA_BUTTON"})
bank_listener = ET.SubElement(application, "service", {
    f"{{{namespace}}}name": ".BankNotificationListener",
    f"{{{namespace}}}exported": "false",
    f"{{{namespace}}}permission": "android.permission.BIND_NOTIFICATION_LISTENER_SERVICE",
})
bank_listener_filter = ET.SubElement(bank_listener, "intent-filter")
ET.SubElement(bank_listener_filter, "action", {
    f"{{{namespace}}}name": "android.service.notification.NotificationListenerService",
})
tree.write(path, encoding="utf-8", xml_declaration=True)

activity = Path("android/app/src/main/kotlin/io/github/gamossup/shubchik/MainActivity.kt")
if not activity.is_file():
    raise FileNotFoundError(f"Missing Android activity: {activity}")
activity.write_bytes(Path("tool/MainActivity.kt").read_bytes())

activity.with_name("ReminderReceiver.kt").write_bytes(Path("tool/ReminderReceiver.kt").read_bytes())

activity.with_name("PlannerWidgetProvider.kt").write_bytes(Path("tool/PlannerWidgetProvider.kt").read_bytes())
for resource in Path("tool/widget").glob("*/*.xml"):
    destination = Path("android/app/src/main/res") / resource.parent.name / resource.name
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(resource.read_bytes())

activity.with_name('BankNotificationListener.kt').write_bytes(Path('tool/BankNotificationListener.kt').read_bytes())
activity.with_name('BackupCipher.kt').write_bytes(Path('tool/BackupCipher.kt').read_bytes())
