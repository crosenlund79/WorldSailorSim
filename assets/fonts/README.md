# Fonts

| Font | Files | Use | Licence | Source |
|---|---|---|---|---|
| Barlow (Regular, Medium, SemiBold) | `Barlow-*.ttf` | the functional UI font: every number, menu, dialog and description | SIL Open Font License 1.1, `OFL.txt` | The Barlow Project Authors, <https://github.com/jpt/barlow> |
| Barlow Condensed (Regular, Medium, SemiBold) | `BarlowCondensed-*.ttf` | Real Horizon's instrument lettering: headings, titles, the title wordmark, harbour signage | SIL Open Font License 1.1, `OFL-BarlowCondensed.txt` | The Barlow Project Authors, via Google Fonts <https://github.com/google/fonts/tree/main/ofl/barlowcondensed> |
| Patrick Hand (Regular) | `PatrickHand-Regular.ttf` | the display font, used sparingly: the title, decorative headings, harbour signs, secret achievement names | SIL Open Font License 1.1, `OFL-PatrickHand.txt` | Patrick Wagesreiter, via Google Fonts <https://github.com/google/fonts/tree/main/ofl/patrickhand> (version 1.003) |

All fonts may be bundled and redistributed with the game under the OFL.
The fonts are not modified or renamed. Which text uses which font is decided
in the theme generator `tools/build_theme.gd` and, at run time, `src/ui/theme/ui_theme.gd` (Real Horizon: headings and display text use Barlow Condensed; Patrick Hand is kept bundled but no longer shown).
