# engine/

Engine files for the automatic video runs (Rota 360, Kokpit 360, Ayet ve Bilim).
Runs download these with curl instead of reading them into the chat:

    mkdir -p ~/eng && cd ~/eng && for f in RUNBOOK.txt RUNBOOK_KOKPIT.txt RUNBOOK_AYET.txt PLAYBOOK.txt bundle.sh kokpit_bundle.sh ayet_bundle.sh finish_audio.sh thumb.py ayet_topics.json; do curl -fsSL -o $f https://raw.githubusercontent.com/ClaudeRepo620/video_repo/main/engine/$f; done

- `bundle.sh` / `kokpit_bundle.sh` / `ayet_bundle.sh`: run as `bash <bundle> ~/faceless-shorts/<slug>`.
- `ayet_topics.json`: saved topic list from miracles-of-quran.com (set `used_by` after each video).
- Music stays private in the panel (Pixabay licence); never commit MP3s here.
