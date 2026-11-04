"""Weather provider parsing, explicit requests and safe failure/persistence."""
from contextlib import redirect_stdout, redirect_stderr
import importlib.machinery
import io
import json
import os
from pathlib import Path
import tempfile
import sys
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
repo = Path(__file__).resolve().parents[1]
weather = importlib.machinery.SourceFileLoader("weather", str(repo / "scripts/dwm-weather")).load_module()
sample = {"current_condition": [{"temp_C": "22", "temp_F": "72", "FeelsLikeC": "25",
    "FeelsLikeF": "76", "humidity": "76", "windspeedKmph": "7", "windspeedMiles": "4",
    "weatherDesc": [{"value": "Overcast"}]}]}


class WeatherTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR"))
        self.addCleanup(self.directory.cleanup)
        self.environment = patch.dict(os.environ, {"XDG_CONFIG_HOME": self.directory.name})
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def fetch(self, location="Salt Lake City", unit="c", body=None):
        response = io.BytesIO(json.dumps(sample).encode() if body is None else body)
        with patch.object(weather.urllib.request.OpenerDirector, "open", return_value=response) as request:
            value = weather.fetch(location, unit)
            url = request.call_args.args[0].full_url
        return value, url

    def test_cli_preserves_negative_coordinates_and_validation(self):
        with patch.object(sys, "argv", ["dwm-weather", "fetch", "-33.86,151.21", "f"]), patch.object(weather, "fetch", return_value={}) as fetch, redirect_stdout(io.StringIO()):
            self.assertEqual(weather.main(), 0)
            fetch.assert_called_once_with("-33.86,151.21", "f")
        for arguments in (["fetch"], ["fetch", "Paris", "kelvin"]):
            with self.subTest(arguments=arguments), patch.object(sys, "argv", ["dwm-weather", *arguments]), patch.object(weather, "fetch") as fetch, redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as error:
                    weather.main()
                self.assertEqual(error.exception.code, 2)
                fetch.assert_not_called()

    def test_read_does_not_contact_service(self):
        with patch.object(weather.urllib.request.OpenerDirector, "open", side_effect=AssertionError("unexpected network")):
            self.assertIsNone(weather.load()["weather"])

    def test_explicit_city_and_units_persist_privately(self):
        value, url = self.fetch()
        self.assertEqual(url, "https://wttr.in/Salt%20Lake%20City?format=j1")
        self.assertEqual(value["weather"]["temperature"], "22")
        self.assertEqual(weather.state_path().stat().st_mode & 0o777, 0o600)
        self.assertEqual(weather.load(), value)
        value, _ = self.fetch("New York, US", "f")
        self.assertEqual((value["weather"]["temperature"], value["weather"]["wind"]), ("72", "4"))

    def test_empty_control_and_url_inputs_never_contact_service(self):
        with patch.object(weather.urllib.request.OpenerDirector, "open", side_effect=AssertionError("unexpected network")):
            for value in ("", " ", "Paris\nLondon", "../:help", "@example.com", "London?format=x", "x" * 121):
                with self.subTest(location=value), self.assertRaises(ValueError):
                    weather.fetch(value, "c")

    def test_failures_preserve_last_success(self):
        previous, _ = self.fetch()
        original = weather.state_path().read_bytes()
        for response in (b"not JSON", b"{}", b"x" * (weather.MAX_RESPONSE + 1)):
            with self.assertRaises(ValueError):
                self.fetch(body=response)
            self.assertEqual(weather.state_path().read_bytes(), original)
        with patch.object(weather.urllib.request.OpenerDirector, "open", side_effect=TimeoutError("offline")):
            with self.assertRaises(TimeoutError):
                weather.fetch("London", "c")
        self.assertEqual(weather.load(), previous)

    def test_overlong_numeric_fields_cannot_replace_a_saved_report(self):
        self.fetch()
        original = weather.state_path().read_bytes()
        for key in ("temp_C", "FeelsLikeC", "humidity", "windspeedKmph"):
            response = json.loads(json.dumps(sample))
            response["current_condition"][0][key] = "0." + "0" * 200
            with self.subTest(field=key), self.assertRaises(ValueError):
                self.fetch(body=json.dumps(response).encode())
            self.assertEqual(weather.state_path().read_bytes(), original)

    def test_invalid_state_is_preserved_without_network(self):
        path = weather.state_path()
        path.parent.mkdir()
        path.write_text('{"protocol":1,"unit":"c","location":42}')
        with patch.object(weather.urllib.request.OpenerDirector, "open", side_effect=AssertionError("unexpected network")):
            with self.assertRaises(ValueError):
                weather.fetch("London", "c")
        self.assertIn('"location":42', path.read_text())

    def test_encoded_report_limit_cannot_poison_the_cache(self):
        self.fetch()
        original = weather.state_path().read_bytes()
        response = json.loads(json.dumps(sample))
        for key in ("temp_C", "FeelsLikeC", "humidity", "windspeedKmph"):
            response["current_condition"][0][key] = "0." + "\U0001d7ce" * 190
        with self.assertRaises(ValueError):
            self.fetch(body=json.dumps(response).encode())
        self.assertEqual(weather.state_path().read_bytes(), original)

    def test_symlink_state_cannot_overwrite_target(self):
        path = weather.state_path()
        path.parent.mkdir()
        target = Path(self.directory.name) / "unrelated"
        target.write_text("preserve")
        path.symlink_to(target)
        with self.assertRaises(ValueError):
            self.fetch()
        self.assertEqual(target.read_text(), "preserve")

    def test_invalid_saved_timestamps_are_preserved_without_network(self):
        value, _ = self.fetch()
        for fetched in (float("nan"), float("inf"), -1, True):
            value["fetched"] = fetched
            weather.state_path().write_text(json.dumps(value))
            original = weather.state_path().read_bytes()
            with patch.object(weather.urllib.request.OpenerDirector, "open", side_effect=AssertionError("unexpected network")):
                with self.assertRaises(ValueError):
                    weather.fetch("London", "c")
            self.assertEqual(weather.state_path().read_bytes(), original)

    def test_redirect_is_not_followed(self):
        with self.assertRaises(ValueError):
            weather.NoRedirect().redirect_request(None, None, 302, "redirect", {}, "http://other.invalid/")

    def test_malformed_readings_are_rejected(self):
        for value in (None, [], {}, {"current_condition": []}, {"current_condition": [{}]}):
            with self.subTest(value=value), self.assertRaises(ValueError):
                weather.parse_weather(value, "c")


if __name__ == "__main__":
    unittest.main()
