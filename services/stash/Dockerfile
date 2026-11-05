# The upstream image has ffmpeg with VAAPI but no VAAPI driver for AMD.
FROM stashapp/stash:latest
RUN apk add --no-cache mesa-va-gallium
