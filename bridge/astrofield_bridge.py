#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""AstroField bridge between the mobile app and Astroberry/Ekos/INDI."""

from __future__ import annotations

import hmac
import json
import math
import os
import platform
import re
import shutil
import socket
import sqlite3
import statistics
import subprocess
import threading
import time
import uuid
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

try:
    import PyIndi
except ImportError:  # Allows local validation away from Astroberry.
    PyIndi = None

HOST = "0.0.0.0"
PORT = 8765
TOKEN = os.environ.get("ASTROFIELD_TOKEN", "")
STATE_DIRECTORY = Path(
    os.environ.get("STATE_DIRECTORY", "/var/lib/astrofield-bridge")
)
LOCATION_FILE = STATE_DIRECTORY / "location.json"
EQUIPMENT_FILE = STATE_DIRECTORY / "equipment.json"
EQUIPMENT_PROFILES_DIRECTORY = STATE_DIRECTORY / "equipment-profiles"
ACTIVE_PROFILE_FILE = STATE_DIRECTORY / "active-equipment-profile"
STORAGE_ROOT = Path(os.environ.get("ASTROFIELD_STORAGE_ROOT", "/srv/astrofield/images"))
ASSISTANT_HISTORY_FILE = STATE_DIRECTORY / "guiding-assistant-history.json"
PHD2_CONFIG_FILE = Path("/home/astroberry/.PHDGuidingV2")
FOCUS_CONFIG_FILE = STATE_DIRECTORY / "focus-config.json"
FOCUS_HISTORY_FILE = STATE_DIRECTORY / "focus-history.json"
INDI_DRIVERS_FILE = Path("/usr/share/indi/drivers.xml")
OPEN_NGC_DATABASE = Path("/usr/share/kstars/OpenNGC.kscat")
location_lock = threading.Lock()
phd2_lock = threading.Lock()
assistant_lock = threading.Lock()
assistant_stop = threading.Event()
assistant_state: dict[str, Any] = {"state": "idle", "samples": 0}
focus_lock = threading.Lock()
focus_state: dict[str, Any] = {"state": "idle", "reason": None}

PHD2_METHODS = {
    "capture_single_frame",
    "clear_calibration",
    "deselect_star",
    "dither",
    "find_star",
    "flip_calibration",
    "get_algo_param",
    "get_algo_param_names",
    "get_app_state",
    "get_calibrated",
    "get_calibration_data",
    "get_camera_binning",
    "get_camera_frame_size",
    "get_connected",
    "get_cooler_status",
    "get_current_equipment",
    "get_dec_guide_mode",
    "get_exposure",
    "get_exposure_durations",
    "get_guide_output_enabled",
    "get_lock_position",
    "get_paused",
    "get_pixel_scale",
    "get_profile",
    "get_profiles",
    "get_search_region",
    "get_sensor_temperature",
    "get_star_image",
    "guide",
    "guide_pulse",
    "loop",
    "save_image",
    "set_algo_param",
    "set_connected",
    "set_dec_guide_mode",
    "set_exposure",
    "set_guide_output_enabled",
    "set_lock_position",
    "set_paused",
    "set_profile",
    "shutdown",
    "stop_capture",
}


def command(*args: str) -> str:
    try:
        result = subprocess.run(
            args,
            check=False,
            capture_output=True,
            text=True,
            timeout=2,
        )
        return result.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def package_version(name: str) -> str:
    return command("dpkg-query", "-W", "-f=${Version}", name) or "unknown"


def indi_pid() -> str:
    return command("pgrep", "-xo", "indiserver")


def phd2_pid() -> str:
    return command("pgrep", "-xo", "phd2")


def phd2_rpc(method: str, params: Any = None) -> dict[str, Any]:
    if method not in PHD2_METHODS:
        raise ValueError("PHD2 method is not allowed")

    request_id = int(time.time_ns() % 2_000_000_000)
    request: dict[str, Any] = {"method": method, "id": request_id}
    if params is not None:
        if not isinstance(params, (list, dict)):
            raise ValueError("params must be an array or object")
        request["params"] = params

    events: list[dict[str, Any]] = []
    with phd2_lock, socket.create_connection(("127.0.0.1", 4400), timeout=2) as client:
        client.settimeout(3)
        stream = client.makefile("rwb")
        stream.write((json.dumps(request, separators=(",", ":")) + "\r\n").encode())
        stream.flush()
        while True:
            line = stream.readline()
            if not line:
                raise ConnectionError("PHD2 closed the connection")
            message = json.loads(line)
            if message.get("id") == request_id:
                return {"response": message, "events": events[-20:]}
            if "Event" in message:
                events.append(message)


def phd2_status() -> dict[str, Any]:
    payload: dict[str, Any] = {
        "installed": package_version("phd2"),
        "running": bool(phd2_pid()),
        "port": 4400,
    }
    if not payload["running"]:
        payload["state"] = "Stopped"
        return payload

    try:
        payload["state"] = phd2_rpc("get_app_state")["response"].get("result")
        payload["connected"] = phd2_rpc("get_connected")["response"].get("result")
        payload["exposure_ms"] = phd2_rpc("get_exposure")["response"].get("result")
        payload["profile"] = phd2_rpc("get_profile")["response"].get("result")
        payload["equipment"] = phd2_rpc("get_current_equipment")["response"].get("result")
    except (ConnectionError, OSError, TimeoutError, json.JSONDecodeError) as error:
        payload["running"] = False
        payload["state"] = "Unavailable"
        payload["error"] = str(error)
    return payload


def phd2_result(method: str, params: Any = None) -> Any:
    response = phd2_rpc(method, params)["response"]
    if "error" in response:
        error = response["error"]
        raise ValueError(str(error.get("message", "PHD2 rejected the command")))
    return response.get("result")


def linear_drift(samples: list[tuple[float, float]]) -> float:
    if len(samples) < 2:
        return 0.0
    mean_time = statistics.fmean(item[0] for item in samples)
    mean_value = statistics.fmean(item[1] for item in samples)
    denominator = sum((item[0] - mean_time) ** 2 for item in samples)
    if denominator == 0:
        return 0.0
    slope_per_second = sum(
        (item[0] - mean_time) * (item[1] - mean_value) for item in samples
    ) / denominator
    return slope_per_second * 60


def detrended_rms(samples: list[tuple[float, float]]) -> float:
    if len(samples) < 2:
        return 0.0
    mean_time = statistics.fmean(item[0] for item in samples)
    mean_value = statistics.fmean(item[1] for item in samples)
    denominator = sum((item[0] - mean_time) ** 2 for item in samples)
    slope = 0.0 if denominator == 0 else sum(
        (item[0] - mean_time) * (item[1] - mean_value) for item in samples
    ) / denominator
    intercept = mean_value - slope * mean_time
    return math.sqrt(
        statistics.fmean((value - (slope * timestamp + intercept)) ** 2 for timestamp, value in samples)
    )


def assistant_history() -> list[dict[str, Any]]:
    try:
        history = json.loads(ASSISTANT_HISTORY_FILE.read_text())
        return history if isinstance(history, list) else []
    except (OSError, json.JSONDecodeError):
        return []


def save_assistant_history(result: dict[str, Any]) -> None:
    STATE_DIRECTORY.mkdir(parents=True, exist_ok=True)
    history = assistant_history()
    history.insert(0, result)
    temporary = ASSISTANT_HISTORY_FILE.with_suffix(".tmp")
    temporary.write_text(json.dumps(history[:20], separators=(",", ":")))
    temporary.replace(ASSISTANT_HISTORY_FILE)


def current_star_position() -> tuple[float, float]:
    image = phd2_result("get_star_image", [31])
    if not isinstance(image, dict) or not isinstance(image.get("star_pos"), list):
        raise ValueError("PHD2 did not return a guide-star position")
    position = image["star_pos"]
    return float(position[0]), float(position[1])


def measure_dec_backlash(exposure_seconds: float, dec_drift_pixels_per_min: float) -> dict[str, Any]:
    calibration = phd2_result("get_calibration_data", ["Mount"])
    if not isinstance(calibration, dict) or not calibration.get("calibrated"):
        raise ValueError("A valid PHD2 mount calibration is required for backlash measurement")
    dec_rate = abs(float(calibration.get("yRate", 0)))
    if dec_rate <= 0:
        raise ValueError("PHD2 did not provide the calibrated DEC guide rate")
    dec_angle = math.radians(float(calibration.get("yAngle", 0)))
    frame_size = phd2_result("get_camera_frame_size")
    if not isinstance(frame_size, list) or len(frame_size) < 2:
        raise ValueError("Guide-camera frame size is unavailable")

    phd2_result("loop")  # Stop guiding while continuing guide-camera exposures.
    time.sleep(max(1.0, exposure_seconds + 0.4))
    start_xy = current_star_position()
    margin = max(20.0, float(phd2_result("get_search_region")))
    if (
        start_xy[0] < margin
        or start_xy[1] < margin
        or start_xy[0] > float(frame_size[0]) - margin
        or start_xy[1] > float(frame_size[1]) - margin
    ):
        raise ValueError("Guide star is too close to the sensor edge for a safe backlash test")

    def dec_coordinate(position: tuple[float, float]) -> float:
        return position[0] * math.cos(dec_angle) + position[1] * math.sin(dec_angle)

    def pulse(direction: str, duration_ms: int) -> float:
        phd2_result("guide_pulse", [duration_ms, direction, "Mount"])
        time.sleep(max(1.0, exposure_seconds + duration_ms / 1000 + 0.3))
        return dec_coordinate(current_star_position())

    clear_pulse_ms = max(250, min(2500, int(5.0 / dec_rate)))
    previous = dec_coordinate(start_xy)
    accepted = 0
    clearing: list[float] = [previous]
    direction_sign = 0.0
    for _ in range(20):
        current = pulse("N", clear_pulse_ms)
        clearing.append(current)
        movement = current - previous
        previous = current
        if abs(movement) >= 4.0 and (direction_sign == 0 or movement * direction_sign > 0):
            direction_sign = movement
            accepted += 1
        else:
            accepted = 0
        with assistant_lock:
            assistant_state.update({"state": "backlash", "backlash_phase": "clearing north", "backlash_steps": len(clearing) - 1})
        if accepted >= 3:
            break
    if accepted < 3:
        raise ValueError("Could not clear north backlash; check calibration, balance, and DEC gear engagement")

    pulse_ms = max(500, min(2000, clear_pulse_ms))
    north_count = max(4, min(16, math.ceil(8000 / pulse_ms)))
    north: list[float] = [previous]
    north_started = time.monotonic()
    for step in range(north_count):
        north.append(pulse("N", pulse_ms))
        with assistant_lock:
            assistant_state.update({"backlash_phase": "moving north", "backlash_steps": step + 1, "backlash_total_steps": north_count * 2})
    north_elapsed = time.monotonic() - north_started
    south: list[float] = [north[-1]]
    for step in range(north_count):
        south.append(pulse("S", pulse_ms))
        with assistant_lock:
            assistant_state.update({"backlash_phase": "returning south", "backlash_steps": north_count + step + 1})

    orientation = 1.0 if statistics.median(
        [north[index] - north[index - 1] for index in range(1, len(north))]
    ) >= 0 else -1.0
    north = [(value - north[0]) * orientation for value in north]
    south = [(value - (north[0] / orientation + previous)) * orientation for value in south]
    north_moves = [north[index] - north[index - 1] for index in range(1, len(north))]
    expected = 0.9 * abs(statistics.median(north_moves))
    north_delta = north[-1] - north[0]
    drift_total = dec_drift_pixels_per_min / 60 * north_elapsed
    north_rate = abs((north_delta - drift_total) / (north_count * pulse_ms))
    if north_rate <= 0 or expected <= 0:
        raise ValueError("DEC movement was too erratic to calculate backlash")
    early_south = 0.0
    good_moves = 0
    backlash_pixels = 0.0
    for step in range(1, len(south)):
        movement = south[step] - south[step - 1]
        early_south += movement
        if movement < 0 and abs(movement) >= expected:
            good_moves += 1
            if good_moves == 2:
                drift_per_frame = drift_total / max(1, north_count)
                backlash_pixels = max(0.0, step * expected - abs(early_south - step * drift_per_frame))
                break
        else:
            good_moves = max(0, good_moves - 1)
    if good_moves < 2:
        raise ValueError("Mount never established consistent south movement; backlash may be excessive")
    backlash_ms = int(backlash_pixels / north_rate)
    recommendation_ms = max(10, int(backlash_ms / 10) * 10) if backlash_ms >= 100 else 0
    if backlash_ms < 100:
        classification = "small"
    elif backlash_ms <= 3000:
        classification = "compensatable"
    else:
        classification = "excessive"
    return {
        "milliseconds": backlash_ms,
        "pixels": round(backlash_pixels, 3),
        "pulse_ms": pulse_ms,
        "classification": classification,
        "recommended_compensation_ms": recommendation_ms if classification == "compensatable" else 0,
        "north_points": [round(value, 3) for value in north],
        "south_points": [round(value, 3) for value in south],
    }


def assistant_snapshot() -> dict[str, Any]:
    with assistant_lock:
        return dict(assistant_state)


def guiding_assistant_worker(duration_seconds: int, measure_backlash: bool) -> None:
    samples: list[tuple[float, float, float, float]] = []
    output_was_enabled = True
    was_guiding = False
    started = time.monotonic()
    try:
        if phd2_result("get_app_state") != "Guiding":
            raise ValueError("Start guiding and let it settle before running the assistant")
        was_guiding = True
        pixel_scale = float(phd2_result("get_pixel_scale"))
        output_was_enabled = bool(phd2_result("get_guide_output_enabled"))
        phd2_result("set_guide_output_enabled", [False])
        with assistant_lock:
            assistant_state.update(
                {
                    "state": "measuring",
                    "started_at": time.time(),
                    "duration_seconds": duration_seconds,
                    "elapsed_seconds": 0,
                    "samples": 0,
                    "pixel_scale": pixel_scale,
                    "message": "Guide output is disabled while mount drift and seeing are measured",
                }
            )

        with socket.create_connection(("127.0.0.1", 4400), timeout=3) as client:
            client.settimeout(10)
            stream = client.makefile("rb")
            while not assistant_stop.is_set() and time.monotonic() - started < duration_seconds:
                try:
                    line = stream.readline()
                except socket.timeout:
                    line = b""
                elapsed = time.monotonic() - started
                if line:
                    message = json.loads(line)
                    if message.get("Event") == "GuideStep":
                        samples.append(
                            (
                                elapsed,
                                float(message.get("RADistanceRaw", 0)) * pixel_scale,
                                float(message.get("DECDistanceRaw", 0)) * pixel_scale,
                                float(message.get("SNR", 0)),
                            )
                        )
                with assistant_lock:
                    assistant_state["elapsed_seconds"] = round(elapsed, 1)
                    assistant_state["samples"] = len(samples)

        if len(samples) < 10:
            raise ValueError("Not enough guide frames were received; keep PHD2 guiding and try again")
        ra_values = [item[1] for item in samples]
        dec_values = [item[2] for item in samples]
        ra_rms = statistics.pstdev(ra_values)
        dec_rms = statistics.pstdev(dec_values)
        ra_differences = [ra_values[index] - ra_values[index - 1] for index in range(1, len(ra_values))]
        dec_differences = [dec_values[index] - dec_values[index - 1] for index in range(1, len(dec_values))]
        ra_seeing = statistics.pstdev(ra_differences) / math.sqrt(2)
        dec_seeing = statistics.pstdev(dec_differences) / math.sqrt(2)
        dec_fit_rms_pixels = detrended_rms([(item[0], item[2] / pixel_scale) for item in samples])
        dec_multiplier = 1.28 if pixel_scale < 1.5 else 1.65
        dec_min_move = max(0.1, math.ceil(dec_fit_rms_pixels * dec_multiplier / 0.05) * 0.05)
        if dec_min_move * pixel_scale > 1.25:
            dec_min_move = min(1.25 / pixel_scale, 0.5)
        ra_min_move = max(0.1, dec_min_move * 0.65)
        recommendation: dict[str, Any] = {
            "ra_min_move_pixels": round(ra_min_move, 3),
            "dec_min_move_pixels": round(dec_min_move, 3),
            "guide_exposure_min_seconds": 2.0,
            "guide_exposure_max_seconds": 4.0,
        }
        dec_drift_arcsec = linear_drift([(item[0], item[2]) for item in samples])
        mount = mount_status()
        declination = mount.get("dec_degrees") if mount.get("connected") else None
        cosine_declination = max(0.1, abs(math.cos(math.radians(float(declination or 0)))))
        polar_error = 3.8197 * abs(dec_drift_arcsec) / cosine_declination
        backlash = None
        backlash_error = None
        if measure_backlash and not assistant_stop.is_set():
            try:
                exposure_seconds = float(phd2_result("get_exposure")) / 1000
                with assistant_lock:
                    assistant_state.update({"state": "backlash", "message": "Measuring DEC backlash"})
                backlash = measure_dec_backlash(exposure_seconds, dec_drift_arcsec / pixel_scale)
                if backlash["classification"] == "excessive":
                    recommendation["dec_guide_mode"] = "South" if dec_drift_arcsec >= 0 else "North"
                elif backlash["classification"] == "compensatable":
                    recommendation["phd2_backlash_compensation_ms"] = backlash["recommended_compensation_ms"]
            except (ConnectionError, OSError, TimeoutError, ValueError, json.JSONDecodeError) as error:
                backlash_error = str(error)

        messages: list[dict[str, str]] = []
        average_snr = statistics.fmean(item[3] for item in samples)
        if average_snr < 10:
            messages.append({"category": "guide_star", "severity": "warning", "message": "Use a brighter guide star or increase guide exposure."})
        if polar_error > 10:
            messages.append({"category": "polar_alignment", "severity": "warning", "message": "Polar alignment error is above 10 arc-min; run Polar Alignment before imaging."})
        elif polar_error > 5:
            messages.append({"category": "polar_alignment", "severity": "advice", "message": "Polar alignment error is above 5 arc-min and can be improved."})
        if backlash and backlash["classification"] == "excessive":
            messages.append({"category": "mechanical", "severity": "warning", "message": "DEC backlash exceeds 3 seconds. Check balance and gear mesh; use one-direction DEC guiding."})
        if max(ra_values) - min(ra_values) > max(4.0, ra_rms * 6):
            messages.append({"category": "mechanical", "severity": "advice", "message": "Large RA excursions detected. Inspect cable drag, balance, and periodic error."})
        if max(dec_values) - min(dec_values) > max(4.0, dec_rms * 6):
            messages.append({"category": "mechanical", "severity": "advice", "message": "Large DEC excursions detected. Inspect cable drag, balance, and DEC gear engagement."})
        trace_step = max(1, len(samples) // 240)
        results = {
            "id": uuid.uuid4().hex,
            "completed_at": time.time(),
            "duration_seconds": round(time.monotonic() - started, 1),
            "samples": len(samples),
            "ra_rms_arcsec": round(ra_rms, 3),
            "dec_rms_arcsec": round(dec_rms, 3),
            "total_rms_arcsec": round(math.hypot(ra_rms, dec_rms), 3),
            "ra_peak_to_peak_arcsec": round(max(ra_values) - min(ra_values), 3),
            "dec_peak_to_peak_arcsec": round(max(dec_values) - min(dec_values), 3),
            "ra_drift_arcsec_per_min": round(linear_drift([(item[0], item[1]) for item in samples]), 3),
            "dec_drift_arcsec_per_min": round(dec_drift_arcsec, 3),
            "seeing_ra_arcsec": round(ra_seeing, 3),
            "seeing_dec_arcsec": round(dec_seeing, 3),
            "average_snr": round(average_snr, 1),
            "polar_alignment_error_arcmin": round(polar_error, 2),
            "polar_alignment_declination_degrees": declination,
            "polar_alignment_is_lower_bound": declination is None,
            "backlash": backlash,
            "backlash_error": backlash_error,
            "trace": [
                {"t": round(item[0], 1), "ra": round(item[1], 3), "dec": round(item[2], 3)}
                for item in samples[::trace_step]
            ],
            "messages": messages,
            "recommendations": recommendation,
        }
        save_assistant_history(results)
        with assistant_lock:
            assistant_state.update({"state": "complete", "results": results, "message": "Measurement complete"})
    except (ConnectionError, OSError, TimeoutError, ValueError, json.JSONDecodeError) as error:
        with assistant_lock:
            assistant_state.update({"state": "error", "message": str(error)})
    finally:
        try:
            if was_guiding and output_was_enabled:
                phd2_result("set_guide_output_enabled", [True])
            if was_guiding and phd2_result("get_app_state") != "Guiding":
                phd2_result(
                    "guide",
                    {
                        "settle": {"pixels": 0.5, "time": 5, "timeout": 30},
                        "recalibrate": False,
                    },
                )
        except (ConnectionError, OSError, TimeoutError, ValueError, json.JSONDecodeError):
            pass


def start_guiding_assistant(duration_seconds: int, measure_backlash: bool = True) -> dict[str, Any]:
    if duration_seconds < 60 or duration_seconds > 1800:
        raise ValueError("measurement duration must be between 60 and 1800 seconds")
    with assistant_lock:
        if assistant_state.get("state") in {"starting", "measuring"}:
            raise ValueError("the Guiding Assistant is already running")
        assistant_state.clear()
        assistant_state.update({"state": "starting", "samples": 0})
    assistant_stop.clear()
    threading.Thread(
        target=guiding_assistant_worker,
        args=(duration_seconds, measure_backlash),
        daemon=True,
    ).start()
    return assistant_snapshot()


def stop_guiding_assistant() -> dict[str, Any]:
    assistant_stop.set()
    return assistant_snapshot()


def apply_guiding_assistant(payload: dict[str, Any]) -> dict[str, Any]:
    if payload.get("confirmed") is not True:
        raise ValueError("explicit confirmation is required before changing guiding settings")
    snapshot = assistant_snapshot()
    results = snapshot.get("results")
    if snapshot.get("state") != "complete" or not isinstance(results, dict):
        raise ValueError("there are no completed Guiding Assistant results")
    recommendations = results.get("recommendations")
    if not isinstance(recommendations, dict):
        raise ValueError("recommendations are unavailable")
    applied: dict[str, float] = {}
    for axis, key in (("ra", "ra_min_move_pixels"), ("dec", "dec_min_move_pixels")):
        value = finite_number(recommendations.get(key), key)
        phd2_result("set_algo_param", [axis, "minMove", value])
        applied[key] = value
    dec_mode = recommendations.get("dec_guide_mode")
    if isinstance(dec_mode, str) and dec_mode in {"North", "South"}:
        phd2_result("set_dec_guide_mode", [dec_mode])
        applied["dec_guide_mode"] = dec_mode
    return {
        "status": "applied",
        "settings": applied,
        "backlash_compensation": recommendations.get("phd2_backlash_compensation_ms"),
        "backlash_note": "PHD2 adaptive backlash compensation requires a PHD2 restart and is handled separately.",
    }


def write_ini_values(path: Path, section: str, values: dict[str, str]) -> None:
    lines = path.read_text().splitlines()
    section_header = f"[{section}]"
    try:
        start = lines.index(section_header) + 1
    except ValueError:
        lines.extend([section_header])
        start = len(lines)
    end = len(lines)
    for index in range(start, len(lines)):
        if lines[index].startswith("[") and lines[index].endswith("]"):
            end = index
            break
    remaining = dict(values)
    for index in range(start, end):
        if "=" not in lines[index]:
            continue
        key = lines[index].split("=", 1)[0]
        if key in remaining:
            lines[index] = f"{key}={remaining.pop(key)}"
    for key, value in remaining.items():
        lines.insert(end, f"{key}={value}")
        end += 1
    temporary = path.with_suffix(".astrofield.tmp")
    temporary.write_text("\n".join(lines) + "\n")
    temporary.replace(path)


def apply_phd2_backlash_compensation(payload: dict[str, Any]) -> dict[str, Any]:
    if payload.get("confirmed") is not True:
        raise ValueError("explicit confirmation is required because PHD2 will restart")
    snapshot = assistant_snapshot()
    results = snapshot.get("results")
    if not isinstance(results, dict):
        raise ValueError("there are no completed assistant results")
    recommendations = results.get("recommendations")
    if not isinstance(recommendations, dict):
        raise ValueError("recommendations are unavailable")
    milliseconds = int(recommendations.get("phd2_backlash_compensation_ms", 0))
    if milliseconds < 100 or milliseconds > 3000:
        raise ValueError("adaptive backlash compensation is not appropriate for this measurement")
    if not PHD2_CONFIG_FILE.exists():
        raise ValueError("PHD2 configuration file was not found")

    if phd2_pid():
        phd2_result("shutdown")
        deadline = time.monotonic() + 10
        while phd2_pid() and time.monotonic() < deadline:
            time.sleep(0.25)
        if phd2_pid():
            raise ValueError("PHD2 did not close; backlash settings were not changed")
    profile_id = "1"
    for line in PHD2_CONFIG_FILE.read_text().splitlines():
        if line.startswith("currentProfile="):
            profile_id = line.split("=", 1)[1].strip()
            break
    write_ini_values(
        PHD2_CONFIG_FILE,
        f"profile/{profile_id}/scope",
        {
            "DecBacklashPulse": str(milliseconds),
            "DecBacklashFloor": "20",
            "DecBacklashCeiling": str(min(3000, int(milliseconds * 1.5))),
            "BacklashCompEnabled": "1",
        },
    )
    environment = os.environ.copy()
    environment.update({"DISPLAY": ":0", "XAUTHORITY": "/home/astroberry/.Xauthority"})
    subprocess.Popen(
        ["/usr/bin/phd2"],
        env=environment,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    return {"status": "applied", "milliseconds": milliseconds, "phd2_restarting": True}


FOCUS_STATES = ["Idle", "Complete", "Failed", "Aborted", "User input", "In progress", "Framing", "Changing filter"]
CAPTURE_STATES = [
    "Idle", "In progress", "Capturing", "Pause planned", "Paused", "Suspended", "Aborted", "Waiting",
    "Image received", "Dithering", "Focusing", "Filter focus", "Changing filter", "Guider settling",
    "Setting temperature", "Setting rotator", "Aligning", "Calibrating", "Meridian flip", "Complete",
]


def gdbus_call(path: str, interface: str, method: str, *arguments: str, timeout: int = 8) -> str:
    environment = os.environ.copy()
    environment["DBUS_SESSION_BUS_ADDRESS"] = "unix:path=/run/user/1000/bus"
    result = subprocess.run(
        [
            "/usr/bin/gdbus", "call", "--session", "--dest", "org.kde.kstars",
            "--object-path", path, "--method", f"{interface}.{method}", *arguments,
        ],
        capture_output=True,
        text=True,
        timeout=timeout,
        env=environment,
        check=False,
    )
    if result.returncode != 0:
        raise ConnectionError(result.stderr.strip() or "KStars/Ekos DBus is unavailable")
    return result.stdout.strip()


def dbus_number(output: str) -> float:
    match = re.search(r"(?:uint32|int32|double)\s+(-?[0-9]+(?:\.[0-9]+)?)", output)
    if not match:
        match = re.search(r"\((-?[0-9]+(?:\.[0-9]+)?),?\)", output)
    if not match:
        raise ValueError(f"Unexpected DBus response: {output[:120]}")
    return float(match.group(1))


def dbus_string(output: str) -> str:
    match = re.search(r"\('([^']*)',?\)", output)
    return match.group(1) if match else ""


def focus_config() -> dict[str, Any]:
    defaults: dict[str, Any] = {
        "temperature_enabled": False,
        "temperature_delta_c": 1.5,
        "time_enabled": False,
        "time_interval_minutes": 60,
        "only_during_capture": True,
        "resume_on_failure": False,
        "exposure_seconds": 2.0,
        "binning": 1,
        "auto_select_star": True,
        "subframe": False,
        "box_size": 64,
        "initial_step": 100,
        "max_travel": 1000,
        "tolerance_percent": 5.0,
        "manual_step": 100,
        "speed_factor": 1,
        "driver_backlash": 0,
        "af_overscan": 0,
        "settle_seconds": 1.0,
        "suspend_guiding": False,
        "filter": "",
        "last_success": None,
    }
    try:
        saved = json.loads(FOCUS_CONFIG_FILE.read_text())
        if isinstance(saved, dict):
            defaults.update(saved)
    except (OSError, json.JSONDecodeError):
        pass
    return defaults


def save_focus_config(payload: dict[str, Any]) -> dict[str, Any]:
    config = focus_config()
    boolean_keys = ("temperature_enabled", "time_enabled", "only_during_capture", "resume_on_failure", "auto_select_star", "subframe", "suspend_guiding")
    for key in boolean_keys:
        if key in payload:
            config[key] = bool(payload[key])
    ranges = {
        "temperature_delta_c": (0.1, 20.0), "time_interval_minutes": (5, 1440),
        "exposure_seconds": (0.1, 120.0), "binning": (1, 4), "box_size": (16, 512),
        "initial_step": (1, 100000), "max_travel": (10, 1000000), "tolerance_percent": (0.1, 50.0),
        "manual_step": (1, 100000), "speed_factor": (1, 10), "driver_backlash": (0, 100000),
        "af_overscan": (0, 100000), "settle_seconds": (0, 60),
    }
    for key, (minimum, maximum) in ranges.items():
        if key in payload:
            value = finite_number(payload[key], key)
            if value < minimum or value > maximum:
                raise ValueError(f"{key} must be between {minimum} and {maximum}")
            config[key] = int(value) if key in {"binning", "box_size", "initial_step", "max_travel", "manual_step", "speed_factor", "driver_backlash", "af_overscan", "time_interval_minutes"} else value
    if "filter" in payload:
        config["filter"] = str(payload["filter"])[:80]
    if isinstance(payload.get("last_success"), dict):
        config["last_success"] = payload["last_success"]
    STATE_DIRECTORY.mkdir(parents=True, exist_ok=True)
    temporary = FOCUS_CONFIG_FILE.with_suffix(".tmp")
    temporary.write_text(json.dumps(config, separators=(",", ":")))
    temporary.replace(FOCUS_CONFIG_FILE)
    return config


def focus_history() -> list[dict[str, Any]]:
    try:
        value = json.loads(FOCUS_HISTORY_FILE.read_text())
        return value if isinstance(value, list) else []
    except (OSError, json.JSONDecodeError):
        return []


def save_focus_history(entry: dict[str, Any]) -> None:
    history = focus_history()
    history.insert(0, entry)
    STATE_DIRECTORY.mkdir(parents=True, exist_ok=True)
    temporary = FOCUS_HISTORY_FILE.with_suffix(".tmp")
    temporary.write_text(json.dumps(history[:50], separators=(",", ":")))
    temporary.replace(FOCUS_HISTORY_FILE)


def focus_indi_status() -> dict[str, Any]:
    if PyIndi is None or not indi_pid():
        return {"connected": False, "temperature_sources": []}
    client = PyIndi.BaseClient()
    client.setServer("127.0.0.1", 7624)
    if not client.connectServer():
        return {"connected": False, "temperature_sources": []}
    try:
        time.sleep(0.25)
        result: dict[str, Any] = {"connected": False, "temperature_sources": []}
        temperatures: list[dict[str, Any]] = []
        for device in client.getDevices():
            if not device.isConnected():
                continue
            for property_name in ("FOCUS_TEMPERATURE", "TEMPERATURE", "WEATHER_TEMPERATURE", "CCD_TEMPERATURE"):
                vector = device.getNumber(property_name)
                if vector and len(vector) > 0:
                    temperatures.append({"device": device.getDeviceName(), "property": property_name, "value_c": vector[0].getValue()})
            absolute = device.getNumber("ABS_FOCUS_POSITION")
            relative = device.getNumber("REL_FOCUS_POSITION")
            if absolute or relative:
                result.update({
                    "connected": True,
                    "device": device.getDeviceName(),
                    "absolute": bool(absolute),
                    "relative": bool(relative),
                    "position": absolute[0].getValue() if absolute else None,
                    "max_position": (device.getNumber("FOCUS_MAX") or [None])[0].getValue() if device.getNumber("FOCUS_MAX") else None,
                    "can_abort": bool(device.getSwitch("FOCUS_ABORT_MOTION")),
                    "can_reverse": bool(device.getSwitch("FOCUS_REVERSE_MOTION")),
                    "reversed": bool(
                        device.getSwitch("FOCUS_REVERSE_MOTION")
                        and device.getSwitch("FOCUS_REVERSE_MOTION")[0].getState() == PyIndi.ISS_ON
                    ),
                    "can_sync": bool(device.getNumber("FOCUS_SYNC")),
                    "can_home": bool(device.getSwitch("FOCUS_HOME")),
                    "has_backlash": bool(device.getNumber("FOCUS_BACKLASH")),
                    "driver_backlash": device.getNumber("FOCUS_BACKLASH")[0].getValue() if device.getNumber("FOCUS_BACKLASH") else None,
                })
        result["temperature_sources"] = temperatures
        if temperatures:
            result["temperature_c"] = temperatures[0]["value_c"]
            result["temperature_source"] = temperatures[0]["device"]
        return result
    finally:
        client.disconnectServer()


def focus_module_status() -> dict[str, Any]:
    indi = focus_indi_status()
    payload: dict[str, Any] = {"ekos_available": False, "indi": indi, "controller": dict(focus_state)}
    try:
        focus_code = int(dbus_number(gdbus_call("/KStars/Ekos/Focus", "org.kde.kstars.Ekos.Focus", "status")))
        capture_code = int(dbus_number(gdbus_call("/KStars/Ekos/Capture", "org.kde.kstars.Ekos.Capture", "status")))
        payload.update({
            "ekos_available": True,
            "focus_state_code": focus_code,
            "focus_state": FOCUS_STATES[focus_code] if 0 <= focus_code < len(FOCUS_STATES) else str(focus_code),
            "capture_state_code": capture_code,
            "capture_state": CAPTURE_STATES[capture_code] if 0 <= capture_code < len(CAPTURE_STATES) else str(capture_code),
            "hfr": dbus_number(gdbus_call("/KStars/Ekos/Focus", "org.kde.kstars.Ekos.Focus", "getHFR")),
            "camera": dbus_string(gdbus_call("/KStars/Ekos/Focus", "org.kde.kstars.Ekos.Focus", "camera")),
            "focuser": dbus_string(gdbus_call("/KStars/Ekos/Focus", "org.kde.kstars.Ekos.Focus", "focuser")),
            "filter": dbus_string(gdbus_call("/KStars/Ekos/Focus", "org.kde.kstars.Ekos.Focus", "filter")),
            "exposure_seconds": dbus_number(gdbus_call("/KStars/Ekos/Focus", "org.kde.kstars.Ekos.Focus", "exposure")),
        })
    except (ConnectionError, OSError, subprocess.TimeoutExpired, ValueError):
        pass
    config = focus_config()
    last = config.get("last_success")
    if isinstance(last, dict):
        payload["last_success"] = last
        payload["minutes_since_focus"] = round((time.time() - float(last.get("time", time.time()))) / 60, 1)
        if indi.get("temperature_c") is not None and last.get("temperature_c") is not None:
            payload["temperature_delta_c"] = round(float(indi["temperature_c"]) - float(last["temperature_c"]), 2)
    return payload


def configure_ekos_focus(config: dict[str, Any]) -> None:
    path = "/KStars/Ekos/Focus"
    interface = "org.kde.kstars.Ekos.Focus"
    gdbus_call(path, interface, "setExposure", str(float(config["exposure_seconds"])))
    gdbus_call(path, interface, "setBinning", str(int(config["binning"])), str(int(config["binning"])))
    gdbus_call(path, interface, "setAutoStarEnabled", str(bool(config["auto_select_star"])).lower())
    gdbus_call(path, interface, "setAutoSubFrameEnabled", str(bool(config["subframe"])).lower())
    gdbus_call(
        path, interface, "setAutoFocusParameters", str(int(config["box_size"])),
        str(int(config["initial_step"])), str(int(config["max_travel"])), str(float(config["tolerance_percent"])),
    )
    if config.get("filter"):
        gdbus_call(path, interface, "setFilter", str(config["filter"]))


def autofocus_worker(reason: str) -> None:
    capture_was_active = False
    config = focus_config()
    started_at = time.time()
    try:
        with focus_lock:
            focus_state.update({"state": "waiting_for_capture", "reason": reason, "started_at": started_at, "message": "Waiting for the current exposure to finish"})
        capture_code = int(dbus_number(gdbus_call("/KStars/Ekos/Capture", "org.kde.kstars.Ekos.Capture", "status")))
        capture_was_active = capture_code in {1, 2, 3, 7, 8, 9, 10, 12, 13, 14, 15, 16, 17}
        if capture_was_active:
            gdbus_call("/KStars/Ekos/Capture", "org.kde.kstars.Ekos.Capture", "pause")
            deadline = time.monotonic() + 900
            while time.monotonic() < deadline:
                capture_code = int(dbus_number(gdbus_call("/KStars/Ekos/Capture", "org.kde.kstars.Ekos.Capture", "status")))
                if capture_code == 4:
                    break
                time.sleep(2)
            if capture_code != 4:
                raise TimeoutError("Capture did not reach a safe pause point")
        configure_ekos_focus(config)
        with focus_lock:
            focus_state.update({"state": "running", "message": "Ekos autofocus is running"})
        gdbus_call("/KStars/Ekos/Focus", "org.kde.kstars.Ekos.Focus", "start")
        deadline = time.monotonic() + 1200
        saw_progress = False
        final_code = 0
        while time.monotonic() < deadline:
            final_code = int(dbus_number(gdbus_call("/KStars/Ekos/Focus", "org.kde.kstars.Ekos.Focus", "status")))
            saw_progress = saw_progress or final_code in {4, 5, 6, 7}
            if saw_progress and final_code in {1, 2, 3}:
                break
            time.sleep(2)
        if not saw_progress or final_code not in {1, 2, 3}:
            raise TimeoutError("Autofocus did not complete within the configured timeout")
        status = FOCUS_STATES[final_code]
        indi = focus_indi_status()
        hfr = dbus_number(gdbus_call("/KStars/Ekos/Focus", "org.kde.kstars.Ekos.Focus", "getHFR"))
        entry = {
            "time": time.time(), "reason": reason, "status": status, "hfr": hfr,
            "position": indi.get("position"), "temperature_c": indi.get("temperature_c"),
            "duration_seconds": round(time.time() - started_at, 1),
        }
        save_focus_history(entry)
        if final_code == 1:
            config["last_success"] = entry
            save_focus_config(config)
        should_resume = capture_was_active and (final_code == 1 or bool(config.get("resume_on_failure")))
        if should_resume:
            gdbus_call("/KStars/Ekos/Capture", "org.kde.kstars.Ekos.Capture", "toggleSequence")
        with focus_lock:
            focus_state.update({
                "state": "complete" if final_code == 1 else "failed", "result": entry,
                "capture_resumed": should_resume,
                "message": "Imaging resumed" if should_resume else "Capture remains paused for review",
            })
    except (ConnectionError, OSError, subprocess.TimeoutExpired, TimeoutError, ValueError) as error:
        with focus_lock:
            focus_state.update({"state": "error", "message": str(error), "capture_resumed": False})


def start_autofocus(reason: str) -> dict[str, Any]:
    with focus_lock:
        if focus_state.get("state") in {"waiting_for_capture", "running"}:
            raise ValueError("Autofocus is already running")
        focus_state.clear()
        focus_state.update({"state": "starting", "reason": reason})
    threading.Thread(target=autofocus_worker, args=(reason,), daemon=True).start()
    return dict(focus_state)


def focus_command(payload: dict[str, Any]) -> dict[str, Any]:
    action = str(payload.get("action", ""))
    if action == "autofocus":
        return start_autofocus("manual")
    if action == "abort":
        gdbus_call("/KStars/Ekos/Focus", "org.kde.kstars.Ekos.Focus", "abort")
        with focus_lock:
            focus_state.update({"state": "aborted", "message": "Autofocus aborted by user"})
        return dict(focus_state)
    if action in {"goto", "sync", "backlash", "reverse", "abort_motion", "home"}:
        if PyIndi is None or not indi_pid():
            raise ValueError("INDI is not running")
        client = PyIndi.BaseClient()
        client.setServer("127.0.0.1", 7624)
        if not client.connectServer():
            raise ValueError("INDI is not ready")
        try:
            time.sleep(0.2)
            for device in client.getDevices():
                if not device.isConnected() or not (device.getNumber("ABS_FOCUS_POSITION") or device.getNumber("REL_FOCUS_POSITION")):
                    continue
                if action in {"goto", "sync", "backlash"}:
                    property_name = {"goto": "ABS_FOCUS_POSITION", "sync": "FOCUS_SYNC", "backlash": "FOCUS_BACKLASH"}[action]
                    vector = device.getNumber(property_name)
                    if not vector:
                        raise ValueError(f"Focuser does not support {action}")
                    value = finite_number(payload.get("value"), "value")
                    vector[0].setValue(value)
                    client.sendNewProperty(vector)
                    return {"status": "applied", "action": action, "value": value}
                switch_name = (
                    "FOCUS_REVERSE_MOTION" if action == "reverse"
                    else "FOCUS_HOME" if action == "home"
                    else "FOCUS_ABORT_MOTION"
                )
                switches = device.getSwitch(switch_name)
                if not switches:
                    raise ValueError(f"Focuser does not support {action}")
                if action == "reverse":
                    enabled = bool(payload.get("enabled"))
                    switches[0].setState(PyIndi.ISS_ON if enabled else PyIndi.ISS_OFF)
                    if len(switches) > 1:
                        switches[1].setState(PyIndi.ISS_OFF if enabled else PyIndi.ISS_ON)
                else:
                    switches[0].setState(PyIndi.ISS_ON)
                client.sendNewProperty(switches)
                return {"status": "applied", "action": action}
            raise ValueError("No connected focuser was found")
        finally:
            client.disconnectServer()
    config = focus_config()
    if action in {"in", "out"}:
        steps = int(finite_number(payload.get("steps", config["manual_step"]), "steps"))
        if steps < 1 or steps > 100000:
            raise ValueError("steps must be between 1 and 100000")
        method = "focusIn" if action == "in" else "focusOut"
        gdbus_call("/KStars/Ekos/Focus", "org.kde.kstars.Ekos.Focus", method, str(steps), str(int(config["speed_factor"])))
        return {"status": "moving", "direction": action, "steps": steps}
    if action == "capture":
        gdbus_call("/KStars/Ekos/Focus", "org.kde.kstars.Ekos.Focus", "capture", str(float(config["settle_seconds"])))
        return {"status": "capturing"}
    raise ValueError("unsupported focus command")


def autofocus_trigger_worker() -> None:
    while True:
        try:
            config = focus_config()
            if (config.get("temperature_enabled") or config.get("time_enabled")) and focus_state.get("state") not in {"waiting_for_capture", "running", "starting"}:
                status = focus_module_status()
                if status.get("ekos_available"):
                    capture_active = status.get("capture_state_code") in {1, 2, 3, 7, 8, 9, 10, 12, 13, 14, 15, 16, 17}
                    if not config.get("only_during_capture") or capture_active:
                        last = config.get("last_success")
                        if isinstance(last, dict):
                            if config.get("temperature_enabled") and status.get("temperature_delta_c") is not None and abs(float(status["temperature_delta_c"])) >= float(config["temperature_delta_c"]):
                                start_autofocus("temperature")
                            elif config.get("time_enabled") and status.get("minutes_since_focus") is not None and float(status["minutes_since_focus"]) >= float(config["time_interval_minutes"]):
                                start_autofocus("time")
        except (ConnectionError, OSError, subprocess.TimeoutExpired, ValueError):
            pass
        time.sleep(10)


def system_payload() -> dict[str, object]:
    return {
        "status": "ok",
        "hostname": socket.gethostname(),
        "architecture": platform.machine(),
        "astroberry_version": package_version("astroberry-os"),
        "kstars_version": package_version("kstars-bleeding"),
        "indi_version": package_version("indi-bin"),
        "indi_running": bool(indi_pid()),
        "phone_location_saved": LOCATION_FILE.exists(),
    }


def system_details() -> dict[str, object]:
    disk = shutil.disk_usage("/")
    try:
        temperature = int(Path("/sys/class/thermal/thermal_zone0/temp").read_text()) / 1000
    except (OSError, ValueError):
        temperature = None
    try:
        memory_lines = Path("/proc/meminfo").read_text().splitlines()
        memory = {
            line.split(":", 1)[0]: int(line.split()[1]) * 1024
            for line in memory_lines
            if line.startswith(("MemTotal:", "MemAvailable:"))
        }
    except (OSError, ValueError, IndexError):
        memory = {}
    astrometry_indexes = list(Path("/usr/share/astrometry").glob("index-*.fits"))
    astap_databases: list[Path] = []
    for root in (
        Path("/usr/share/astap"),
        Path("/opt/astap"),
    ):
        try:
            if root.exists():
                for pattern in ("d*.290", "g*.1476", "h*.1476", "w*.1476"):
                    astap_databases.extend(root.glob(pattern))
        except OSError:
            continue
    cached_updates = [
        line
        for line in command("apt", "list", "--upgradable").splitlines()
        if line and not line.startswith("Listing")
    ]
    return {
        **system_payload(),
        "kernel": platform.release(),
        "uptime_seconds": float(Path("/proc/uptime").read_text().split()[0]),
        "temperature_c": temperature,
        "memory": memory,
        "storage": {
            "total_bytes": disk.total,
            "used_bytes": disk.used,
            "free_bytes": disk.free,
        },
        "packages": {
            "astap": package_version("astap"),
            "astrometry_net": package_version("astrometry.net"),
            "stellarsolver": package_version("libstellarsolver"),
            "kstars": package_version("kstars-bleeding"),
            "indi": package_version("indi-bin"),
        },
        "solver_data": {
            "astap_database_files": len(astap_databases),
            "astap_ready": bool(astap_databases),
            "astrometry_index_files": len(astrometry_indexes),
            "astrometry_ready": bool(astrometry_indexes),
        },
        "cached_updates": cached_updates[:100],
        "cached_update_count": len(cached_updates),
    }


def equatorial_to_horizontal(
    ra_degrees: float,
    declination_degrees: float,
    latitude_degrees: float,
    longitude_degrees: float,
) -> tuple[float, float]:
    julian_date = time.time() / 86400 + 2440587.5
    days_since_j2000 = julian_date - 2451545.0
    gmst_hours = (18.697374558 + 24.06570982441908 * days_since_j2000) % 24
    local_sidereal_degrees = (gmst_hours * 15 + longitude_degrees) % 360
    hour_angle = math.radians(
        (local_sidereal_degrees - ra_degrees + 540) % 360 - 180
    )
    declination = math.radians(declination_degrees)
    latitude = math.radians(latitude_degrees)
    altitude = math.asin(
        math.sin(declination) * math.sin(latitude)
        + math.cos(declination) * math.cos(latitude) * math.cos(hour_angle)
    )
    azimuth = math.atan2(
        math.sin(hour_angle),
        math.cos(hour_angle) * math.sin(latitude)
        - math.tan(declination) * math.cos(latitude),
    )
    return math.degrees(altitude), (math.degrees(azimuth) + 180) % 360


def catalog_object(row: sqlite3.Row, location: dict[str, object]) -> dict[str, object]:
    altitude, azimuth = equatorial_to_horizontal(
        float(row["ra"]),
        float(row["dec"]),
        float(location["latitude"]),
        float(location["longitude"]),
    )
    return {
        "name": row["name"],
        "long_name": row["long_name"] or "",
        "catalog_identifier": row["catalog_identifier"],
        "type": int(row["type"]),
        "ra_degrees": float(row["ra"]),
        "dec_degrees": float(row["dec"]),
        "altitude_degrees": round(altitude, 3),
        "azimuth_degrees": round(azimuth, 3),
        "magnitude": row["magnitude"],
        "major_axis_arcmin": row["major_axis"],
        "minor_axis_arcmin": row["minor_axis"],
        "position_angle_degrees": row["position_angle"],
    }


def sky_catalog(query: str = "", min_altitude: float = 20, limit: int = 50) -> dict[str, object]:
    location = load_location()
    if location is None:
        raise ValueError("phone location is required")
    if not OPEN_NGC_DATABASE.exists():
        raise FileNotFoundError("KStars OpenNGC catalogue is unavailable")
    limit = max(1, min(limit, 200))
    connection = sqlite3.connect(f"file:{OPEN_NGC_DATABASE}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        if query:
            match = f"%{query.strip()}%"
            rows = connection.execute(
                """SELECT * FROM cat WHERE name LIKE ? OR long_name LIKE ?
                   OR catalog_identifier LIKE ? ORDER BY magnitude IS NULL, magnitude LIMIT 200""",
                (match, match, match),
            ).fetchall()
        else:
            rows = connection.execute(
                """SELECT * FROM cat WHERE magnitude IS NOT NULL AND magnitude <= 12
                   ORDER BY magnitude LIMIT 4000"""
            ).fetchall()
    finally:
        connection.close()
    objects = [catalog_object(row, location) for row in rows]
    objects = [item for item in objects if item["altitude_degrees"] >= min_altitude]
    objects.sort(key=lambda item: (-float(item["altitude_degrees"]), item["magnitude"] or 99))
    return {
        "source": "KStars OpenNGC",
        "catalog_license": "CC-BY-SA-4.0",
        "generated_at": time.time(),
        "minimum_altitude_degrees": min_altitude,
        "objects": objects[:limit],
    }


def installed_drivers(group: str = "", search: str = "") -> dict[str, object]:
    root = ET.parse(INDI_DRIVERS_FILE).getroot()
    matches: list[dict[str, object]] = []
    for device_group in root.findall("devGroup"):
        group_name = device_group.get("group", "Other")
        if group and group.casefold() not in group_name.casefold():
            continue
        for device in device_group.findall("device"):
            label = device.get("label", "Unknown")
            manufacturer = device.get("manufacturer", "Unknown")
            driver = device.find("driver")
            if driver is None or not driver.text:
                continue
            haystack = f"{label} {manufacturer} {driver.text}"
            if search and search.casefold() not in haystack.casefold():
                continue
            matches.append(
                {
                    "group": group_name,
                    "label": label,
                    "manufacturer": manufacturer,
                    "driver": driver.text,
                    "driver_name": driver.get("name", label),
                    "version": device.findtext("version", "unknown"),
                }
            )
    matches.sort(key=lambda item: (str(item["manufacturer"]), str(item["label"])))
    return {"source": "INDI drivers.xml", "drivers": matches[:500]}


def validate_equipment_profile(payload: dict[str, Any]) -> dict[str, object]:
    telescope = payload.get("telescope")
    if not isinstance(telescope, dict):
        raise ValueError("telescope is required")
    focal_length = finite_number(telescope.get("focal_length_mm"), "focal_length_mm")
    aperture = finite_number(telescope.get("aperture_mm"), "aperture_mm")
    if not 10 <= focal_length <= 20000 or not 10 <= aperture <= 2000:
        raise ValueError("telescope dimensions are outside the supported range")
    profile: dict[str, object] = {
        "name": str(payload.get("name", "Default rig"))[:80],
        "telescope": {
            "name": str(telescope.get("name", "Custom telescope"))[:120],
            "focal_length_mm": focal_length,
            "aperture_mm": aperture,
            "reducer_factor": finite_number(telescope.get("reducer_factor", 1), "reducer_factor"),
        },
        "main_camera": payload.get("main_camera"),
        "guide_camera": payload.get("guide_camera"),
        "focuser": payload.get("focuser"),
        "updated_at": time.time(),
    }
    return profile


def save_equipment_profile(profile: dict[str, object]) -> None:
    STATE_DIRECTORY.mkdir(parents=True, exist_ok=True)
    EQUIPMENT_PROFILES_DIRECTORY.mkdir(parents=True, exist_ok=True)
    profile_id = str(profile.get("id") or uuid.uuid4().hex)
    profile["id"] = profile_id
    profile_path = EQUIPMENT_PROFILES_DIRECTORY / f"{profile_id}.json"
    profile_temporary = profile_path.with_suffix(".tmp")
    profile_temporary.write_text(json.dumps(profile, separators=(",", ":")))
    profile_temporary.replace(profile_path)
    ACTIVE_PROFILE_FILE.write_text(profile_id)
    temporary = EQUIPMENT_FILE.with_suffix(".tmp")
    temporary.write_text(json.dumps(profile, separators=(",", ":")))
    temporary.replace(EQUIPMENT_FILE)


def equipment_profiles() -> dict[str, object]:
    profiles: list[dict[str, object]] = []
    try:
        active_id = ACTIVE_PROFILE_FILE.read_text().strip()
    except OSError:
        active_id = ""
    if EQUIPMENT_PROFILES_DIRECTORY.exists():
        for path in EQUIPMENT_PROFILES_DIRECTORY.glob("*.json"):
            try:
                profile = json.loads(path.read_text())
                if isinstance(profile, dict):
                    profiles.append(profile)
            except (OSError, json.JSONDecodeError):
                continue
    if not profiles and EQUIPMENT_FILE.exists():
        try:
            legacy = json.loads(EQUIPMENT_FILE.read_text())
            if isinstance(legacy, dict):
                profiles.append(legacy)
                active_id = str(legacy.get("id", ""))
        except (OSError, json.JSONDecodeError):
            pass
    profiles.sort(key=lambda profile: str(profile.get("name", "")).casefold())
    return {"active_profile_id": active_id, "profiles": profiles}


def select_equipment_profile(profile_id: str) -> dict[str, object]:
    if not profile_id or not profile_id.isalnum() or len(profile_id) > 64:
        raise ValueError("invalid profile id")
    path = EQUIPMENT_PROFILES_DIRECTORY / f"{profile_id}.json"
    try:
        profile = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError("equipment profile was not found") from error
    ACTIVE_PROFILE_FILE.write_text(profile_id)
    temporary = EQUIPMENT_FILE.with_suffix(".tmp")
    temporary.write_text(json.dumps(profile, separators=(",", ":")))
    temporary.replace(EQUIPMENT_FILE)
    return profile


def safe_storage_path(relative_path: str) -> Path:
    candidate = (STORAGE_ROOT / relative_path.lstrip("/\\")).resolve()
    root = STORAGE_ROOT.resolve()
    if candidate != root and root not in candidate.parents:
        raise ValueError("path is outside the image library")
    return candidate


def storage_status() -> dict[str, object]:
    usage = shutil.disk_usage(STORAGE_ROOT if STORAGE_ROOT.exists() else STORAGE_ROOT.parent)
    return {
        "root": str(STORAGE_ROOT),
        "total_bytes": usage.total,
        "used_bytes": usage.used,
        "free_bytes": usage.free,
        "smb_share": "AstroField Images",
        "hostname": socket.gethostname(),
    }


def storage_listing(relative_path: str) -> dict[str, object]:
    directory = safe_storage_path(relative_path)
    if not directory.is_dir():
        raise ValueError("directory was not found")
    entries: list[dict[str, object]] = []
    for path in sorted(directory.iterdir(), key=lambda item: (not item.is_dir(), item.name.casefold()))[:500]:
        stat = path.stat()
        entries.append(
            {
                "name": path.name,
                "path": str(path.relative_to(STORAGE_ROOT)),
                "type": "directory" if path.is_dir() else "file",
                "size_bytes": stat.st_size if path.is_file() else 0,
                "modified_at": stat.st_mtime,
                "is_fits": path.suffix.casefold() in {".fits", ".fit", ".fts"},
            }
        )
    return {"path": str(directory.relative_to(STORAGE_ROOT)), "entries": entries}


def finite_number(value: Any, name: str) -> float:
    if isinstance(value, bool):
        raise ValueError(f"{name} must be a number")
    try:
        number = float(value)
    except (TypeError, ValueError) as error:
        raise ValueError(f"{name} must be a number") from error
    if not math.isfinite(number):
        raise ValueError(f"{name} must be finite")
    return number


def validate_location(payload: dict[str, Any]) -> dict[str, object]:
    latitude = finite_number(payload.get("latitude"), "latitude")
    longitude = finite_number(payload.get("longitude"), "longitude")
    altitude = finite_number(payload.get("altitude", 0), "altitude")
    accuracy = finite_number(payload.get("accuracy", 0), "accuracy")

    if not -90 <= latitude <= 90:
        raise ValueError("latitude must be between -90 and 90")
    if not -180 <= longitude <= 180:
        raise ValueError("longitude must be between -180 and 180")
    if not -500 <= altitude <= 10000:
        raise ValueError("altitude is outside the supported range")
    if not 0 <= accuracy <= 100000:
        raise ValueError("accuracy is outside the supported range")

    return {
        "source": "phone",
        "latitude": latitude,
        "longitude": longitude,
        "indi_longitude": longitude % 360,
        "altitude": altitude,
        "accuracy": accuracy,
        "captured_at": str(payload.get("captured_at", "")),
        "received_at": time.time(),
    }


def save_location(location: dict[str, object]) -> None:
    STATE_DIRECTORY.mkdir(parents=True, exist_ok=True)
    temporary = LOCATION_FILE.with_suffix(".tmp")
    temporary.write_text(json.dumps(location, separators=(",", ":")))
    temporary.replace(LOCATION_FILE)


def load_location() -> dict[str, object] | None:
    try:
        return json.loads(LOCATION_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def apply_location_to_indi(location: dict[str, object]) -> dict[str, object]:
    if PyIndi is None:
        return {"status": "pending", "reason": "pyindi_unavailable"}
    if not indi_pid():
        return {"status": "pending", "reason": "indi_not_running"}

    client = PyIndi.BaseClient()
    client.setServer("127.0.0.1", 7624)
    if not client.connectServer():
        return {"status": "pending", "reason": "indi_not_ready"}

    try:
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            for device in client.getDevices():
                try:
                    coordinates = device.getNumber("GEOGRAPHIC_COORD")
                    if not device.isConnected() or not coordinates:
                        continue

                    latitude = float(location["latitude"])
                    longitude = float(location["indi_longitude"])
                    altitude = float(location["altitude"])
                    unchanged = (
                        abs(coordinates[0].getValue() - latitude) < 0.00001
                        and abs(coordinates[1].getValue() - longitude) < 0.00001
                        and abs(coordinates[2].getValue() - altitude) < 0.5
                    )
                    if not unchanged:
                        coordinates[0].setValue(latitude)
                        coordinates[1].setValue(longitude)
                        coordinates[2].setValue(altitude)
                        client.sendNewProperty(coordinates)
                    return {
                        "status": "applied",
                        "device": device.getDeviceName(),
                        "changed": not unchanged,
                    }
                except (IndexError, TypeError, ValueError):
                    continue
            time.sleep(0.15)
        return {"status": "pending", "reason": "telescope_not_connected"}
    finally:
        client.disconnectServer()


def mount_status() -> dict[str, object]:
    if PyIndi is None or not indi_pid():
        return {"connected": False, "reason": "indi_not_running"}
    client = PyIndi.BaseClient()
    client.setServer("127.0.0.1", 7624)
    if not client.connectServer():
        return {"connected": False, "reason": "indi_not_ready"}
    try:
        time.sleep(0.3)
        for device in client.getDevices():
            if not device.isConnected():
                continue
            coordinates = device.getNumber("EQUATORIAL_EOD_COORD") or device.getNumber(
                "EQUATORIAL_COORD"
            )
            if coordinates and len(coordinates) >= 2:
                return {
                    "connected": True,
                    "device": device.getDeviceName(),
                    "ra_hours": coordinates[0].getValue(),
                    "dec_degrees": coordinates[1].getValue(),
                }
        return {"connected": False, "reason": "mount_not_connected"}
    finally:
        client.disconnectServer()


def indi_number_map(vector: object) -> dict[str, float]:
    """Collapse an INDI number vector into a {element_name: value} mapping."""
    values: dict[str, float] = {}
    if not vector:
        return values
    for index in range(len(vector)):
        element = vector[index]
        try:
            values[element.getName()] = float(element.getValue())
        except (AttributeError, TypeError, ValueError):
            continue
    return values


def indi_active_switch(vector: object) -> str | None:
    """Return the name of the enabled element in an INDI switch vector, if any."""
    if not vector or PyIndi is None:
        return None
    for index in range(len(vector)):
        element = vector[index]
        try:
            if element.getState() == PyIndi.ISS_ON:
                return element.getName()
        except (AttributeError, TypeError):
            continue
    return None


def active_equipment_profile() -> dict[str, object] | None:
    """Load the active equipment profile (mirrored to equipment.json)."""
    try:
        data = json.loads(EQUIPMENT_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return None
    return data if isinstance(data, dict) else None


def camera_from_indi(device: object) -> dict[str, object] | None:
    """Read CCD_INFO/CCD_BINNING for one INDI device, or None if it is not a camera."""
    info = indi_number_map(device.getNumber("CCD_INFO"))
    if not info:
        return None
    pixel_x = info.get("CCD_PIXEL_SIZE_X") or info.get("CCD_PIXEL_SIZE")
    pixel_y = info.get("CCD_PIXEL_SIZE_Y") or info.get("CCD_PIXEL_SIZE")
    sensor_px_x = info.get("CCD_MAX_X")
    sensor_px_y = info.get("CCD_MAX_Y")
    if not (pixel_x and pixel_y and sensor_px_x and sensor_px_y):
        return None
    binning = indi_number_map(device.getNumber("CCD_BINNING"))
    bin_x = int(binning.get("HOR_BIN", 1)) or 1
    bin_y = int(binning.get("VER_BIN", 1)) or 1
    return {
        "name": device.getDeviceName(),
        "connected": bool(device.isConnected()),
        "pixel_size_um_x": round(float(pixel_x), 4),
        "pixel_size_um_y": round(float(pixel_y), 4),
        "sensor_px_x": int(sensor_px_x),
        "sensor_px_y": int(sensor_px_y),
        "sensor_mm_x": round(float(sensor_px_x) * float(pixel_x) / 1000, 4),
        "sensor_mm_y": round(float(sensor_px_y) * float(pixel_y) / 1000, 4),
        "binning_x": bin_x,
        "binning_y": bin_y,
        "bits_per_pixel": int(info.get("CCD_BITSPERPIXEL", 0)) or None,
    }


def framing_snapshot() -> dict[str, object]:
    """Single INDI pass: camera geometry, telescope focal length and mount position."""
    offline: dict[str, object] = {
        "indi_running": False,
        "cameras": [],
        "selected": None,
        "indi_focal_mm": None,
        "mount": {"connected": False, "reason": "indi_not_running"},
    }
    if PyIndi is None or not indi_pid():
        return offline
    client = PyIndi.BaseClient()
    client.setServer("127.0.0.1", 7624)
    if not client.connectServer():
        return offline
    try:
        time.sleep(0.4)
        cameras: list[dict[str, object]] = []
        indi_focal: float | None = None
        mount: dict[str, object] = {"connected": False, "reason": "mount_not_connected"}
        for device in client.getDevices():
            camera = camera_from_indi(device)
            if camera:
                cameras.append(camera)
            scope = indi_number_map(device.getNumber("TELESCOPE_INFO"))
            focal = scope.get("TELESCOPE_FOCAL_LENGTH")
            if indi_focal is None and focal and focal > 0:
                indi_focal = float(focal)
            if not mount["connected"] and device.isConnected():
                coordinates = device.getNumber("EQUATORIAL_EOD_COORD") or device.getNumber(
                    "EQUATORIAL_COORD"
                )
                if coordinates and len(coordinates) >= 2:
                    mount = {
                        "connected": True,
                        "device": device.getDeviceName(),
                        "ra_hours": coordinates[0].getValue(),
                        "dec_degrees": coordinates[1].getValue(),
                        "pier_side": indi_active_switch(
                            device.getSwitch("TELESCOPE_PIER_SIDE")
                        ),
                    }
        selected = next((item["name"] for item in cameras if item["connected"]), None)
        if selected is None and cameras:
            selected = cameras[0]["name"]
        return {
            "indi_running": True,
            "cameras": cameras,
            "selected": selected,
            "indi_focal_mm": indi_focal,
            "mount": mount,
        }
    finally:
        client.disconnectServer()


def framing_geometry() -> dict[str, object]:
    """Combine the saved equipment profile with live INDI geometry into framing values."""
    profile = active_equipment_profile() or {}
    telescope = profile.get("telescope")
    telescope = telescope if isinstance(telescope, dict) else {}
    profile_focal: float | None = None
    reducer = 1.0
    try:
        if telescope.get("focal_length_mm") is not None:
            profile_focal = float(telescope["focal_length_mm"])
        reducer = float(telescope.get("reducer_factor", 1) or 1)
    except (TypeError, ValueError):
        profile_focal = None
        reducer = 1.0
    profile_effective = round(profile_focal * reducer, 2) if profile_focal else None

    snapshot = framing_snapshot()
    indi_focal = snapshot.get("indi_focal_mm")

    # Authoritative focal length is the saved profile; the INDI TELESCOPE_INFO value
    # is surfaced for reference and any significant mismatch is flagged.
    effective_focal = profile_effective
    focal_source: str | None = "equipment_profile"
    if effective_focal is None and indi_focal:
        effective_focal = round(float(indi_focal), 2)
        focal_source = "indi_telescope_info"
    if effective_focal is None:
        focal_source = None

    mismatch = None
    if profile_effective and indi_focal:
        delta = abs(profile_effective - float(indi_focal))
        mismatch = {
            "profile_effective_focal_mm": profile_effective,
            "indi_focal_mm": round(float(indi_focal), 2),
            "delta_mm": round(delta, 2),
            "significant": delta > max(5.0, 0.02 * profile_effective),
        }

    selected_name = snapshot.get("selected")
    camera = next(
        (item for item in snapshot.get("cameras", []) if item["name"] == selected_name),
        None,
    )

    field_of_view = None
    if camera and effective_focal:
        scale = 206.265 * camera["pixel_size_um_x"] * camera["binning_x"] / effective_focal
        field_of_view = {
            "width_deg": round(camera["sensor_mm_x"] / effective_focal * 57.29578, 4),
            "height_deg": round(camera["sensor_mm_y"] / effective_focal * 57.29578, 4),
            "scale_arcsec_per_px": round(scale, 3),
            "binning_x": camera["binning_x"],
            "binning_y": camera["binning_y"],
        }

    camera_reason: str | None = None
    if camera is None:
        if not snapshot.get("indi_running"):
            camera_reason = "indi_not_running"
        elif not snapshot.get("cameras"):
            camera_reason = "no_camera_with_ccd_info"
        else:
            camera_reason = "selected_camera_unavailable"

    return {
        "generated_at": time.time(),
        "indi_running": snapshot.get("indi_running", False),
        "telescope_name": telescope.get("name"),
        "focal_length": {
            "profile_focal_mm": profile_focal,
            "reducer_factor": reducer,
            "profile_effective_focal_mm": profile_effective,
            "indi_focal_mm": round(float(indi_focal), 2) if indi_focal else None,
            "effective_focal_mm": effective_focal,
            "source": focal_source,
            "mismatch": mismatch,
        },
        "camera": camera,
        "camera_unavailable_reason": camera_reason,
        "cameras_detected": snapshot.get("cameras", []),
        "selected_camera": selected_name,
        "field_of_view": field_of_view,
        "mount": snapshot.get("mount"),
    }


def indi_devices() -> dict[str, object]:
    if PyIndi is None or not indi_pid():
        return {"indi_running": False, "devices": []}
    client = PyIndi.BaseClient()
    client.setServer("127.0.0.1", 7624)
    if not client.connectServer():
        return {"indi_running": False, "devices": []}
    try:
        time.sleep(0.4)
        devices: list[dict[str, object]] = []
        for device in client.getDevices():
            camera = bool(device.getNumber("CCD_EXPOSURE"))
            focuser = bool(
                device.getNumber("ABS_FOCUS_POSITION")
                or device.getNumber("REL_FOCUS_POSITION")
                or device.getSwitch("FOCUS_MOTION")
            )
            mount = bool(
                device.getNumber("EQUATORIAL_EOD_COORD")
                or device.getNumber("EQUATORIAL_COORD")
            )
            devices.append(
                {
                    "name": device.getDeviceName(),
                    "connected": bool(device.isConnected()),
                    "roles": {
                        "camera": camera,
                        "focuser": focuser,
                        "mount": mount,
                    },
                    "capabilities": {
                        "cooling": bool(
                            device.getNumber("CCD_TEMPERATURE")
                            or device.getSwitch("CCD_COOLER")
                        ),
                        "gain": bool(
                            device.getNumber("CCD_GAIN")
                            or device.getNumber("CCD_CONTROLS")
                        ),
                        "offset": bool(
                            device.getNumber("CCD_OFFSET")
                            or device.getNumber("CCD_CONTROLS")
                        ),
                        "dew_heater": bool(
                            device.getNumber("DEW_HEATER")
                            or device.getSwitch("DEW_HEATER")
                            or device.getNumber("CCD_DEW_HEATER")
                        ),
                        "absolute_focus": bool(
                            device.getNumber("ABS_FOCUS_POSITION")
                        ),
                        "relative_focus": bool(
                            device.getNumber("REL_FOCUS_POSITION")
                        ),
                        "focus_backlash": bool(
                            device.getNumber("FOCUS_BACKLASH")
                        ),
                    },
                }
            )
        return {"indi_running": True, "devices": devices}
    finally:
        client.disconnectServer()


def mount_goto(payload: dict[str, Any]) -> dict[str, object]:
    ra_hours = finite_number(payload.get("ra_hours"), "ra_hours")
    declination = finite_number(payload.get("dec_degrees"), "dec_degrees")
    if not 0 <= ra_hours < 24 or not -90 <= declination <= 90:
        raise ValueError("coordinates are outside the supported range")
    if PyIndi is None or not indi_pid():
        raise ConnectionError("INDI is not running")
    client = PyIndi.BaseClient()
    client.setServer("127.0.0.1", 7624)
    if not client.connectServer():
        raise ConnectionError("INDI is not ready")
    try:
        time.sleep(0.3)
        for device in client.getDevices():
            if not device.isConnected():
                continue
            coordinates = device.getNumber("EQUATORIAL_EOD_COORD") or device.getNumber(
                "EQUATORIAL_COORD"
            )
            if not coordinates or len(coordinates) < 2:
                continue
            coordinates[0].setValue(ra_hours)
            coordinates[1].setValue(declination)
            client.sendNewProperty(coordinates)
            return {"status": "slewing", "device": device.getDeviceName()}
        raise ConnectionError("no connected telescope was found")
    finally:
        client.disconnectServer()


def location_worker() -> None:
    last_applied_key: tuple[str, object] | None = None
    while True:
        location = load_location()
        pid = indi_pid()
        if location and pid:
            key = (pid, location.get("received_at"))
            if key != last_applied_key:
                result = apply_location_to_indi(location)
                if result["status"] == "applied":
                    last_applied_key = key
        else:
            last_applied_key = None
        time.sleep(5)


class Handler(BaseHTTPRequestHandler):
    server_version = "AstroFieldBridge/0.2"

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path == "/api/v1/health":
            self.send_json({"status": "ok"})
            return
        if parsed.path == "/api/v1/system":
            self.send_json(system_payload())
            return
        if parsed.path == "/api/v1/system/details":
            self.send_json(system_details())
            return
        if parsed.path == "/api/v1/phd2/status":
            self.send_json(phd2_status())
            return
        if parsed.path in {"/api/v1/focus/status", "/api/v1/focus/config", "/api/v1/focus/history"}:
            if not self.authorized():
                self.send_json({"error": "unauthorized"}, status=401)
                return
            if parsed.path.endswith("status"):
                self.send_json(focus_module_status())
            elif parsed.path.endswith("config"):
                self.send_json(focus_config())
            else:
                self.send_json({"runs": focus_history()})
            return
        if parsed.path == "/api/v1/phd2/assistant/status":
            if not self.authorized():
                self.send_json({"error": "unauthorized"}, status=401)
                return
            self.send_json(assistant_snapshot())
            return
        if parsed.path == "/api/v1/phd2/assistant/history":
            if not self.authorized():
                self.send_json({"error": "unauthorized"}, status=401)
                return
            self.send_json({"runs": assistant_history()})
            return
        if parsed.path == "/api/v1/mount/status":
            self.send_json(mount_status())
            return
        if parsed.path == "/api/v1/indi/devices":
            self.send_json(indi_devices())
            return
        if parsed.path == "/api/v1/sky/framing":
            self.send_json(framing_geometry())
            return
        if parsed.path in {"/api/v1/sky/visible", "/api/v1/sky/search"}:
            try:
                parameters = parse_qs(parsed.query)
                query = parameters.get("q", [""])[0] if parsed.path.endswith("search") else ""
                min_altitude = finite_number(
                    parameters.get("min_altitude", [20])[0], "min_altitude"
                )
                limit = int(parameters.get("limit", [50])[0])
                self.send_json(sky_catalog(query, min_altitude, limit))
            except (ValueError, OSError) as error:
                self.send_json({"error": "sky_catalog_unavailable", "message": str(error)}, 400)
            return
        if parsed.path == "/api/v1/equipment/drivers":
            parameters = parse_qs(parsed.query)
            self.send_json(
                installed_drivers(
                    parameters.get("group", [""])[0],
                    parameters.get("q", [""])[0],
                )
            )
            return
        if parsed.path == "/api/v1/equipment/profile":
            try:
                self.send_json(json.loads(EQUIPMENT_FILE.read_text()))
            except (OSError, json.JSONDecodeError):
                self.send_json({"status": "not_configured"}, 404)
            return
        if parsed.path == "/api/v1/equipment/profiles":
            self.send_json(equipment_profiles())
            return
        if parsed.path == "/api/v1/storage/status":
            if not self.authorized():
                self.send_json({"error": "unauthorized"}, status=401)
                return
            try:
                self.send_json(storage_status())
            except OSError as error:
                self.send_json({"error": "storage_unavailable", "message": str(error)}, 503)
            return
        if parsed.path == "/api/v1/storage/files":
            if not self.authorized():
                self.send_json({"error": "unauthorized"}, status=401)
                return
            try:
                relative_path = parse_qs(parsed.query).get("path", [""])[0]
                self.send_json(storage_listing(relative_path))
            except (OSError, ValueError) as error:
                self.send_json({"error": "invalid_storage_path", "message": str(error)}, 400)
            return
        if parsed.path == "/api/v1/storage/download":
            if not self.authorized():
                self.send_json({"error": "unauthorized"}, status=401)
                return
            try:
                relative_path = parse_qs(parsed.query).get("path", [""])[0]
                self.send_file(safe_storage_path(relative_path))
            except (OSError, ValueError) as error:
                self.send_json({"error": "invalid_storage_path", "message": str(error)}, 400)
            return
        self.send_json({"error": "not_found"}, status=404)

    def do_POST(self) -> None:  # noqa: N802
        if self.path not in {
            "/api/v1/location",
            "/api/v1/phd2/rpc",
            "/api/v1/phd2/assistant/start",
            "/api/v1/phd2/assistant/stop",
            "/api/v1/phd2/assistant/apply",
            "/api/v1/phd2/assistant/backlash/apply",
            "/api/v1/focus/config",
            "/api/v1/focus/command",
            "/api/v1/mount/goto",
            "/api/v1/equipment/profile",
            "/api/v1/equipment/profiles/select",
        }:
            self.send_json({"error": "not_found"}, status=404)
            return
        if not self.authorized():
            self.send_json({"error": "unauthorized"}, status=401)
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 4096:
                raise ValueError("invalid request size")
            payload = json.loads(self.rfile.read(length))
            if not isinstance(payload, dict):
                raise ValueError("JSON body must be an object")
            if self.path == "/api/v1/location":
                location = validate_location(payload)
        except (json.JSONDecodeError, ValueError) as error:
            self.send_json({"error": "invalid_request", "message": str(error)}, 400)
            return

        if self.path == "/api/v1/phd2/rpc":
            try:
                method = payload.get("method")
                if not isinstance(method, str):
                    raise ValueError("method must be a string")
                result = phd2_rpc(method, payload.get("params"))
                self.send_json({"status": "ok", **result})
            except ValueError as error:
                self.send_json({"error": "invalid_rpc", "message": str(error)}, 400)
            except (ConnectionError, OSError, TimeoutError, json.JSONDecodeError) as error:
                self.send_json({"error": "phd2_unavailable", "message": str(error)}, 503)
            return

        if self.path == "/api/v1/focus/config":
            try:
                self.send_json({"status": "saved", "config": save_focus_config(payload)})
            except ValueError as error:
                self.send_json({"error": "invalid_focus_config", "message": str(error)}, 400)
            return

        if self.path == "/api/v1/focus/command":
            try:
                self.send_json(focus_command(payload), 202)
            except (ConnectionError, OSError, subprocess.TimeoutExpired, ValueError) as error:
                self.send_json({"error": "focus_command_failed", "message": str(error)}, 400)
            return

        if self.path == "/api/v1/phd2/assistant/start":
            try:
                duration = int(payload.get("duration_seconds", 600))
                self.send_json(
                    start_guiding_assistant(
                        duration,
                        bool(payload.get("measure_backlash", True)),
                    ),
                    202,
                )
            except (TypeError, ValueError) as error:
                self.send_json({"error": "assistant_unavailable", "message": str(error)}, 400)
            return

        if self.path == "/api/v1/phd2/assistant/stop":
            self.send_json(stop_guiding_assistant(), 202)
            return

        if self.path == "/api/v1/phd2/assistant/apply":
            try:
                self.send_json(apply_guiding_assistant(payload))
            except (ConnectionError, OSError, TimeoutError, ValueError, json.JSONDecodeError) as error:
                self.send_json({"error": "assistant_apply_failed", "message": str(error)}, 400)
            return

        if self.path == "/api/v1/phd2/assistant/backlash/apply":
            try:
                self.send_json(apply_phd2_backlash_compensation(payload))
            except (ConnectionError, OSError, TimeoutError, ValueError, json.JSONDecodeError) as error:
                self.send_json({"error": "backlash_apply_failed", "message": str(error)}, 400)
            return

        if self.path == "/api/v1/mount/goto":
            try:
                self.send_json(mount_goto(payload))
            except ValueError as error:
                self.send_json({"error": "invalid_coordinates", "message": str(error)}, 400)
            except (ConnectionError, OSError) as error:
                self.send_json({"error": "mount_unavailable", "message": str(error)}, 503)
            return

        if self.path == "/api/v1/equipment/profile":
            try:
                profile = validate_equipment_profile(payload)
                save_equipment_profile(profile)
                self.send_json({"status": "saved", "profile": profile})
            except ValueError as error:
                self.send_json({"error": "invalid_equipment", "message": str(error)}, 400)
            return

        if self.path == "/api/v1/equipment/profiles/select":
            try:
                profile = select_equipment_profile(str(payload.get("profile_id", "")))
                self.send_json({"status": "selected", "profile": profile})
            except ValueError as error:
                self.send_json({"error": "invalid_equipment", "message": str(error)}, 400)
            return

        with location_lock:
            save_location(location)
            result = apply_location_to_indi(location)
        self.send_json(
            {
                "status": "saved",
                "source": "phone",
                "indi": result,
            },
            status=200 if result["status"] == "applied" else 202,
        )

    def authorized(self) -> bool:
        supplied = self.headers.get("X-AstroField-Token", "")
        return bool(TOKEN) and hmac.compare_digest(supplied, TOKEN)

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self.send_cors_headers()
        self.end_headers()

    def send_cors_headers(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header(
            "Access-Control-Allow-Headers", "Content-Type, X-AstroField-Token"
        )
        self.send_header("Access-Control-Allow-Private-Network", "true")

    def send_json(self, payload: dict[str, object], status: int = 200) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_cors_headers()
        self.end_headers()
        self.wfile.write(body)

    def send_file(self, path: Path) -> None:
        if not path.is_file():
            raise ValueError("file was not found")
        stat = path.stat()
        self.send_response(200)
        self.send_header("Content-Type", "application/fits" if path.suffix.casefold() in {".fits", ".fit", ".fts"} else "application/octet-stream")
        self.send_header("Content-Disposition", f'attachment; filename="{path.name.replace(chr(34), "")}"')
        self.send_header("Content-Length", str(stat.st_size))
        self.send_header("Cache-Control", "private, no-store")
        self.send_cors_headers()
        self.end_headers()
        with path.open("rb") as source:
            shutil.copyfileobj(source, self.wfile, length=1024 * 1024)

    def log_message(self, format: str, *args: object) -> None:
        print(f"{self.client_address[0]} {format % args}")


if __name__ == "__main__":
    threading.Thread(target=location_worker, daemon=True).start()
    threading.Thread(target=autofocus_trigger_worker, daemon=True).start()
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
