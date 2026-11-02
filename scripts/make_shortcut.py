#!/usr/bin/env python3
"""Builds the Nimbus Shortcuts (battery sync, Pomodoro control, timer, pause, skip).
Each one writes a small nimbus-*.json file into the Shortcuts folder in iCloud Drive, which Nimbus
reads. Run on a Mac:

    python3 scripts/make_shortcut.py

The unsigned plist is written next to the signed file so the structure can be inspected.
"""
import plistlib
import subprocess
import sys
import uuid
from pathlib import Path

OBJ = "￼"  # placeholder character where a variable is inserted into text
ROOT = Path(__file__).resolve().parent.parent / "Shortcuts"
NAME = "Nimbus Sync"


def token_string(parts):
    """Text with variables. `parts` mixes plain strings and (uuid, output_name) tuples."""
    text, attachments = "", {}
    for part in parts:
        if isinstance(part, tuple):
            attachments[f"{{{len(text.encode('utf-16-le')) // 2}, 1}}"] = {
                "OutputUUID": part[0],
                "OutputName": part[1],
                "Type": "ActionOutput",
            }
            text += OBJ
        else:
            text += part
    return {
        "Value": {"string": text, "attachmentsByRange": attachments},
        "WFSerializationType": "WFTextTokenString",
    }


def action(identifier, **params):
    return {"WFWorkflowActionIdentifier": f"is.workflow.actions.{identifier}", "WFWorkflowActionParameters": params}


def save_steps(filename):
    """Name the text as a file and save it to the default Shortcuts folder in iCloud Drive.
    `filename` is plain text, or a list of parts that may include variables."""
    name = token_string(filename) if isinstance(filename, list) else filename
    return [
        action("setitemname", WFName=name, WFDontIncludeFileExtension=False),
        action("documentpicker.save", WFAskWhereToSave=False, WFSaveFileOverwrite=True),
    ]


def workflow(actions, color):
    return {
        "WFWorkflowClientVersion": "2900.0.1",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowIcon": {"WFWorkflowIconStartColor": color, "WFWorkflowIconGlyphNumber": 59511},
        "WFWorkflowImportQuestions": [],
        "WFWorkflowInputContentItemClasses": [],
        "WFWorkflowTypes": [],
        "WFWorkflowActions": actions,
    }


def ask_minutes(prompt, default="25"):
    ask = str(uuid.uuid4()).upper()
    return ask, action(
        "ask", UUID=ask, WFAskActionPrompt=prompt, WFInputType="Number",
        WFAskActionDefaultAnswer=default, WFAskActionDefaultAnswerNumber=default,
    )


def battery():
    """Writes this device's battery level. The file is named after the device, so an iPhone and
    an iPad never overwrite each other, and the device model picks the icon in Nimbus."""
    level, device, model, text = (str(uuid.uuid4()).upper() for _ in range(4))
    return workflow([
        action("getbatterylevel", UUID=level),
        action("getdevicedetails", WFDeviceDetail="Device Name", UUID=device),
        action("getdevicedetails", WFDeviceDetail="Device Model", UUID=model),
        action("gettext", UUID=text, WFTextActionText=token_string([
            '{"name": "', (device, "Device Details"),
            '", "level": ', (level, "Battery Level"),
            ', "kind": "', (model, "Device Details"), '"}',
        ])),
        *save_steps(["nimbus-device-", (device, "Device Details"), ".json"]),
    ], 4282601983)


def pomodoro():
    """Starts a focus session of the chosen length on the Mac."""
    ask_id, ask = ask_minutes("How many minutes of focus?")
    text = str(uuid.uuid4()).upper()
    return workflow([
        ask,
        action("gettext", UUID=text, WFTextActionText=token_string([
            '{"action": "pomodoro.start", "stage": "focus", "minutes": ', (ask_id, "Provided Input"), "}",
        ])),
        *save_steps("nimbus-command.json"),
    ], 4251333119)


def phone_timer():
    """Starts a real Clock timer on the phone AND sends the countdown to the Mac's island."""
    ask_id, ask = ask_minutes("Timer length in minutes?")
    device, text = (str(uuid.uuid4()).upper() for _ in range(2))
    clock = action(
        "timer.start",
        WFDuration={
            "Value": {"Unit": "min", "Magnitude": token_string([(ask_id, "Provided Input")])},
            "WFSerializationType": "WFQuantityFieldValue",
        },
    )
    return workflow([
        ask,
        clock,
        action("getdevicedetails", WFDeviceDetail="Device Name", UUID=device),
        action("gettext", UUID=text, WFTextActionText=token_string([
            '{"name": "', (device, "Device Details"), '", "label": "Timer", "minutes": ',
            (ask_id, "Provided Input"), "}",
        ])),
        *save_steps(["nimbus-timer-", (device, "Device Details"), ".json"]),
    ], 4271458815)


def command(payload, color):
    text = str(uuid.uuid4()).upper()
    return workflow([
        action("gettext", UUID=text, WFTextActionText=token_string([payload])),
        *save_steps("nimbus-command.json"),
    ], color)


SHORTCUTS = {
    "Nimbus Sync": battery,
    "Nimbus Pomodoro": pomodoro,
    "Nimbus Timer": phone_timer,
    "Nimbus Pause": lambda: command('{"action": "pomodoro.pause"}', 4292093695),
    "Nimbus Skip": lambda: command('{"action": "pomodoro.skip"}', 4292093695),
}


def main():
    ROOT.mkdir(exist_ok=True)
    for name, build in SHORTCUTS.items():
        unsigned = ROOT / f"{name} (unsigned).shortcut"
        signed = ROOT / f"{name}.shortcut"
        with unsigned.open("wb") as f:
            plistlib.dump(build(), f, fmt=plistlib.FMT_BINARY)

        # iOS only imports signed shortcuts. `shortcuts sign` is part of macOS 12 and later.
        result = subprocess.run(
            ["shortcuts", "sign", "--mode", "anyone", "--input", str(unsigned), "--output", str(signed)],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            print(f"Signing {name} failed:", (result.stderr or result.stdout).strip(), file=sys.stderr)
            sys.exit(1)
        print(f"Wrote {signed.name}")


if __name__ == "__main__":
    main()
