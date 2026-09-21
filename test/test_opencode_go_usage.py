import importlib.machinery
import importlib.util
import io
import json
import sqlite3
import sys
import tempfile
import time
import unittest
import urllib.error
from pathlib import Path
from unittest import mock


HELPER_PATH = Path(__file__).parents[1] / "tools" / "omarchy-agent-usage-opencode-go"
loader = importlib.machinery.SourceFileLoader("opencode_go_usage", str(HELPER_PATH))
spec = importlib.util.spec_from_loader(loader.name, loader)
helper = importlib.util.module_from_spec(spec)
sys.modules[loader.name] = helper
loader.exec_module(helper)


class FakeResponse:
    def __init__(self, payload):
        self._raw = json.dumps(payload).encode("utf-8")

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def read(self, size=-1):
        return self._raw if size is None or size < 0 else self._raw[:size]


def make_message_db(path, rows):
    conn = sqlite3.connect(path)
    conn.execute("CREATE TABLE message (session_id TEXT, data TEXT)")
    conn.executemany("INSERT INTO message (session_id, data) VALUES (?, ?)", rows)
    conn.commit()
    conn.close()


def message_row(session_id, provider_id, model_id, created_ms, input_tokens=100, output_tokens=50, role="assistant"):
    data = {
        "role": role,
        "providerID": provider_id,
        "modelID": model_id,
        "time": {"created": created_ms},
        "tokens": {"input": input_tokens, "output": output_tokens, "reasoning": 0, "cache": {"read": 0, "write": 0}},
    }
    return (session_id, json.dumps(data))


class CredentialTests(unittest.TestCase):
    def test_env_var_wins_over_auth_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            auth_path = Path(tmp) / "auth.json"
            auth_path.write_text(json.dumps({"opencode-go": {"key": "file-key"}}))
            with mock.patch.dict("os.environ", {"OPENCODE_API_KEY": "env-key"}, clear=False):
                self.assertEqual(helper.resolve_api_key(auth_path), "env-key")

    def test_prefers_go_key_over_zen_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            auth_path = Path(tmp) / "auth.json"
            auth_path.write_text(json.dumps({
                "opencode": {"key": "zen-key"},
                "opencode-go": {"key": "go-key"},
            }))
            with mock.patch.dict("os.environ", {}, clear=True):
                self.assertEqual(helper.resolve_api_key(auth_path), "go-key")

    def test_falls_back_to_zen_key_when_go_key_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            auth_path = Path(tmp) / "auth.json"
            auth_path.write_text(json.dumps({"opencode": {"key": "zen-key"}}))
            with mock.patch.dict("os.environ", {}, clear=True):
                self.assertEqual(helper.resolve_api_key(auth_path), "zen-key")

    def test_returns_empty_when_no_key_anywhere(self):
        with tempfile.TemporaryDirectory() as tmp:
            auth_path = Path(tmp) / "auth.json"
            with mock.patch.dict("os.environ", {}, clear=True):
                self.assertEqual(helper.resolve_api_key(auth_path), "")


class FetchQuotaTests(unittest.TestCase):
    def test_converts_percent_and_maps_window_labels(self):
        payload = {
            "usage": {
                "rolling": {"status": "ok", "percent": 34.5, "resetsAt": "2026-09-21T13:00:00Z"},
                "weekly": {"status": "ok", "percent": 58, "resetsAt": "2026-09-26T00:00:00Z"},
                "monthly": {"status": "ok", "percent": 12, "resetsAt": "2026-10-01T00:00:00Z"},
            }
        }
        with mock.patch("urllib.request.urlopen", return_value=FakeResponse(payload)):
            limits, error = helper.fetch_quota("a-key", helper.USAGE_URL)
        self.assertEqual(error, "")
        self.assertEqual(
            limits,
            [
                {"label": "Session (5-hour)", "percent": 0.345, "resetsAt": "2026-09-21T13:00:00Z"},
                {"label": "Weekly (7-day)", "percent": 0.58, "resetsAt": "2026-09-26T00:00:00Z"},
                {"label": "Monthly", "percent": 0.12, "resetsAt": "2026-10-01T00:00:00Z"},
            ],
        )

    def test_skips_windows_without_a_numeric_percent(self):
        payload = {"usage": {"rolling": {"status": "ok"}, "weekly": {"status": "ok", "percent": 10, "resetsAt": ""}}}
        with mock.patch("urllib.request.urlopen", return_value=FakeResponse(payload)):
            limits, error = helper.fetch_quota("a-key", helper.USAGE_URL)
        self.assertEqual(error, "")
        self.assertEqual([entry["label"] for entry in limits], ["Weekly (7-day)"])

    def test_reports_key_rejected_on_401_and_403(self):
        for code in (401, 403):
            http_error = urllib.error.HTTPError(helper.USAGE_URL, code, "denied", None, io.BytesIO(b""))
            with mock.patch("urllib.request.urlopen", side_effect=http_error):
                limits, error = helper.fetch_quota("a-key", helper.USAGE_URL)
            http_error.close()
            self.assertEqual(limits, [])
            self.assertEqual(error, "OpenCode Go key rejected")

    def test_reports_network_failure(self):
        with mock.patch("urllib.request.urlopen", side_effect=urllib.error.URLError("boom")):
            limits, error = helper.fetch_quota("a-key", helper.USAGE_URL)
        self.assertEqual(limits, [])
        self.assertEqual(error, "Could not reach opencode.ai")


class LocalScanTests(unittest.TestCase):
    def test_filters_to_the_go_provider_and_fills_today_stats(self):
        with tempfile.TemporaryDirectory() as tmp:
            db = Path(tmp) / "opencode.db"
            today = helper.local_date_string()
            now_ms = int(time.time() * 1000)
            make_message_db(db, [
                message_row("s1", "opencode-go", "gpt-5.6-sol", now_ms, input_tokens=100, output_tokens=50),
                message_row("s1", "opencode-go", "gpt-5.6-sol", now_ms, input_tokens=10, output_tokens=5),
                message_row("s2", "opencode", "big-pickle", now_ms),  # Zen, not Go: excluded
                message_row("s3", "openai", "gpt-5.6", now_ms),  # underlying provider, not Go: excluded
                message_row("s4", "opencode-go", "gpt-5.6-sol", now_ms, role="user"),  # not assistant: excluded
            ])
            stats = helper.scan_local_usage(db, 0)
        self.assertIsNotNone(stats)
        self.assertEqual(stats["todayPrompts"], 2)
        self.assertEqual(stats["todaySessions"], 1)
        self.assertEqual(stats["todayTotalTokens"], 165)
        self.assertEqual(stats["totalPrompts"], 2)
        self.assertEqual(stats["modelUsage"]["gpt-5.6-sol"]["inputTokens"], 110)
        self.assertEqual(stats["activeDates"], [today])

    def test_returns_none_when_the_go_provider_never_appears(self):
        with tempfile.TemporaryDirectory() as tmp:
            db = Path(tmp) / "opencode.db"
            now_ms = int(time.time() * 1000)
            make_message_db(db, [message_row("s1", "opencode", "big-pickle", now_ms)])
            self.assertIsNone(helper.scan_local_usage(db, 0))

    def test_returns_none_when_the_database_is_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertIsNone(helper.scan_local_usage(Path(tmp) / "missing.db", 0))

    def test_reuses_a_fresh_cache_instead_of_rescanning(self):
        with tempfile.TemporaryDirectory() as tmp:
            db = Path(tmp) / "opencode.db"
            now_ms = int(time.time() * 1000)
            make_message_db(db, [message_row("s1", "opencode-go", "gpt-5.6-sol", now_ms)])
            with mock.patch.object(helper, "cache_root", return_value=Path(tmp)):
                first = helper.scan_local_usage(db, 60)
                db.unlink()
                make_message_db(db, [])  # would report no data on a real rescan
                second = helper.scan_local_usage(db, 60)
        self.assertEqual(first, second)


class ScanTests(unittest.TestCase):
    def test_no_key_short_circuits_without_a_network_call(self):
        with tempfile.TemporaryDirectory() as tmp:
            auth_path = Path(tmp) / "auth.json"
            db = Path(tmp) / "opencode.db"
            with mock.patch.dict("os.environ", {}, clear=True):
                with mock.patch("urllib.request.urlopen") as urlopen:
                    record = helper.scan(0, auth_path, db, helper.USAGE_URL)
                    urlopen.assert_not_called()
        self.assertFalse(record["ready"])
        self.assertEqual(record["authHelpText"], helper.AUTH_HELP)


if __name__ == "__main__":
    unittest.main()
