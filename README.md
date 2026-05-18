# Baby Monitor — RTSP Audio Noise Alert for Home Assistant

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/docker-ready-blue.svg)](Dockerfile)

A lightweight Docker container that continuously monitors audio from an RTSP camera stream and sends alerts to **Home Assistant** when noise exceeds a configurable threshold. Designed for baby monitoring but works with any RTSP camera.

---

## How It Works

Uses **FFmpeg's `ebur128` filter** to sample audio volume from the RTSP stream every few seconds. When the volume exceeds the threshold for N consecutive readings, it fires a webhook to Home Assistant and publishes the raw volume to an MQTT topic.

```
RTSP Camera → FFmpeg → Volume check → MQTT (live volume)
                                    → HA Webhook (noise alert)
```

**Features:**
- Configurable dBFS threshold and trigger count (avoids false positives)
- Dual camera support — automatically falls back to a secondary URL on connection loss
- Auto-reconnect loop with configurable retry delay
- MQTT volume publishing for dashboards/graphs
- Home Assistant webhook integration for automations
- Fully configurable via environment variables — no code changes needed

---

## Quick Start

### Docker Compose

```yaml
services:
  baby-monitor:
    image: ghcr.io/aldendana/ha-baby-monitor:latest
    restart: unless-stopped
    environment:
      - CAMERA_URL=rtsp://user:pass@192.168.1.x:554/stream
      - THRESHOLD=-30
      - MQTT_HOST=192.168.1.x
      - MQTT_USER=mqtt_user
      - MQTT_PASS=mqtt_password
      - WEBHOOK_URL=http://homeassistant:8123/api/webhook/your_webhook_id
```

### Build locally

```bash
docker build -t baby-monitor .
docker run --restart unless-stopped \
  -e CAMERA_URL="rtsp://user:pass@192.168.1.x:554/stream" \
  -e THRESHOLD=-30 \
  -e MQTT_HOST=192.168.1.x \
  -e MQTT_USER=mqtt_user \
  -e MQTT_PASS=mqtt_password \
  -e WEBHOOK_URL="http://homeassistant:8123/api/webhook/your_webhook_id" \
  baby-monitor
```

---

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `CAMERA_URL` | *(required)* | Primary RTSP stream URL |
| `CAMERA_FALLBACK_URL` | *(empty)* | Secondary RTSP URL — used when primary fails |
| `THRESHOLD` | `-30` | Noise threshold in dBFS. Higher = more sensitive (e.g. `-25` triggers on quieter sounds) |
| `TRIGGER_COUNT` | `2` | Consecutive loud readings required before alert fires |
| `SAMPLE_INTERVAL` | `2` | Seconds between volume samples |
| `MQTT_HOST` | `localhost` | MQTT broker host |
| `MQTT_PORT` | `1883` | MQTT broker port |
| `MQTT_USER` | `homeassistant` | MQTT username |
| `MQTT_PASS` | *(empty)* | MQTT password |
| `MQTT_TOPIC` | `home/baby_monitor/volume` | Topic for live volume readings |
| `WEBHOOK_URL` | `http://homeassistant:8123/api/webhook/baby_noise_alert` | HA webhook URL to call on alert |
| `RETRY_DELAY` | `5` | Seconds to wait before retrying after connection loss |
| `FFMPEG_LOGLEVEL` | `verbose` | FFmpeg log verbosity |

---

## Home Assistant Setup

### 1. Create the webhook automation

```yaml
- alias: Baby noise alert
  triggers:
    - trigger: webhook
      webhook_id: baby_noise_alert
      allowed_methods: [POST]
      local_only: true
  actions:
    - action: notify.mobile_app_your_phone
      data:
        title: Baby Monitor
        message: Noise detected in baby room
```

### 2. MQTT sensor for live volume (optional)

```yaml
mqtt:
  sensor:
    - name: Baby Room Volume
      state_topic: home/baby_monitor/volume
      unit_of_measurement: dB
      device_class: signal_strength
```

---

## Threshold Tuning

The `ebur128` filter measures integrated loudness in dBFS. Typical values:

| Environment | Typical range |
|---|---|
| Silent room | -60 to -45 dB |
| Baby sleeping (white noise) | -40 to -30 dB |
| Baby crying | -20 to -10 dB |
| Speech | -30 to -15 dB |

Start with `-30` and adjust based on the MQTT volume readings. Enable debug logging (`FFMPEG_LOGLEVEL=verbose`) to see real-time volume output.

---

## License

MIT — see [LICENSE](LICENSE)
