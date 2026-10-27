# Créditos e procedência do protocolo

[English](NOTICE.md) · **Português**

Este projeto não descobriu o protocolo da Royal Kludge sozinho. A engenharia
reversa foi feita pela comunidade, capturando no Wireshark o tráfego USB entre
o software oficial (Windows) e o teclado.

| Origem | O que veio de lá | Licença |
|---|---|---|
| [Rangoli](https://github.com/rnayabed/rangoli) — Debayan Sutradhar | Formato dos 9 buffers de remap, buffer de iluminação, tabela de códigos de firmware | GPL-3.0 |
| [Kludge Knight](https://github.com/vinc3m1/kludgeknight) | Buffers de cor por tecla, mapeamento VK → firmware, documentação do `KB.ini`/`led.xml` | GPL-3.0 |
| Software oficial RK (`RK KB`) | `Cfg.ini`, `Dev/<PID>/KB.ini`, `led.xml` e a arte dos teclados, redistribuídos aqui apenas para os modelos G68 | da Royal Kludge |

Por derivar do Rangoli, **este projeto é GPL-3.0** (ver `LICENSE`).

Os arquivos em `Sources/RKCore/Resources/rk/` vêm do instalador oficial da RK e
são dados do fabricante, não código deste projeto.
