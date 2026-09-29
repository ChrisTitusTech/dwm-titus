import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    // Weather is opt-in: nothing is fetched until weather.conf names a valid
    // location, so installs without it never contact the forecast service.
    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string configuredConfigHome: Quickshell.env("XDG_CONFIG_HOME")
    readonly property string configHome: root.configuredConfigHome.startsWith("/")
        ? root.configuredConfigHome : root.homeDir + "/.config"
    readonly property string configPath: root.configHome + "/dwm-titus/weather.conf"
    readonly property string endpoint: "https://api.open-meteo.com/v1/forecast"
    readonly property int refreshInterval: 15 * 60 * 1000
    readonly property int retryInterval: 5 * 60 * 1000
    readonly property int requestTimeout: 20 * 1000
    // Weather observations are sampled; hide readings too old to trust.
    readonly property int staleAfter: 60 * 60 * 1000

    property var settings: null
    property var reading: null
    property double fetchedAt: 0
    property double now: Date.now()
    property var request: null
    readonly property bool configured: root.settings !== null
    readonly property bool available: root.configured && root.reading !== null
        && root.now - root.fetchedAt < root.staleAfter
    readonly property string icon: root.available ? root.iconFor(root.reading.code, root.reading.isDay) : ""
    readonly property string panelText: root.available ? Math.round(root.reading.temperature) + "\u00B0" : ""
    readonly property string tooltipText: !root.available ? "" : [
        root.settings.place,
        root.describe(root.reading.code) + ", " + Math.round(root.reading.temperature) + root.reading.temperatureUnit
            + " (feels " + Math.round(root.reading.apparent) + "\u00B0)",
        "H " + Math.round(root.reading.high) + "\u00B0 L " + Math.round(root.reading.low) + "\u00B0 - wind "
            + Math.round(root.reading.wind) + " " + root.reading.windUnit
    ].filter(part => part.length > 0).join(" - ")

    function parseConfig(text) {
        const values = {};
        for (const raw of text.split("\n")) {
            const line = raw.trim();
            if (line.length === 0 || line.startsWith("#")) continue;
            const split = line.indexOf("=");
            if (split <= 0) continue;
            values[line.slice(0, split).trim()] = line.slice(split + 1).trim();
        }
        const numeric = /^-?[0-9]+(\.[0-9]+)?$/;
        if (!numeric.test(values.latitude || "") || !numeric.test(values.longitude || "")) return null;
        const latitude = Number(values.latitude);
        const longitude = Number(values.longitude);
        if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return null;
        const temperature = values.temperature || "celsius";
        const wind = values.wind || "kmh";
        if (["celsius", "fahrenheit"].indexOf(temperature) < 0
                || ["kmh", "mph", "ms", "kn"].indexOf(wind) < 0) return null;
        return {
            latitude: latitude,
            longitude: longitude,
            place: (values.place || "").replace(/[^\w .,'-]/g, "").slice(0, 40),
            temperature: temperature,
            wind: wind
        };
    }

    function requestUrl(settings) {
        return root.endpoint + "?latitude=" + settings.latitude + "&longitude=" + settings.longitude
            + "&current=temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m"
            + "&daily=temperature_2m_max,temperature_2m_min&forecast_days=1&timezone=auto"
            + "&temperature_unit=" + settings.temperature + "&wind_speed_unit=" + settings.wind;
    }

    function parseResponse(text) {
        let data;
        try {
            data = JSON.parse(text);
        } catch (error) {
            return null;
        }
        const current = data && data.current;
        const units = data && data.current_units;
        const daily = data && data.daily;
        if (!current || !units || !daily) return null;
        const fields = [current.temperature_2m, current.apparent_temperature, current.weather_code,
            current.wind_speed_10m, (daily.temperature_2m_max || [])[0], (daily.temperature_2m_min || [])[0]];
        if (fields.some(value => typeof value !== "number" || !isFinite(value))) return null;
        return {
            temperature: current.temperature_2m,
            apparent: current.apparent_temperature,
            code: current.weather_code,
            isDay: current.is_day !== 0,
            wind: current.wind_speed_10m,
            high: daily.temperature_2m_max[0],
            low: daily.temperature_2m_min[0],
            temperatureUnit: typeof units.temperature_2m === "string" ? units.temperature_2m : "\u00B0",
            windUnit: typeof units.wind_speed_10m === "string" ? units.wind_speed_10m : ""
        };
    }

    // WMO weather interpretation codes, as documented by Open-Meteo.
    function iconFor(code, isDay) {
        if (code === 0) return isDay ? "\u{F0599}" : "\u{F0594}";
        if (code === 1 || code === 2) return isDay ? "\u{F0595}" : "\u{F0F31}";
        if (code === 3) return "\u{F0590}";
        if (code === 45 || code === 48) return "\u{F0591}";
        if (code === 65 || code === 67 || code === 82) return "\u{F0596}";
        if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return "\u{F0597}";
        if ((code >= 71 && code <= 77) || code === 85 || code === 86) return "\u{F0598}";
        if (code >= 95 && code <= 99) return "\u{F0593}";
        return "\u{F0590}";
    }

    function describe(code) {
        if (code === 0) return "Clear";
        if (code === 1) return "Mostly clear";
        if (code === 2) return "Partly cloudy";
        if (code === 3) return "Overcast";
        if (code === 45 || code === 48) return "Fog";
        if (code >= 51 && code <= 57) return "Drizzle";
        if (code >= 61 && code <= 67) return code >= 65 ? "Heavy rain" : "Rain";
        if (code >= 71 && code <= 77) return "Snow";
        if (code >= 80 && code <= 82) return "Showers";
        if (code === 85 || code === 86) return "Snow showers";
        if (code >= 95 && code <= 99) return "Thunderstorm";
        return "Unknown";
    }

    function applyConfig(text) {
        const parsed = root.parseConfig(text);
        if (JSON.stringify(parsed) === JSON.stringify(root.settings)) return;
        root.settings = parsed;
        root.reading = null;
        root.fetchedAt = 0;
        root.refresh();
    }

    function finish(reading) {
        requestTimer.stop();
        root.request = null;
        root.now = Date.now();
        if (reading) {
            root.reading = reading;
            root.fetchedAt = root.now;
        }
        refreshTimer.interval = reading ? root.refreshInterval : root.retryInterval;
        refreshTimer.restart();
    }

    function refresh() {
        if (root.request) {
            root.request.onreadystatechange = null;
            root.request.abort();
            root.request = null;
        }
        requestTimer.stop();
        if (!root.configured) {
            refreshTimer.stop();
            return;
        }
        const xhr = new XMLHttpRequest();
        root.request = xhr;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || root.request !== xhr) return;
            root.finish(xhr.status === 200 ? root.parseResponse(xhr.responseText) : null);
        };
        xhr.open("GET", root.requestUrl(root.settings));
        xhr.send();
        requestTimer.restart();
    }

    FileView {
        path: root.configPath
        watchChanges: true
        printErrors: false
        onLoaded: root.applyConfig(text())
        onLoadFailed: root.applyConfig("")
        onFileChanged: reload()
    }

    Timer {
        id: refreshTimer
        interval: root.refreshInterval
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        id: requestTimer
        interval: root.requestTimeout
        repeat: false
        onTriggered: if (root.request) {
            const xhr = root.request;
            xhr.onreadystatechange = null;
            xhr.abort();
            root.finish(null);
        }
    }
}
