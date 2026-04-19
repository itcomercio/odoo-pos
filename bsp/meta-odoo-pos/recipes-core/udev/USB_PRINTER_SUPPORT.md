# USB Thermal Printer Support para Odoo POS

## Cambios realizados

### 1. Configuración del kernel (`recipes-kernel/linux/files/usb-printer.cfg`)

Se ha añadido soporte de kernel para impresoras USB:

- **CONFIG_USB_PRINTER=y**: Driver usblp (Universal Serial Bus Printer class)
- **CONFIG_USB_XHCI_HCD=y**, **CONFIG_USB_EHCI_HCD=y**, etc.: Controladores USB host
- **CONFIG_HIDRAW=y**: Soporte para dispositivos HID (alternativa fallback)

Esto permite que el kernel cargue el módulo `usblp` cuando se conecta una impresora térmica USB.

### 2. Reglas udev (`recipes-core/udev/files/99-odoo-pos-usb-printer.rules`)

Se han definido reglas para:

- Detectar automáticamente impresoras USB por clase de dispositivo (bDeviceClass=0x07, bDeviceSubClass=0x01)
- Crear permisos apropiados en `/dev/usb/lp*` (MODE=0666)
- Asignar pertenencia al grupo `lpadmin` para acceso desde aplicaciones

### 3. Paquetes agregados a `odoo-pos-image.bb`

- **usbutils**: Herramientas de diagnóstico USB (`lsusb`, `usbhid-dump`)
- **libusb**: Librería USB de bajo nivel
- **libusb1**: Librería USB v1.0 (moderna)
- **odoo-pos-usb-printer-rules**: Paquete con reglas udev + script de diagnóstico

### 4. Script de diagnóstico (`check-printer-support.sh`)

Disponible como `check-printer-support` en el target. Verifica:

- Carga del módulo `usblp`
- Presencia de reglas udev
- Disponibilidad de librerías USB
- Estado del demonio CUPS
- Dispositivos USB conectados
- Nodos `/dev/usb/lp*`

## Uso en el target

Una vez que la imagen esté compilada y arrancada en el sistema:

```bash
# Ver estado del soporte de impresoras
check-printer-support

# Conectar una impresora térmica USB y verificar que se detecte
lsusb

# Debería aparecer el dispositivo, ej:
# Bus 003 Device 002: ID 0416:5011 Printer

# Verificar que se creó el nodo de dispositivo
ls -la /dev/usb/lp*

# Probar con CUPS
lpadmin -p usb-printer -E -v usb:///dev/usb/lp0 -m drv:///sample.drv/generic.ppd
lpstat -p
```

## Notas técnicas

- **Vendor ID 0x0416**: Zebra (impresoras térmicas estándar)
- **Clase 0x07, SubClase 0x01**: Estándar USB Printer class
- El driver `usblp` puede venir compilado como módulo o built-in
- Las reglas udev aseguran permisos correctos y detección automática
- CUPS es necesario para integración completa con Chromium kiosk printing

## Troubleshooting

Si la impresora no aparece:

1. Ejecutar `check-printer-support` para diagnóstico completo
2. Verificar que `usblp` esté cargado: `lsmod | grep usblp`
3. Revisar logs del kernel: `dmesg | tail`
4. Revisar logs de udev: `udevadm monitor --property` (conectar impresora)
5. Recargar reglas udev: `udevadm control --reload && udevadm trigger`

