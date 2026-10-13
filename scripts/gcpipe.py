#!/usr/bin/env python3
"""Drive the GameCube controller via ModernGekko's named-pipe input device.

ModernGekko's Dolphin-derived input backend reads text commands from FIFOs in
$MODERNGEKKO_PIPES_DIR (default ~/.local/share/moderngekko/Pipes). Commands:

    PRESS <BUTTON>
    RELEASE <BUTTON>
    SET MAIN <x> <y>     # main stick, each in [-1, 1]
    SET C <x> <y>        # C-stick, each in [-1, 1]
    SET L <v>            # analog shoulder L, v in [-1, 1]
    SET R <v>            # analog shoulder R, v in [-1, 1]

Buttons: A B X Y Z START L R D_UP D_DOWN D_LEFT D_RIGHT

This script waits up to --open-timeout for the runtime to open the FIFO for
reading, then executes the requested sequence with wall-clock timing so the
game sees a believable button timeline.
"""

from __future__ import annotations

import argparse
import errno
import json
import os
import sys
import time
from pathlib import Path


DEFAULT_PIPES_DIR = Path.home() / ".local/share/moderngekko/Pipes"


class PadWriter:
    def __init__(self, pipe_path: Path, timeout_s: float = 60.0):
        self.pipe_path = pipe_path
        self.fd = None
        deadline = time.monotonic() + timeout_s
        while time.monotonic() < deadline:
            try:
                fd = os.open(pipe_path, os.O_WRONLY | os.O_NONBLOCK)
            except OSError as error:
                if error.errno not in (errno.ENOENT, errno.ENXIO):
                    raise
            else:
                # Bound only the connection wait; keep command writes blocking.
                try:
                    os.set_blocking(fd, True)
                except OSError:
                    os.close(fd)
                    raise
                self.fd = fd
                return
            remaining = deadline - time.monotonic()
            if remaining > 0:
                time.sleep(min(0.25, remaining))
        raise RuntimeError(f"pipe never opened for reading: {pipe_path}")

    def send(self, command: str) -> None:
        line = command.rstrip("\n") + "\n"
        os.write(self.fd, line.encode("utf-8"))

    def tap(self, button: str, hold_s: float = 0.12) -> None:
        self.send(f"PRESS {button}")
        time.sleep(hold_s)
        self.send(f"RELEASE {button}")

    def set_stick(self, name: str, x: float, y: float) -> None:
        # The pipe's 4-token SET form takes raw axis values in [0, 1] with
        # 0.5 = neutral (0 = full negative, 1 = full positive). The API here
        # uses [-1, 1] with +x = right and +y = up, matching GCPadNew.ini where
        # "Axis <N> Y -" is bound to Stick Up and "Axis <N> Y +" to Stick Down.
        ix = 0.5 + x / 2.0
        iy = 0.5 - y / 2.0
        self.send(f"SET {name} {ix:.3f} {iy:.3f}")

    def set_trigger(self, name: str, value: float) -> None:
        self.send(f"SET {name} {value:.3f}")

    def close(self) -> None:
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None


def run_sequence(writer: PadWriter, seq: list[dict]) -> None:
    t0 = time.monotonic()
    for i, step in enumerate(seq):
        action = step.get("action", "tap")
        delay = float(step.get("delay", 0.0))
        if delay > 0:
            time.sleep(delay)
        if action == "tap":
            writer.tap(step["button"], float(step.get("hold", 0.12)))
        elif action == "press":
            writer.send(f"PRESS {step['button']}")
        elif action == "release":
            writer.send(f"RELEASE {step['button']}")
        elif action == "stick":
            writer.set_stick(step["axis"], float(step["x"]), float(step["y"]))
        elif action == "trigger":
            writer.set_trigger(step["axis"], float(step["value"]))
        elif action == "wait":
            time.sleep(float(step.get("seconds", 1.0)))
        else:
            raise ValueError(f"unknown action {action}")
        now = time.monotonic() - t0
        print(f"[{now:7.2f}s] {json.dumps(step)}", flush=True)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--pipe", type=Path, default=None, help="FIFO path")
    ap.add_argument("--open-timeout", type=float, default=60.0)
    ap.add_argument("--sequence", type=Path, help="JSON list of input steps")
    ap.add_argument("--tap", metavar="BUTTON", help="tap one button")
    ap.add_argument("--stick", nargs=3, metavar=("AXIS", "X", "Y"),
                    help="set stick, e.g. MAIN 0.5 0.5")
    args = ap.parse_args()

    pipe = args.pipe or (DEFAULT_PIPES_DIR / "sunpad")
    writer = PadWriter(pipe, timeout_s=args.open_timeout)
    try:
        if args.sequence:
            with open(args.sequence) as f:
                seq = json.load(f)
            run_sequence(writer, seq)
        if args.tap:
            writer.tap(args.tap)
        if args.stick:
            writer.set_stick(args.stick[0], float(args.stick[1]), float(args.stick[2]))
    finally:
        writer.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
