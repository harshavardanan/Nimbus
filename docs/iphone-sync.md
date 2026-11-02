# Syncing Nimbus with your iPhone and iPad

There are two ways to connect your iPhone or iPad. **Wi-Fi is the one to use.** iCloud is the fallback.

| | Wi-Fi (recommended) | iCloud folder |
|---|---|---|
| Speed | Instant | A few seconds to minutes |
| Needs | Same Wi-Fi as your Mac | iCloud Drive and Shortcuts sync |
| Setup | Two clicks in Nimbus | Add shortcuts, then check the Save File step |

## Wi-Fi (recommended)

Your iPhone sends a small web request to your Mac, and Nimbus listens for it. Nothing goes through the
internet or iCloud.

1. In Nimbus → Settings → Widgets, switch on **Let my devices connect to this Mac**. (macOS may ask if Nimbus
   can accept connections. Allow it.)
2. Click **Create iPhone shortcuts**. Nimbus builds five shortcuts with your Mac's address and a private
   token already inside.
3. Click **Add** on each one, then **Add Shortcut**. They reach your iPhone and iPad through iCloud. Or use
   **AirDrop** to send them straight to a device.
4. Run **Nimbus Sync** on the phone. Your battery appears in the Devices tab within a second.

For a battery that stays fresh, add a Personal automation (Shortcuts → Automation) that runs **Nimbus Sync**,
for example every hour or when the charger connects. Add **Nimbus Timer** to the Action Button or say
"Hey Siri, Nimbus Timer".

**What the shortcuts send.** A web address such as
`http://My-Mac.local:8765/b?token=…&name=iPhone&level=82`. Nimbus accepts only a battery level (`/b`), a
timer (`/t`) and a Pomodoro command or message (`/c`), and answers `403` to anything without the token.

**Safety.**
- It's off until you switch it on, and it only listens on your local network.
- Every request needs the private token, which lives in your Keychain and inside the shortcuts Nimbus made.
- Requests are limited to 60 a minute, and the list of things they can do is fixed. They can't run programs,
  open files or change settings.
- The connection isn't encrypted, so use it on networks you trust, like home. If you think the token leaked,
  click **Make a new private token…** and create the shortcuts again.

**If it doesn't connect.** Make sure the phone is on the same Wi-Fi (not cellular). If your network doesn't
resolve `.local` names, Settings also shows the Mac's IP address; use it in place of the name. Guest networks
and some routers block devices from talking to each other.

---

# The iCloud way (fallback)

Nimbus can't read an iPhone's battery directly: Apple offers no public way to do it from a Mac.
Instead, a small Shortcut on your iPhone writes its battery level to a file in iCloud Drive, and
Nimbus reads that file. Nothing leaves your Apple account, and there's no server.

```
iPhone Shortcut  ──►  iCloud Drive / Shortcuts / nimbus-device-<name>.json  ──►  Nimbus on your Mac
```

## Set it up (about two minutes)

1. **Add the shortcut.** On your Mac, open Nimbus → Settings → Widgets → *iPhone and iPad* and click
   **Add shortcut to Shortcuts**, then **Add Shortcut**. It syncs to your iPhone through iCloud.
   (Or use **Send via AirDrop…** to send it straight to the phone.)
2. **Run it once on the iPhone.** Open Shortcuts, tap **Nimbus Sync**. iOS asks for permission to save to
   iCloud Drive and read device details. Allow both.
3. **Check it arrived.** In Nimbus, open the island's Devices tab. Your iPhone appears with a small age
   label such as `now`.
4. **Keep it fresh.** In Shortcuts → Automation, add a **Personal** automation that runs **Nimbus Sync**,
   for example *Time of Day, every hour* or *when the charger is connected*. Turn on **Run Immediately**
   and turn off **Notify When Run**.

For an iPad (or a second phone), install the same shortcut there and run it once. There is nothing to
rename: each device writes its own file, named after the device (`nimbus-device-Harsha's iPad.json`), and the
device model in the file picks the iPad or iPhone icon.

## What gets written

One small text file per device, `iCloud Drive/Shortcuts/nimbus-device-<name>.json`:

```json
{"name": "Harsha's iPhone", "level": 82, "kind": "iPhone"}
```

| Field | Meaning |
|---|---|
| `name` | Shown on the tile |
| `level` | Battery percentage. `82`, `"82"` and `0.82` all work |
| `kind` | The device model (`iPhone`, `iPad`) or `watch`, for the icon |

Nimbus reads the `nimbus*.json` files in the Shortcuts folder (every `.json` file if you pick a folder yourself), ignores any it can't understand, and shows how old each
reading is.

## Limits

- A phone is only as current as its last run. Nimbus shows the age, and it won't raise a low-battery alert
  from a reading older than six hours.
- Shortcuts can't report whether the phone is charging, so there's no charging bolt for phones.
- macOS may ask Nimbus for permission to read iCloud Drive the first time.
- Not using iCloud Drive? Pick any synced folder (Dropbox, Syncthing and so on) with **Choose folder…**
  in Settings, and point the *Save File* action on the phone at the same folder.

## If something is off

- **Nothing appears.** Use **Write test file** in Settings. If the test tile shows up, Nimbus is fine and
  the problem is the phone side. Check that `nimbus-device-<name>.json` exists in iCloud Drive → Shortcuts.
- **The imported shortcut looks incomplete.** Open it in Shortcuts. It should have five actions:
  Get Battery Level, Get Device Details, Text, Set Name, Save File. If one is blank, fill it in using the
  hand-made steps in Settings.
- **Rebuilding the shortcut.** `python3 scripts/make_shortcut.py` regenerates and signs
  `Shortcuts/Nimbus Sync.shortcut` (needs macOS).

---

# More than battery: timers and commands

The same iCloud folder carries two more things. Add any of these from Nimbus → Settings → Widgets →
*Control Nimbus from your iPhone* (**Add**, or **AirDrop** straight to the phone).

| Shortcut | What it does |
|---|---|
| **Nimbus Pomodoro** | Asks how many minutes, then starts a focus session on your Mac |
| **Nimbus Timer** | Starts a Clock timer on your phone and shows the countdown in the island |
| **Nimbus Pause** | Pauses the Pomodoro on your Mac |
| **Nimbus Skip** | Skips to the next Pomodoro stage |

Add a Siri phrase, a Home Screen icon, an Action Button press or a Back Tap to any of them.

## Phone timers

Nimbus can't see a timer you start the normal way (in the Clock app, or by telling Siri "set a timer").
iOS gives apps and Shortcuts no way to read those. Start your timers with **Nimbus Timer** instead:

- Say "Hey Siri, **Nimbus Timer**", or put it on the Action Button, Back Tap, Lock Screen or Home Screen.
- It asks for the length, starts a real Clock timer on the phone, and sends the countdown to your Mac.

The island shows an iPhone icon with the time left (the Pomodoro tab shows it larger, with a Dismiss
button), and a banner appears when it ends. Nimbus treats the moment the file was written as the start,
so the Mac matches the phone.

It writes `nimbus-timer-<device name>.json`:

```json
{"name": "iPhone", "label": "Timer", "minutes": 25}
```

`start` (ISO 8601 or a Unix time) is optional and overrides the file's own time. If your Mac runs
macOS 15 or later, it may also show Live Activities from a nearby iPhone in the menu bar by itself;
Nimbus can't read those.

## Commands

A command is a file named `nimbus-command.json`. Nimbus runs it once and deletes it.

```json
{"action": "pomodoro.start", "stage": "focus", "minutes": 25}
```

| `action` | Extra fields |
|---|---|
| `pomodoro.start` | `stage` (`focus`, `short`, `long`) and `minutes`, both optional |
| `pomodoro.pause`, `pomodoro.resume`, `pomodoro.reset`, `pomodoro.skip` | none |
| `notify` | `title`, `line`: shows a banner in the island |

To make your own, copy *Nimbus Pause* in Shortcuts and change the text.

**Safety.** Commands are a fixed short list and can't run programs, open files or change settings.
Only people who can write to your iCloud folder (you, on your own devices) can send them. A command
older than ten minutes is discarded unrun. To turn it all off, switch off
*Accept commands from my devices* in Settings.
