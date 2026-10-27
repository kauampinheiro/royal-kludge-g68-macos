# Protocol credits and provenance

**English** · [Português](NOTICE.pt-BR.md)

This project did not figure out Royal Kludge's protocol on its own. The reverse
engineering was done by the community, capturing the USB traffic between the
official (Windows) software and the keyboard in Wireshark.

| Source | What came from it | License |
|---|---|---|
| [Rangoli](https://github.com/rnayabed/rangoli) — Debayan Sutradhar | The shape of the 9 remap buffers, the lighting buffer, the firmware code table | GPL-3.0 |
| [Kludge Knight](https://github.com/vinc3m1/kludgeknight) | Per-key color buffers, VK → firmware mapping, documentation of `KB.ini`/`led.xml` | GPL-3.0 |
| RK's official software (`RK KB`) | `Cfg.ini`, `Dev/<PID>/KB.ini`, `led.xml` and the keyboard artwork, redistributed here for the G68 models only | Royal Kludge's |

Because it derives from Rangoli, **this project is GPL-3.0** (see `LICENSE`).

The files under `Sources/RKCore/Resources/rk/` come from Royal Kludge's official
installer and are vendor data, not code of this project. They are included so
that the drawn keyboard and the effect list match the hardware. If you are
Royal Kludge and would rather they were not redistributed here, open an issue
and they will be removed in favour of a script that extracts them from your
installer.
