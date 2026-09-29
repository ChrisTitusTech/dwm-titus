import QtQuick
import Quickshell
import qs.core

ShellRoot {
    id: root
    property int assertions: 0

    WeatherModel { id: weather }

    function check(value, message) {
        assertions++;
        if (!value) throw new Error(message);
    }
    function response(overrides) {
        const data = {
            current_units: { temperature_2m: "°C", wind_speed_10m: "mp/h" },
            current: { temperature_2m: 20.7, apparent_temperature: 20.4, weather_code: 2, is_day: 1, wind_speed_10m: 10.8 },
            daily: { temperature_2m_max: [22.1], temperature_2m_min: [16.1] }
        };
        return JSON.stringify(Object.assign(data, overrides || {}));
    }
    function run() {
        try {
            check(!weather.configured && !weather.available && weather.request === null,
                "A missing weather.conf never fetches");

            const settings = weather.parseConfig("# Ipswich\nlatitude=52.0567\nlongitude = 1.1482\nplace=Ipswich<b>\nwind=mph\n");
            check(settings !== null && settings.latitude === 52.0567 && settings.longitude === 1.1482, "Coordinates parse");
            check(settings.place === "Ipswichb" && settings.temperature === "celsius" && settings.wind === "mph",
                "Place is sanitized and units default");
            for (const invalid of ["", "latitude=52\n", "latitude=91\nlongitude=0", "latitude=0\nlongitude=-181",
                    "latitude=1e2\nlongitude=0", "latitude=0\nlongitude=0&x=1", "latitude=0\nlongitude=0\ntemperature=kelvin",
                    "latitude=0\nlongitude=0\nwind=furlongs"])
                check(weather.parseConfig(invalid) === null, "Invalid config is rejected: " + JSON.stringify(invalid));

            const url = weather.requestUrl(settings);
            check(url.startsWith("https://api.open-meteo.com/v1/forecast?latitude=52.0567&longitude=1.1482&"), "Request URL location");
            check(url.indexOf("temperature_unit=celsius") > 0 && url.indexOf("wind_speed_unit=mph") > 0, "Request URL units");

            const reading = weather.parseResponse(root.response());
            check(reading !== null && reading.temperature === 20.7 && reading.code === 2 && reading.isDay, "Current conditions parse");
            check(reading.high === 22.1 && reading.low === 16.1 && reading.windUnit === "mp/h", "Daily range and units parse");
            for (const invalid of ["", "not json", "null", "{}", root.response({ current: { temperature_2m: "warm" } }),
                    root.response({ daily: { temperature_2m_max: [], temperature_2m_min: [] } })])
                check(weather.parseResponse(invalid) === null, "Invalid response is rejected: " + invalid.slice(0, 40));

            check(weather.iconFor(0, true) === "\u{F0599}" && weather.iconFor(0, false) === "\u{F0594}", "Clear day and night icons");
            check(weather.iconFor(63, true) === "\u{F0597}" && weather.iconFor(82, true) === "\u{F0596}", "Rain icons");
            check(weather.iconFor(73, true) === "\u{F0598}" && weather.iconFor(95, true) === "\u{F0593}", "Snow and storm icons");
            check(weather.describe(2) === "Partly cloudy" && weather.describe(1234) === "Unknown", "Descriptions");

            weather.settings = settings;
            weather.reading = reading;
            weather.fetchedAt = Date.now();
            weather.now = weather.fetchedAt;
            check(weather.available && weather.panelText === "21°" && weather.icon === "\u{F0595}", "Panel text and icon");
            check(weather.tooltipText === "Ipswichb - Partly cloudy, 21°C (feels 20°) - H 22° L 16° - wind 11 mp/h",
                "Tooltip text: " + weather.tooltipText);
            weather.now = weather.fetchedAt + weather.staleAfter;
            check(!weather.available && weather.panelText === "", "Stale readings are hidden");

            console.info("Weather model tests: PASS (" + assertions + " assertions)");
        } catch (error) {
            console.error("Weather model FAILED: " + error);
        } finally {
            Qt.quit();
        }
    }

    Component.onCompleted: Qt.callLater(root.run)
}
