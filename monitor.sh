#!/bin/bash
set -u

THRESHOLD=${THRESHOLD:--30}
MQTT_HOST=${MQTT_HOST:-localhost}
MQTT_PORT=${MQTT_PORT:-1883}
MQTT_USER=${MQTT_USER:-homeassistant}
MQTT_PASS=${MQTT_PASS:-}
MQTT_TOPIC=${MQTT_TOPIC:-home/baby_monitor/volume}
WEBHOOK_URL=${WEBHOOK_URL:-http://homeassistant:8123/api/webhook/baby_noise_alert}
CAMERA_URL=${CAMERA_URL:-}
CAMERA_FALLBACK_URL=${CAMERA_FALLBACK_URL:-}
TRIGGER_COUNT=${TRIGGER_COUNT:-2}
SAMPLE_INTERVAL=${SAMPLE_INTERVAL:-2}
RETRY_DELAY=${RETRY_DELAY:-5}
FFMPEG_LOGLEVEL=${FFMPEG_LOGLEVEL:-verbose}

LAST_GOOD_CAMERA=""
CONSECUTIVE_ERRORS=0

log() {
  printf '%s %s\n' "$(date '+%H:%M:%S')" "$*"
}

publish_volume() {
  local vol="$1"
  mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
    -u "$MQTT_USER" -P "$MQTT_PASS" \
    -t "$MQTT_TOPIC" -m "$vol" >/dev/null 2>&1 &
}

send_alert() {
  curl -fsS -X POST "$WEBHOOK_URL" >/dev/null 2>&1 &
}

is_loud() {
  awk -v v="$1" -v t="$THRESHOLD" 'BEGIN { exit (v+0 > t+0) ? 0 : 1 }'
}

monitor_camera() {
  local source_url="$1"
  local active_label="${source_url##*@}"
  local high_vol_count=0
  local got_reading=0
  local last_sample_ts=0
  local line tmp vol now

  log "🔌 Conectando a cámara: $active_label"

  while IFS= read -r line; do
    case "$line" in
      *" M:"*|M:*) ;;
      *) continue ;;
    esac

    if [ "$got_reading" -eq 0 ]; then
      got_reading=1
      LAST_GOOD_CAMERA="$source_url"
      if [ "$CONSECUTIVE_ERRORS" -gt 0 ]; then
        log "✅ Cámara reconectada: $active_label"
        CONSECUTIVE_ERRORS=0
      else
        log "✅ Cámara activa: $active_label"
      fi
    fi

    now=$(date +%s)
    if [ $((now - last_sample_ts)) -lt "$SAMPLE_INTERVAL" ]; then
      continue
    fi
    last_sample_ts=$now

    tmp="${line#*M:}"
    vol="${tmp%%S:*}"
    vol="${vol// /}"

    case "$vol" in
      ""|*inf*|*-nan*|*nan*)
        continue
        ;;
    esac

    log "🎧 Volumen: $vol dB ($active_label)"
    publish_volume "$vol"

    if is_loud "$vol"; then
      high_vol_count=$((high_vol_count + 1))
      log "🔊 Sonido alto ($high_vol_count/$TRIGGER_COUNT)"
      if [ "$high_vol_count" -ge "$TRIGGER_COUNT" ]; then
        log "🚨 ALERTA ENVIADA!"
        send_alert
        high_vol_count=0
      fi
    else
      high_vol_count=0
    fi
  done < <(
    ffmpeg -nostdin -hide_banner -loglevel "$FFMPEG_LOGLEVEL" \
      -rtsp_transport tcp \
      -i "$source_url" \
      -vn \
      -af "ebur128=peak=true:framelog=verbose" \
      -f null - 2>&1
  )

  if [ "$got_reading" -gt 0 ]; then
    log "⚠️ Se perdió la conexión con $active_label"
    return 10
  fi

  log "⚠️ No se pudo leer audio de $active_label"
  return 11
}

echo "🚀 Baby Monitor iniciado en $(date)"
echo "📊 Configuración:"
echo "   - Umbral: $THRESHOLD dB"
echo "   - Intervalo: $SAMPLE_INTERVAL segundos"
echo "   - Trigger: $TRIGGER_COUNT lecturas consecutivas"
echo "   - MQTT: $MQTT_HOST:$MQTT_PORT"
echo "   - Topic MQTT: $MQTT_TOPIC"
echo "   - Webhook: $WEBHOOK_URL"
echo "   - Cámara principal: $CAMERA_URL"
echo "   - Cámara fallback: $CAMERA_FALLBACK_URL"
echo "   - Reintentos automáticos habilitados"

echo "ℹ️ Nota: al pasar de volumedetect a ebur128, puede hacer falta reajustar el umbral ~±3 dB"

while true; do
  for TRY_CAMERA in "$CAMERA_URL" "$CAMERA_FALLBACK_URL"; do
    [ -z "$TRY_CAMERA" ] && continue
    monitor_camera "$TRY_CAMERA"
    CONSECUTIVE_ERRORS=$((CONSECUTIVE_ERRORS + 1))
  done

  if [ -n "$LAST_GOOD_CAMERA" ]; then
    log "Última cámara válida: ${LAST_GOOD_CAMERA##*@}"
  fi
  log "🔄 Esperando ${RETRY_DELAY}s antes de reintentar desde la principal..."
  sleep "$RETRY_DELAY"
done
