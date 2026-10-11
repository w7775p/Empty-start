# In-game font assets

| File | Usage | Source | License |
| --- | --- | --- | --- |
| NotoSansSC-VF.ttf | Global Godot Theme font for UI, barrage, story, scripture, and controls | https://github.com/google/fonts/tree/main/ofl/notosanssc | SIL OFL 1.1 |
| ZCOOLKuaiLe-Regular.ttf | Streamer names, fan-group names, and naming inputs | https://github.com/googlefonts/zcool-kuaile/tree/main/fonts/ttf | SIL OFL 1.1 |

The accompanying OFL-NotoSansSC.txt and OFL-ZCOOLKuaiLe.txt are distributed with the original fonts.
ui/theme/base_theme.tres sets the global default and role-specific theme type variations:

- StreamerNameLabel: streamer names in standard-size text
- StreamerHeadingLabel: streamer names in heading-size text
- StreamerMutedLabel: subdued streamer names in history/scripture UI
- FanGroupNameLabel: fan-group name display
- StreamerNameInput: streamer and fan-group name entry

Set theme_type_variation on new named text controls to reuse these fonts.
The rest of the UI inherits the global Noto Sans SC font automatically.
Keep font-size, color, motion, emphasis, and handcrafted special-impact typography defined by their existing views.
