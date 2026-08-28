import contextlib
import importlib.machinery
import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.parse
from pathlib import Path
from unittest import mock


HELPER_PATH = Path(__file__).parents[1] / "tools" / "google-calendar-helper"
loader = importlib.machinery.SourceFileLoader("google_calendar_helper", str(HELPER_PATH))
spec = importlib.util.spec_from_loader(loader.name, loader)
helper = importlib.util.module_from_spec(spec)
sys.modules[loader.name] = helper
loader.exec_module(helper)


class FakeResponse:
    def __init__(self, value=None, raw=None):
        self.raw = raw if raw is not None else json.dumps(value).encode("utf-8")

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def read(self, size=-1):
        return self.raw if size is None or size < 0 else self.raw[:size]


class FakeSecretStore:
    available = True

    def __init__(self, token=None):
        self.token = token
        self.stored = []
        self.deleted = 0

    def lookup(self):
        return self.token

    def store(self, token):
        self.stored.append(token)
        self.token = token

    def delete(self):
        self.deleted += 1
        self.token = None


class PkceTests(unittest.TestCase):
    def test_pkce_uses_s256_without_base64_padding(self):
        verifier, challenge = helper.generate_pkce(lambda size: bytes(range(size)))

        self.assertGreaterEqual(len(verifier), 43)
        self.assertLessEqual(len(verifier), 128)
        self.assertNotIn("=", verifier)
        self.assertNotIn("=", challenge)
        expected = helper._base64url(
            helper.hashlib.sha256(verifier.encode("ascii")).digest()
        )
        self.assertEqual(challenge, expected)

    def test_authorization_url_contains_read_only_scope_and_pkce(self):
        client = helper.OAuthClient(client_id="client-id")
        url = helper.build_authorization_url(
            client,
            "http://127.0.0.1:4321/oauth2callback",
            "state-value",
            "challenge-value",
        )
        query = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)

        self.assertEqual(query["scope"], [helper.SCOPE])
        self.assertEqual(query["code_challenge_method"], ["S256"])
        self.assertEqual(query["code_challenge"], ["challenge-value"])
        self.assertEqual(query["state"], ["state-value"])
        self.assertEqual(query["redirect_uri"], ["http://127.0.0.1:4321/oauth2callback"])
        self.assertEqual(query["access_type"], ["offline"])


class AuthorizationTests(unittest.TestCase):
    def test_authorize_binds_loopback_exchanges_code_and_stores_refresh_token(self):
        store = FakeSecretStore()
        client = helper.OAuthClient(client_id="client-id", client_secret="client-secret")
        browser_urls = []
        servers = []
        token_forms = []

        class FakeServer:
            server_address = ("127.0.0.1", 49152)

            def server_close(self):
                self.closed = True

        def server_factory(address, handler):
            self.assertEqual(address, ("127.0.0.1", 0))
            server = FakeServer()
            server.handler = handler
            server.closed = False
            servers.append(server)
            return server

        def wait_for_callback(server, result):
            result["code"] = "authorization-code"
            return result

        def urlopen(request, timeout):
            token_forms.append(urllib.parse.parse_qs(request.data.decode("utf-8")))
            return FakeResponse(
                {"access_token": "memory-only", "refresh_token": "refresh-secret"}
            )

        with mock.patch.object(helper, "generate_pkce", return_value=("verifier", "challenge")), mock.patch.object(
            helper, "wait_for_callback", side_effect=wait_for_callback
        ):
            result = helper.authorize(
                client,
                store,
                urlopen=urlopen,
                browser_opener=lambda url: browser_urls.append(url) or True,
                server_factory=server_factory,
            )

        self.assertEqual(result, {"ok": True, "connected": True})
        self.assertEqual(store.stored, ["refresh-secret"])
        self.assertTrue(servers[0].closed)
        query = urllib.parse.parse_qs(urllib.parse.urlparse(browser_urls[0]).query)
        self.assertEqual(query["redirect_uri"], ["http://127.0.0.1:49152/oauth2callback"])
        self.assertEqual(query["code_challenge"], ["challenge"])
        self.assertEqual(token_forms[0]["code_verifier"], ["verifier"])
        self.assertEqual(token_forms[0]["code"], ["authorization-code"])


    def test_wrong_callback_state_does_not_end_the_authorization_wait(self):
        result = {}
        handler = helper._callback_handler("expected-state", result)
        server = helper.HTTPServer(("127.0.0.1", 0), handler)
        port = server.server_address[1]

        thread = threading.Thread(
            target=lambda: [server.handle_request(), server.handle_request()], daemon=True
        )
        thread.start()
        try:
            with self.assertRaises(urllib.error.HTTPError) as rejected:
                urllib.request.urlopen(
                    f"http://127.0.0.1:{port}/oauth2callback?state=wrong&code=bad",
                    timeout=2,
                )
            self.assertEqual(rejected.exception.code, 400)
            rejected.exception.close()
            self.assertEqual(result, {})

            response = urllib.request.urlopen(
                f"http://127.0.0.1:{port}/oauth2callback?state=expected-state&code=good",
                timeout=2,
            )
            self.assertEqual(response.status, 200)
            response.close()
            thread.join(timeout=2)
            self.assertEqual(result, {"code": "good"})
        finally:
            server.server_close()


class ClientConfigTests(unittest.TestCase):
    def write_client(self, document):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "client.json"
        path.write_text(json.dumps(document), encoding="utf-8")
        return path

    def test_parses_installed_desktop_client(self):
        path = self.write_client(
            {
                "installed": {
                    "client_id": "desktop.apps.googleusercontent.com",
                    "client_secret": "client-secret",
                    "auth_uri": helper.GOOGLE_AUTH_URL,
                    "token_uri": helper.GOOGLE_TOKEN_URL,
                }
            }
        )

        client = helper.parse_client_config(path)

        self.assertEqual(client.client_id, "desktop.apps.googleusercontent.com")
        self.assertEqual(client.client_secret, "client-secret")
        self.assertEqual(client.auth_uri, helper.GOOGLE_AUTH_URL)
        self.assertNotIn("client-secret", repr(client))

    def test_rejects_web_client_and_unexpected_endpoints(self):
        web_path = self.write_client({"web": {"client_id": "id"}})
        with self.assertRaises(helper.ClientConfigError):
            helper.parse_client_config(web_path)

        endpoint_values = [
            "http://oauth2.googleapis.com/token",
            "https://oauth2.googleapis.com:443/token",
            "https://oauth2.googleapis.com/token?target=attacker",
            "https://oauth2.googleapis.com.evil.example/token",
            "https://user@oauth2.googleapis.com/token",
        ]
        for endpoint in endpoint_values:
            with self.subTest(endpoint=endpoint):
                path = self.write_client(
                    {"installed": {"client_id": "id", "token_uri": endpoint}}
                )
                with self.assertRaises(helper.ClientConfigError):
                    helper.parse_client_config(path)

    def test_uses_xdg_config_home(self):
        with mock.patch.dict("os.environ", {"XDG_CONFIG_HOME": "/tmp/config-home"}):
            self.assertEqual(
                helper.client_config_path(),
                Path("/tmp/config-home") / helper.APP_ID / helper.CLIENT_FILENAME,
            )


class SecretStoreTests(unittest.TestCase):
    def test_refresh_token_is_passed_on_stdin_not_argv(self):
        calls = []

        def runner(command, **kwargs):
            calls.append((command, kwargs))
            return subprocess.CompletedProcess(command, 0, stdout=b"", stderr=b"")

        store = helper.SecretStore(executable="/usr/bin/secret-tool", runner=runner)
        store.store("refresh-secret")

        command, kwargs = calls[0]
        self.assertNotIn("refresh-secret", command)
        self.assertEqual(kwargs["input"], b"refresh-secret")
        self.assertEqual(command[1], "store")

    def test_lookup_and_delete_use_fixed_attributes(self):
        calls = []

        def runner(command, **kwargs):
            calls.append(command)
            stdout = b"stored-token\n" if command[1] == "lookup" else b""
            return subprocess.CompletedProcess(command, 0, stdout=stdout, stderr=b"")

        store = helper.SecretStore(executable="secret-tool", runner=runner)
        self.assertEqual(store.lookup(), "stored-token")
        store.delete()

        self.assertEqual(calls[0], ["secret-tool", "lookup", *helper.SECRET_ATTRIBUTES])
        self.assertEqual(calls[1], ["secret-tool", "clear", *helper.SECRET_ATTRIBUTES])


class EventNormalizationTests(unittest.TestCase):
    def event(self, **overrides):
        value = {
            "id": "event-1",
            "summary": "Planning",
            "status": "confirmed",
            "start": {"dateTime": "2025-08-27T10:00:00+02:00"},
            "end": {"dateTime": "2025-08-27T11:00:00+02:00"},
        }
        value.update(overrides)
        return value

    def test_normalizes_timed_and_all_day_events(self):
        timed = helper.normalize_event(self.event(transparency="transparent"))
        all_day = helper.normalize_event(
            self.event(
                summary="",
                eventType="birthday",
                start={"date": "2025-08-27"},
                end={"date": "2025-08-28"},
            )
        )

        self.assertEqual(
            timed,
            {
                "id": "event-1",
                "summary": "Planning",
                "allDay": False,
                "start": "2025-08-27T10:00:00+02:00",
                "end": "2025-08-27T11:00:00+02:00",
                "eventType": "default",
                "transparency": "transparent",
            },
        )
        self.assertTrue(all_day["allDay"])
        self.assertEqual(all_day["summary"], "Busy")
        self.assertEqual(all_day["eventType"], "birthday")
        self.assertEqual(all_day["transparency"], "opaque")

    def test_excludes_cancelled_working_location_and_self_declined(self):
        self.assertIsNone(helper.normalize_event(self.event(status="cancelled")))
        self.assertIsNone(helper.normalize_event(self.event(eventType="workingLocation")))
        self.assertIsNone(
            helper.normalize_event(
                self.event(
                    attendees=[
                        {"self": False, "responseStatus": "accepted"},
                        {"self": True, "responseStatus": "declined"},
                    ]
                )
            )
        )

    def test_includes_transparent_and_other_attendee_declines(self):
        event = helper.normalize_event(
            self.event(
                transparency="transparent",
                attendees=[{"self": False, "responseStatus": "declined"}],
            )
        )
        self.assertEqual(event["transparency"], "transparent")

    def test_drops_malformed_events(self):
        self.assertIsNone(helper.normalize_event(self.event(id="")))
        self.assertIsNone(helper.normalize_event(self.event(start={})))


class ApiTests(unittest.TestCase):
    def test_fetch_events_paginates_primary_calendar_with_partial_fields(self):
        requests = []
        pages = [
            {
                "items": [
                    {
                        "id": "first",
                        "summary": "First",
                        "start": {"date": "2025-08-27"},
                        "end": {"date": "2025-08-28"},
                    }
                ],
                "nextPageToken": "next-page",
            },
            {
                "items": [
                    {
                        "id": "second",
                        "status": "cancelled",
                        "start": {"date": "2025-08-28"},
                        "end": {"date": "2025-08-29"},
                    },
                    {
                        "id": "third",
                        "start": {"dateTime": "2025-08-29T10:00:00Z"},
                        "end": {"dateTime": "2025-08-29T11:00:00Z"},
                    },
                ]
            },
        ]

        def urlopen(request, timeout):
            requests.append(request)
            return FakeResponse(pages.pop(0))

        events = helper.fetch_events(
            "access-token", "2025-08-01T00:00:00Z", "2025-09-01T00:00:00Z", urlopen=urlopen
        )

        self.assertEqual([event["id"] for event in events], ["first", "third"])
        self.assertEqual(len(requests), 2)
        self.assertIn("/calendars/primary/events?", requests[0].full_url)
        first_query = urllib.parse.parse_qs(urllib.parse.urlparse(requests[0].full_url).query)
        second_query = urllib.parse.parse_qs(urllib.parse.urlparse(requests[1].full_url).query)
        self.assertEqual(first_query["singleEvents"], ["true"])
        self.assertEqual(first_query["orderBy"], ["startTime"])
        self.assertIn("nextPageToken", first_query["fields"][0])
        self.assertEqual(second_query["pageToken"], ["next-page"])
        self.assertEqual(requests[0].get_header("Authorization"), "Bearer access-token")

    def test_invalid_grant_deletes_refresh_token(self):
        store = FakeSecretStore("refresh-token")
        client = helper.OAuthClient(client_id="id")

        def urlopen(request, timeout):
            raise urllib.error.HTTPError(
                request.full_url,
                400,
                "Bad Request",
                {},
                io.BytesIO(b'{"error":"invalid_grant"}'),
            )

        with self.assertRaises(helper.AuthenticationRequiredError):
            helper.refresh_access_token(client, store, urlopen=urlopen)
        self.assertEqual(store.deleted, 1)
        self.assertIsNone(store.token)

    def test_access_token_is_returned_without_persistence(self):
        store = FakeSecretStore("refresh-token")
        client = helper.OAuthClient(client_id="id")
        captured_form = {}

        def urlopen(request, timeout):
            captured_form.update(urllib.parse.parse_qs(request.data.decode("utf-8")))
            return FakeResponse({"access_token": "memory-only-token"})

        token = helper.refresh_access_token(client, store, urlopen=urlopen)

        self.assertEqual(token, "memory-only-token")
        self.assertEqual(store.stored, [])
        self.assertEqual(captured_form["refresh_token"], ["refresh-token"])

    def test_disconnect_revokes_before_deleting_secret(self):
        actions = []

        class Store(FakeSecretStore):
            def lookup(self):
                actions.append("lookup")
                return super().lookup()

            def delete(self):
                actions.append("delete")
                super().delete()

        store = Store("refresh-token")

        def urlopen(request, timeout):
            actions.append("revoke")
            form = urllib.parse.parse_qs(request.data.decode("utf-8"))
            self.assertEqual(form["token"], ["refresh-token"])
            return FakeResponse(raw=b"")

        result = helper.disconnect(store, urlopen=urlopen)

        self.assertEqual(actions, ["lookup", "revoke", "delete"])
        self.assertEqual(
            result,
            {
                "ok": True,
                "connected": False,
                "revoked": True,
                "localSecretRemoved": True,
            },
        )

    def test_disconnect_removes_local_secret_when_revoke_is_offline(self):
        store = FakeSecretStore("refresh-token")

        def urlopen(request, timeout):
            raise urllib.error.URLError("offline")

        result = helper.disconnect(store, urlopen=urlopen)

        self.assertFalse(result["revoked"])
        self.assertTrue(result["localSecretRemoved"])
        self.assertIn("warning", result)
        self.assertEqual(store.deleted, 1)
        self.assertIsNone(store.token)


class StatusAndCliTests(unittest.TestCase):
    def valid_client_path(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "client.json"
        path.write_text(json.dumps({"installed": {"client_id": "id"}}), encoding="utf-8")
        return path

    def test_status_reports_missing_client_and_secret_tool(self):
        result = helper.get_status(
            path=Path("/does/not/exist"),
            secret_store=FakeSecretStore(),
        )
        self.assertFalse(result["configured"])
        self.assertFalse(result["connected"])
        self.assertEqual(result["reason"], "invalid_client_config")

        unavailable = FakeSecretStore()
        unavailable.available = False
        result = helper.get_status(path=self.valid_client_path(), secret_store=unavailable)
        self.assertTrue(result["configured"])
        self.assertFalse(result["secretToolAvailable"])
        self.assertEqual(result["reason"], "missing_secret_tool")

    def test_status_reports_connected_without_exposing_token(self):
        result = helper.get_status(
            path=self.valid_client_path(),
            secret_store=FakeSecretStore("do-not-print"),
        )
        self.assertTrue(result["connected"])
        self.assertNotIn("do-not-print", json.dumps(result))

    def test_events_command_requires_all_arguments_and_valid_rfc3339(self):
        args = helper.parse_args(
            [
                "events",
                "--time-min",
                "2025-08-01T00:00:00Z",
                "--time-max",
                "2025-09-01T00:00:00+00:00",
                "--request-id",
                "request-7",
            ]
        )
        self.assertEqual(args.command, "events")
        self.assertEqual(args.request_id, "request-7")

        with self.assertRaises(helper.UsageError):
            helper.parse_args(["events", "--time-min", "2025-08-01"])

    def test_events_command_rejects_reversed_and_oversized_ranges(self):
        store = FakeSecretStore("refresh-token")
        client = helper.OAuthClient(client_id="id")

        for time_min, time_max in [
            ("2025-09-01T00:00:00Z", "2025-08-01T00:00:00Z"),
            ("2025-01-01T00:00:00Z", "2025-12-31T00:00:00Z"),
        ]:
            args = helper.parse_args(
                [
                    "events",
                    "--time-min", time_min,
                    "--time-max", time_max,
                    "--request-id", "request-8",
                ]
            )
            with self.subTest(time_min=time_min, time_max=time_max), mock.patch.object(
                helper, "SecretStore", return_value=store
            ), mock.patch.object(helper, "parse_client_config", return_value=client):
                with self.assertRaises(helper.UsageError):
                    helper.run_command(args)

    def test_disconnect_does_not_require_client_file(self):
        store = FakeSecretStore()
        args = helper.parse_args(["disconnect"])
        with mock.patch.object(helper, "SecretStore", return_value=store), mock.patch.object(
            helper, "parse_client_config"
        ) as parse_client:
            result = helper.run_command(args)

        parse_client.assert_not_called()
        self.assertEqual(
            result,
            {
                "ok": True,
                "connected": False,
                "revoked": False,
                "localSecretRemoved": True,
            },
        )
        self.assertEqual(store.deleted, 1)

    def test_main_prints_one_json_object_for_parse_error(self):
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            exit_code = helper.main(["events"])

        lines = stdout.getvalue().splitlines()
        self.assertEqual(exit_code, 2)
        self.assertEqual(len(lines), 1)
        result = json.loads(lines[0])
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"]["code"], "usage_error")


if __name__ == "__main__":
    unittest.main()
