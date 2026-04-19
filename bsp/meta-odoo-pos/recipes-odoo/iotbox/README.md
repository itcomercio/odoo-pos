# iotbox recipe

La receta descarga `odoo-iotbox` directamente desde GitHub usando el fetcher estándar de Yocto:

- rama: `main`
- transporte: `git://` con `protocol=https`
- commit fijado en `SRCREV` para builds reproducibles

## Fuente upstream

Repositorio:

`https://github.com/itcomercio/odoo-iotbox`

## Resultado

La receta instala el código en `/opt/iotbox`, el fichero de entorno en `/etc/iotbox/iotbox.env` y habilita `iotbox.service` en systemd.

