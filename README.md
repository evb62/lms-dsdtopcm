# On-the-fly DSD to PCM transcoding for Lyrion Music Server (LMS)

Background: a music library where some parts are in PCM audio (FLAC, for instance), others are in DSD audio (DSD compressed to WavPack/wv). Direct Stream Digital is the format used in Super Audio CDs. There is no software volume control in Lyrion for DSD.

This plugin provides on-the-fly transcoding of DSD files compressed in WavPack to PCM. PCM will be streamed to the player, instead of DSD, enabling use of software volume control. After installing the plugin, other settings will be available in the Player WebUI -> Extra Settings.

Enabled per player, in the web UI.

## Installation

Scroll to the end of the "Manage Plugins" page in the LMS WebUI. Find the "Additional Repositories" and fill the line with the repository address: https://raw.githubusercontent.com/evb62/lms-plugins/main/public.xml.

Accept the restart prompt, then enable the plugin.

## Use

(Material Skin)

Server-wide: Settings -> Manage plugins -> DSD Transcode (or go directly to DSD to PCM Transcoding)

Player Settings: Settings -> Player -> pick the player -> Extra Settings -> DSD Transcode
- Sample rate override: Overrides the server-wide default for this player only. Leave on "Use default" unless this player needs a different rate than the rest (e.g. while synced, only the sync-group master's setting applies). Rates available: 44.1 kHz, 88.2 kHz, 176.4 kHz. DSD transcoding to 192 kHZ could result in hissing audio, so it is not provided.
- Headroom (dB): Gain applied before resampling, to keep the resampler's overshoot from clipping. -3 is a reasonable default; 0 for unity gain. Positive values accepted.
