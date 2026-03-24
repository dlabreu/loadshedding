"""
EDA Custom Event Source: EskomSePush API
Polls the EskomSePush API and emits events when loadshedding windows
are approaching or ending for a configured area.

Usage in EDA rulebook:
  sources:
    - name: eskomsepush
      eskomsepush_source:
        api_token: "{{ eskomsepush_api_token }}"
        area_id: "capetown-10-atlantis"   # your area ID
        warning_minutes: 30               # alert this many mins before start
        poll_interval: 300                # seconds between API polls
"""

import asyncio
import datetime
import os
from typing import Any

import aiohttp


ESKOMSEPUSH_BASE = "https://developer.sepush.co.za/business/2.0"


async def main(queue: asyncio.Queue, args: dict[str, Any]):
    api_token: str = args["api_token"]
    area_id: str = args["area_id"]
    warning_minutes: int = int(args.get("warning_minutes", 30))
    poll_interval: int = int(args.get("poll_interval", 300))

    headers = {"Token": api_token}
    last_seen_events: set[str] = set()

    async with aiohttp.ClientSession(headers=headers) as session:
        while True:
            try:
                await _poll(
                    session, queue, area_id,
                    warning_minutes, last_seen_events
                )
            except Exception as exc:
                await queue.put({
                    "type": "error",
                    "source": "eskomsepush",
                    "message": str(exc),
                    "timestamp": _now(),
                })
            await asyncio.sleep(poll_interval)


async def _poll(session, queue, area_id, warning_minutes, last_seen):
    url = f"{ESKOMSEPUSH_BASE}/area"
    params = {"id": area_id, "test": "current"}  # remove test param in prod

    async with session.get(url, params=params) as resp:
        resp.raise_for_status()
        data = await resp.json()

    area_name = data.get("info", {}).get("name", area_id)
    events = data.get("events", [])
    schedule = data.get("schedule", {})

    now = datetime.datetime.now(datetime.timezone.utc)
    warning_delta = datetime.timedelta(minutes=warning_minutes)

    # Emit status heartbeat every poll so dashboard stays fresh
    await queue.put({
        "type": "status_update",
        "source": "eskomsepush",
        "area_id": area_id,
        "area_name": area_name,
        "events": events,
        "schedule": schedule,
        "timestamp": _now(),
    })

    for event in events:
        start_str = event.get("start", "")
        end_str = event.get("end", "")
        if not start_str:
            continue

        try:
            start = datetime.datetime.fromisoformat(start_str.replace("Z", "+00:00"))
            end = datetime.datetime.fromisoformat(end_str.replace("Z", "+00:00"))
        except ValueError:
            continue

        event_key = f"{start_str}-{end_str}"

        # Approaching: warn_minutes before start
        if now < start <= now + warning_delta:
            if f"approaching:{event_key}" not in last_seen:
                last_seen.add(f"approaching:{event_key}")
                await queue.put({
                    "type": "loadshedding_approaching",
                    "source": "eskomsepush",
                    "area_id": area_id,
                    "area_name": area_name,
                    "start": start_str,
                    "end": end_str,
                    "minutes_until_start": int((start - now).total_seconds() / 60),
                    "note": event.get("note", ""),
                    "timestamp": _now(),
                })

        # Active: within the outage window
        if start <= now < end:
            if f"active:{event_key}" not in last_seen:
                last_seen.add(f"active:{event_key}")
                await queue.put({
                    "type": "loadshedding_active",
                    "source": "eskomsepush",
                    "area_id": area_id,
                    "area_name": area_name,
                    "start": start_str,
                    "end": end_str,
                    "note": event.get("note", ""),
                    "timestamp": _now(),
                })

        # Ending: when we pass the end time, power can be restored
        if now >= end:
            if f"ended:{event_key}" not in last_seen:
                last_seen.add(f"ended:{event_key}")
                await queue.put({
                    "type": "loadshedding_ended",
                    "source": "eskomsepush",
                    "area_id": area_id,
                    "area_name": area_name,
                    "start": start_str,
                    "end": end_str,
                    "timestamp": _now(),
                })

    # Prune old keys to prevent unbounded growth
    cutoff = now - datetime.timedelta(hours=24)
    # (simplified: a production version would parse keys to filter by date)


def _now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat()
