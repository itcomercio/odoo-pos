# iotbox recipe

La receta descarga `odoo-iotbox` directamente desde GitHub usando el fetcher estándar de Yocto:

- rama: `main`
- transporte: `git://` con `protocol=https`
- `SRCREV = "${AUTOREV}"` para seguir siempre el ultimo commit de `main`

## Fuente upstream

Repositorio:

`https://github.com/itcomercio/odoo-iotbox`

## Resultado

La receta instala el código en `/opt/iotbox`, el fichero de entorno en `/etc/iotbox/iotbox.env` y habilita `iotbox.service` en systemd.

Si el upstream trae modulos Odoo, se detectan directorios con `__manifest__.py`
dentro de `addon/` y se empaquetan en:

- `/var/lib/odoo/custom_addons`

El directorio `addon/` no se instala en `/opt/iotbox` para evitar duplicado
del mismo modulo en dos rutas dentro del RPM.

