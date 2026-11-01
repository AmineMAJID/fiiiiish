"""Read the real FiveM NUI over the Chromium DevTools Protocol.

FiveM exposes its CEF remote debugging endpoint on ``http://localhost:13172``
while the game is running (see docs.fivem.net, "Full screen NUI" ->
"Developer tools").  That lets the bot read the exact numbers the player sees
instead of trying to OCR pixels:

    fight    progress %, danger %, requested side, verdict
    cast     power %, charging / locked
    bite     waiting / bite
    decision keep/release modal open
    depth    the "START_FISHING" prompt (can cast)

The page is found by URL substring (the resource name, e.g. ``fiiiiish`` or
``qs-fisher``).  If several NUI pages exist, the bot probes them for the
fishing HUD classes and picks the right one.

Only the standard library plus ``websocket-client`` is required.  The module
imports cleanly on every OS; the connection is only attempted when the live
bot asks for it.
"""

from __future__ import annotations

import json
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any

from .fight import NuiView, TargetSide

try:  # optional, only needed for live mode
    import websocket  # type: ignore
except Exception:  # pragma: no cover - exercised on machines without it
    websocket = None  # type: ignore


class NuiUnavailable(RuntimeError):
    """Raised when the CEF endpoint or the fishing NUI cannot be reached."""


class NuiError(RuntimeError):
    """Raised when a CDP evaluation fails."""


# ---------------------------------------------------------------------------
# JS snippets.  They are deliberately defensive: a missing element returns
# null rather than throwing, so a closed HUD is not an error.
# ---------------------------------------------------------------------------
JS_PROBE = """(() => {
  const keys = ['cueRow','depthValue','card','floatBiting','waitingText','choice'];
  return keys.some(k => !!document.querySelector(`[class*="${k}"]`));
})()"""

JS_FIGHT = """(() => {
  const row = document.querySelector('[class*="cueRow"]');
  if (!row) return null;
  const cueOn = row.querySelector('[class*="cueOn"]');
  const cues = Array.from(row.children).filter(el => String(el.className).includes('cue'));
  const idx = cueOn ? cues.indexOf(cueOn) : -1;
  const vals = Array.from(document.querySelectorAll('[class*="meterValue"]')).map(el => {
    const m = String(el.textContent).match(/-?\\d+/);
    return m ? Number(m[0]) : 0;
  });
  const verdictEl = document.querySelector('[class*="verdict"]');
  return {
    side: idx === 0 ? 'left' : (idx > 0 ? 'right' : null),
    danger: vals[1] || 0,
    progress: vals[0] || 0,
    active: !verdictEl,
    verdict: verdictEl ? String(verdictEl.textContent).trim() : null
  };
})()"""

JS_CAST = """(() => {
  // The cast card exists in every cast state (ready / charging / locked);
  // only the cardLive / cardLocked classes change.  Querying the card itself
  // lets the bot see the 'ready' state and press the charge button.
  const card = document.querySelector('[class*="card"]');
  if (!card) return null;
  const value = card.querySelector('[class*="value"]');
  const m = value ? String(value.textContent).match(/-?\\d+/) : null;
  return {
    power: m ? Number(m[0]) : 0,
    charging: String(card.className).includes('cardLive'),
    locked: String(card.className).includes('cardLocked')
  };
})()"""

JS_BITE = """(() => {
  const biting = document.querySelector('[class*="floatBiting"]');
  const waiting = document.querySelector('[class*="waitingText"]');
  if (!biting && !waiting) return null;
  return { state: biting ? 'bite' : 'waiting' };
})()"""

JS_DECISION = """(() => {
  const keep = document.querySelector('[class*="keep"]');
  const release = document.querySelector('[class*="release"]');
  if (!keep && !release) return null;
  return { open: true };
})()"""

JS_CAN_CAST = """(() => {
  const depth = document.querySelector('[class*="depthValue"]');
  if (!depth) return false;
  const col = depth.closest('[class*="depthCol"]');
  if (!col) return false;
  const action = col.querySelector('[class*="action"]');
  if (!action) return false;
  return !String(action.className).includes('actionOff');
})()"""

JS_CLICK_KEEP = """(() => {
  const b = document.querySelector('[class*="keep"]');
  if (!b) return false;
  b.click();
  return true;
})()"""


@dataclass
class CastView:
    power: int
    charging: bool
    locked: bool


@dataclass
class BiteView:
    state: str  # "waiting" | "bite"


@dataclass
class DecisionView:
    open: bool


class CdpClient:
    """Minimal synchronous CDP client (Runtime.evaluate only)."""

    def __init__(self, endpoint: str = "http://127.0.0.1:13172", *, timeout: float = 5.0):
        self.endpoint = endpoint.rstrip("/")
        self.timeout = float(timeout)
        self.ws = None
        self._id = 0
        self.page_url = ""
        self.page_title = ""

    # ------------------------------------------------------------------
    def list_pages(self) -> list[dict]:
        try:
            with urllib.request.urlopen(self.endpoint + "/json", timeout=self.timeout) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except (urllib.error.URLError, OSError) as exc:
            raise NuiUnavailable(
                f"Cannot reach the FiveM CEF endpoint at {self.endpoint}/json. "
                f"Start the game and join the server first. Underlying error: {exc}"
            ) from exc
        return [p for p in data if p.get("type") == "page"]

    def connect(self, page_match: str | None = None) -> None:
        if websocket is None:
            raise NuiUnavailable(
                "The 'websocket-client' package is required for live mode. "
                "Install it with: pip install websocket-client"
            )
        try:
            pages = self.list_pages()
        except (urllib.error.URLError, OSError) as exc:
            raise NuiUnavailable(
                f"Cannot reach the FiveM CEF endpoint at {self.endpoint}/json. "
                "Start the game, join the server, then run the bot again. "
                "If it still fails, enable developer mode / nui_devTools in the "
                "FiveM client. Underlying error: {exc}"
            ) from exc

        if not pages:
            raise NuiUnavailable("The CEF endpoint returned no page targets.")

        page = None
        if page_match:
            needle = page_match.lower()
            page = next(
                (p for p in pages if needle in (p.get("url", "") + " " + p.get("title", "")).lower()),
                None,
            )
        if page is None:
            # Try the usual resource names, then probe every page.
            for candidate in ("fiiiiish", "qs-fisher", "qs-fishing", "cfx-nui"):
                page = next(
                    (p for p in pages if candidate in (p.get("url", "") + " " + p.get("title", "")).lower()),
                    None,
                )
                if page is not None:
                    break
        if page is None:
            page = pages[0]

        url = page.get("webSocketDebuggerUrl", "")
        if not url:
            raise NuiUnavailable("The selected page has no WebSocket debugger URL.")
        self.page_url = page.get("url", "")
        self.page_title = page.get("title", "")
        try:
            self.ws = websocket.create_connection(
                url,
                timeout=self.timeout,
                suppress_origin=True,
                enable_multithread=True,
            )
        except Exception as exc:  # pragma: no cover - network dependent
            raise NuiUnavailable(f"Could not attach to the NUI page: {exc}") from exc

        # If the chosen page is not the fishing NUI, try the others.
        try:
            if not self.evaluate(JS_PROBE):
                for other in pages:
                    if other is page:
                        continue
                    other_url = other.get("webSocketDebuggerUrl", "")
                    if not other_url:
                        continue
                    try:
                        self.ws.close()
                    except Exception:
                        pass
                    try:
                        self.ws = websocket.create_connection(
                            other_url,
                            timeout=self.timeout,
                            suppress_origin=True,
                            enable_multithread=True,
                        )
                        self.page_url = other.get("url", "")
                        self.page_title = other.get("title", "")
                        if self.evaluate(JS_PROBE):
                            break
                    except Exception:
                        continue
        except NuiError:
            pass

    # ------------------------------------------------------------------
    def evaluate(self, expression: str) -> Any:
        if self.ws is None:
            raise NuiUnavailable("Not connected to the NUI.")
        self._id += 1
        msg = {
            "id": self._id,
            "method": "Runtime.evaluate",
            "params": {
                "expression": expression,
                "returnByValue": True,
                "awaitPromise": True,
            },
        }
        self.ws.send(json.dumps(msg))
        deadline = time.monotonic() + self.timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise NuiError("Timed out waiting for the NUI to answer.")
            self.ws.settimeout(max(0.1, remaining))
            try:
                raw = self.ws.recv()
            except Exception as exc:  # timeout, closed socket, etc.
                raise NuiError(f"NUI connection lost: {exc}") from exc
            if isinstance(raw, bytes):
                raw = raw.decode("utf-8", "replace")
            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if data.get("id") != self._id:
                continue
            if "error" in data:
                raise NuiError(str(data["error"]))
            result = data.get("result", {})
            if "exceptionDetails" in result:
                details = result["exceptionDetails"]
                text = details.get("exception", {}).get("description") or details.get("text", "")
                raise NuiError(f"NUI evaluation failed: {text}")
            return result.get("result", {}).get("value")

    def close(self) -> None:
        if self.ws is not None:
            try:
                self.ws.close()
            except Exception:
                pass
            self.ws = None


class NuiReader:
    """High-level reader used by the live bot."""

    def __init__(
        self,
        *,
        endpoint: str = "http://127.0.0.1:13172",
        page_match: str | None = None,
        timeout: float = 5.0,
    ) -> None:
        self.endpoint = endpoint
        self.page_match = page_match
        self.timeout = float(timeout)
        self.cdp = CdpClient(endpoint, timeout=self.timeout)
        self.connected = False

    # ------------------------------------------------------------------
    def connect(self) -> None:
        self.cdp.connect(self.page_match)
        self.connected = True

    def close(self) -> None:
        self.cdp.close()
        self.connected = False

    # ------------------------------------------------------------------
    def read_fight(self) -> NuiView | None:
        raw = self.cdp.evaluate(JS_FIGHT)
        if not raw:
            return None
        side = raw.get("side")
        if side not in ("left", "right"):
            side = None
        return NuiView(
            danger=int(raw.get("danger") or 0),
            progress=int(raw.get("progress") or 0),
            side=side,
            active=bool(raw.get("active")),
            verdict=raw.get("verdict"),
        )

    def read_cast(self) -> CastView | None:
        raw = self.cdp.evaluate(JS_CAST)
        if not raw:
            return None
        return CastView(
            power=int(raw.get("power") or 0),
            charging=bool(raw.get("charging")),
            locked=bool(raw.get("locked")),
        )

    def read_bite(self) -> BiteView | None:
        raw = self.cdp.evaluate(JS_BITE)
        if not raw:
            return None
        return BiteView(state=str(raw.get("state") or "waiting"))

    def read_decision(self) -> DecisionView | None:
        raw = self.cdp.evaluate(JS_DECISION)
        if not raw:
            return None
        return DecisionView(open=bool(raw.get("open")))

    def can_cast(self) -> bool:
        return bool(self.cdp.evaluate(JS_CAN_CAST))

    def click_keep(self) -> bool:
        return bool(self.cdp.evaluate(JS_CLICK_KEEP))

    # ------------------------------------------------------------------
    def probe(self) -> bool:
        return bool(self.cdp.evaluate(JS_PROBE))
