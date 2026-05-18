FROM jrottenberg/ffmpeg:6.0-ubuntu

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends curl mosquitto-clients && \
    rm -rf /var/lib/apt/lists/*

COPY monitor.sh /monitor.sh
RUN chmod +x /monitor.sh

ENTRYPOINT ["/bin/bash", "/monitor.sh"]
