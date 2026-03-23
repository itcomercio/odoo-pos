#!/usr/bin/env python3
import os
import shutil
import subprocess
import sys
import time
import dialog
import logging
import parted
import tarfile
from string import Template

MSG_ROOT           = "Comodoo Point of Sale Installer"
MSG_WELCOME        = "Comodoo POS installer, please press the OK button " \
                      "for continuing the installation process"
MSG_DISK_SET       = "Wait please The installer is preparing %s disk " \
                      "for installation"
MSG_PARTITION      = "Partitioning in progress ..."
MSG_PART_DONE      = "The disk was sucessfully formated"
MSG_BOOTPART_READY = "Boot partition. Ready to format the Boot partition"
MSG_FORMAT_BOOT    = "Making ext4 filesystem in boot partition ..."
MSG_FORMAT_OK      = "The disk was sucessfully formated"
MSG_FORMAT_ROOT    = "Making ext4 filesystem in root partition ..."
MSG_FORMAT_SWAP    = "Making swap filesystem ..."
MSG_LOADING_BSP    = "Loading Comodoo BSP, wait please ..."
MSG_BSP_OK         = "BSP transfered sucessfully"
MSG_GRUB            = "Wait please, Installing GRUB boot loader ..."
MSG_REBOOT         = "Congratulations the installation is complete \n\n" \
                      "Remove any installation media usaded during installation."

MIN_RAM = 64000

BSPFILE = "beetlepos-image-beetlepos.bsp"
CDROM_DEVICE = "/dev/sr0"
CDROM_MOUNT = "/mnt/cdrom"

MEGABYTE = 1024 * 1024
BOOTPARTITION = 1
INSTALLDEST = "/mnt/disk"

fstype2tool = {"ext4": ("mkfs.ext4", "-F", "-v"), "swap": ("mkswap", "-V1")}

def mkdir_p(path):
    os.makedirs(path, exist_ok=True)


def run_command(args, log, check=True, capture=False):
    log.info("Ejecutando comando: %s", " ".join(args))
    try:
        if capture:
            result = subprocess.run(
                args,
                check=check,
                capture_output=True,
                text=True,
                stdin=subprocess.DEVNULL,
            )
        else:
            with open('/tmp/installer.log', 'a', encoding='utf-8') as log_file:
                result = subprocess.run(
                    args,
                    check=check,
                    stdout=log_file,
                    stderr=log_file,
                    text=True,
                    stdin=subprocess.DEVNULL,
                )
    except FileNotFoundError:
        log.exception("Comando no encontrado: %s", args[0])
        raise
    except subprocess.CalledProcessError as error:
        if error.stdout:
            log.error("stdout (%s): %s", args[0], error.stdout.strip())
        if error.stderr:
            log.error("stderr (%s): %s", args[0], error.stderr.strip())
        raise

    if capture and result.stdout:
        log.debug("stdout (%s): %s", args[0], result.stdout.strip())
    if capture and result.stderr:
        log.warning("stderr (%s): %s", args[0], result.stderr.strip())
    return result

class DiskSet:
    """The disks in the system."""

    def __init__(self, log):
        self.deviceFile = None
        self.log = log

    def drive_list(self):
        self.deviceFile = "/dev/sda"
        self.log.info("detected possible disk: %s" % self.deviceFile)

        if not self.deviceFile:
            self.log.warning("no detected possible disks")

        return self.deviceFile

    def megabytes_to_sectors(self, mb, sector_bytes=512):
        return int(mb * 1024 * 1024 / sector_bytes)

    def convert_bytes(self, bytes):
        bytes = float(bytes)
        if bytes >= 1099511627776:
            terabytes = bytes / 1099511627776
            size = '%.2fT' % terabytes
        elif bytes >= 1073741824:
            gigabytes = bytes / 1073741824
            size = '%.2fG' % gigabytes
        elif bytes >= 1048576:
            megabytes = bytes / 1048576
            size = '%.2fM' % megabytes
        elif bytes >= 1024:
            kilobytes = bytes / 1024
            size = '%.2fK' % kilobytes
        else:
            size = '%.2fb' % bytes
        return size

    def create_partitions_v2(self):
        '''Up to now, the partition layout is fixed to conservative
        values. The current layout is:
        /dev/sda1    boot partition -> 100MB
        /dev/sda2    swap partition -> 1.5 size of RAM
        /dev/sda3    root partition -> remaining disk space
        '''
        target_device = parted.Device(path=self.deviceFile)

        # log diskinformation for debug
        (cylinders, heads, sectors) = target_device.biosGeometry
        sizeInBytes = target_device.length * target_device.sectorSize
        geometry_cad = "%d heads, %d sectors/track, %d cylinders\n" % (
        heads, sectors, cylinders,)
        size_cad = "Disk /dev/sdb size: %s\n" % (
        self.convert_bytes(sizeInBytes),)
        self.log.info(geometry_cad)
        self.log.info(size_cad)

        # Create Disk object
        target_disk = parted.freshDisk(target_device, "msdos")

        target_constraint = parted.Constraint(device=target_device)

        # Create geometry for 100MB from sector 1 - boot partition
        bootsize = self.megabytes_to_sectors(100)

        # Partitioning for BIOS with MBR:
        # Be sure to leave enough free space before the first partition.
        # Starting the first partition at sector 2048 leaves at least 1 MiB
        # of disk space for the master boot record. It is recommended
        # (but not mandatory) to create an additional partition for GRUB
        # called the BIOS boot partition. This partition just needs to be
        # defined, but not formatted. It is only needed if the system is
        # later migrated to the GPT partition layout. When sticking with MBR,
        # this is not needed.
        boot_partition_geom = parted.Geometry(device=target_device, start=2048,
                                              end=bootsize)
        filesystem_target = parted.FileSystem(type="ext4",
                                              geometry=boot_partition_geom)
        boot_partition = parted.Partition(disk=target_disk,
                                          fs=filesystem_target,
                                          type=parted.PARTITION_NORMAL,
                                          geometry=boot_partition_geom)

        # Create geometry for 500MB of swap partition
        swapsize = self.megabytes_to_sectors(500)

        swap_partition_geom = parted.Geometry(device=target_device,
                                              start=bootsize + 1,
                                              end=bootsize + swapsize)
        filesystem_target = parted.FileSystem(type="linux-swap(v1)",
                                              geometry=swap_partition_geom)
        swap_partition = parted.Partition(disk=target_disk,
                                          fs=filesystem_target,
                                          type=parted.PARTITION_NORMAL,
                                          geometry=swap_partition_geom)

        root_partition_geom = parted.Geometry(device=target_device,
                                              start=bootsize + swapsize + 1,
                                              end=target_device.length - 1)
        filesystem_target = parted.FileSystem(type="ext4",
                                              geometry=root_partition_geom)
        root_partition = parted.Partition(disk=target_disk,
                                          fs=filesystem_target,
                                          type=parted.PARTITION_NORMAL,
                                          geometry=root_partition_geom)

        # Delete all partitions in the drive
        target_disk.deleteAllPartitions()
        # Add new partitions
        target_disk.addPartition(partition=boot_partition,
                                 constraint=target_constraint)
        target_disk.addPartition(partition=swap_partition,
                                 constraint=target_constraint)
        target_disk.addPartition(partition=root_partition,
                                 constraint=target_constraint)
        # All the stuff we just did needs to be committed to the disk.
        target_disk.commit()

        return 0

    def format_disk(self, window, devicePath, formattool):
        # Simplified, since exec_with_pulse_progress is not defined
        cmd = [formattool[0], *formattool[1:], devicePath]
        run_command(cmd, self.log)

class BspImage:
    def __init__(self, filename, destdir, disk, log):
        self.bspfile = os.path.join(CDROM_MOUNT, "bsp", filename)
        self.outputdir = destdir
        self.total = 0
        self.list_of_names = []
        self.tar = None
        self.disk = disk
        self.log = log
        self.use_tar_zstd = False

    def _list_tar_zstd(self):
        result = run_command(["tar", "--zstd", "-tf", self.bspfile], self.log, capture=True)
        return [name for name in result.stdout.splitlines() if name]

    def load_bsp(self):
        if not os.path.isfile(self.bspfile):
            raise FileNotFoundError(f"BSP no encontrado: {self.bspfile}")

        try:
            self.tar = tarfile.open(self.bspfile, "r:*")
            self.list_of_names = self.tar.getnames()
            self.use_tar_zstd = False
        except tarfile.ReadError:
            # El BSP actual viene en Zstandard; usamos tar del sistema para listar/extractar.
            self.list_of_names = self._list_tar_zstd()
            self.use_tar_zstd = True

        self.total = len(self.list_of_names)

    def transfer_files(self, window):
        mkdir_p(INSTALLDEST)
        # FIXME: hard coded
        run_command(["mount", "-t", "ext4", self.disk + "3", INSTALLDEST], self.log)
        mkdir_p(INSTALLDEST + "/boot")
        # FIXME: hard coded
        run_command(["mount", "-t", "ext4", self.disk + "1", INSTALLDEST + "/boot"], self.log)

        if self.use_tar_zstd:
            run_command(["tar", "--zstd", "-xf", self.bspfile, "-C", self.outputdir], self.log)
            if window:
                window.gauge_update(100)
            else:
                print("Extraccion BSP completada")
            return

        for i, filename in enumerate(self.list_of_names):
            try:
                # Python 3.14 aplica filtro "data" por defecto y bloquea enlaces
                # absolutos. El BSP se considera confiable en este instalador.
                try:
                    self.tar.extract(
                        filename,
                        self.outputdir,
                        filter=tarfile.fully_trusted_filter,
                    )
                except TypeError:
                    # Compatibilidad con runtimes que no soportan el argumento filter.
                    self.tar.extract(filename, self.outputdir)
                if window:
                    window.gauge_update(int((i + 1) / self.total * 100))
                else:
                    print(f"Extrayendo: {filename}")
            except KeyError:
                print('ERROR: Did not find %s in tar archive', filename)

    def get_total_files(self):
        return self.total

class Installer:
    def __init__(self, log):
        self.log = log
        self.targetdisk = None
        # Mantener TERM para ncurses; no fijamos tamano para que dialog se adapte al terminal.
        os.environ['TERM'] = 'linux'
        self.is_serial = self.is_serial_console()
        if not self.is_serial:
            self.screen = dialog.Dialog(dialog="dialog")
            self.drawMainFrame()
        self.displayWellcome()
        self.prepareDisk()
        self.transferBSP()
        self.installGRUB()
        self.finalSteps()

    def is_serial_console(self):
        try:
            with open('/proc/cmdline', 'r') as f:
                cmdline = f.read()
                return 'console=ttyS0' in cmdline
        except:
            return False

    def displayWellcome(self):
        if self.is_serial:
            print(MSG_WELCOME)
            input("Presiona Enter para continuar")
        else:
            self.screen.msgbox(MSG_WELCOME, None, None)

    def drawMainFrame(self):
        '''
        Just the title of main window
        '''
        self.screen.set_background_title(MSG_ROOT)

    def serial_pause(self, msg, seconds):
        print(msg)
        time.sleep(seconds)

    def serial_gauge_start(self, msg):
        print(f"{msg} - Iniciando...")

    def serial_gauge_update(self, percent, text=None):
        print(f"Progreso: {percent}% {text or ''}")

    def serial_gauge_stop(self):
        print("Completado.")

    def prepareDisk(self):
        #
        # Main Device disk detection
        #
        ds = DiskSet(self.log)
        self.targetdisk = ds.drive_list()

        if self.is_serial:
            self.serial_pause(MSG_DISK_SET % self.targetdisk, 2)
        else:
            self.screen.pause(MSG_DISK_SET % self.targetdisk, None, None, 2)
        #
        # Main device disk partitioning
        #
        if not False:
            ds.create_partitions_v2()

        if self.is_serial:
            self.serial_gauge_start(MSG_PARTITION)
            self.serial_gauge_update(10)
            time.sleep(3)
            self.serial_gauge_update(50)
            time.sleep(3)
            self.serial_gauge_update(100, MSG_PART_DONE)
            self.serial_gauge_stop()
        else:
            self.screen.gauge_start(MSG_PARTITION, None, None, 1)
            self.screen.gauge_update(10)
            time.sleep(3)
            self.screen.gauge_update(50)
            time.sleep(3)
            self.screen.gauge_update(100, MSG_PART_DONE)
            self.screen.gauge_stop()

        # Format
        if self.is_serial:
            self.serial_pause(MSG_BOOTPART_READY, 2)
            self.serial_gauge_start(MSG_FORMAT_BOOT)
        else:
            self.screen.pause(MSG_BOOTPART_READY, None, None, 2)
            self.screen.gauge_start(MSG_FORMAT_BOOT, None, None, 1)

        if not False:
            ds.format_disk(None, self.targetdisk + "1", fstype2tool["ext4"])
        else:
            time.sleep(3)

        if self.is_serial:
            self.serial_gauge_update(90)
            time.sleep(3)
            self.serial_gauge_update(100, MSG_FORMAT_OK)
            time.sleep(2)
            self.serial_gauge_stop()
        else:
            self.screen.gauge_update(90)
            time.sleep(3)
            self.screen.gauge_update(100, MSG_FORMAT_OK)
            time.sleep(2)
            self.screen.gauge_stop()

        if self.is_serial:
            self.serial_gauge_start(MSG_FORMAT_ROOT)
        else:
            self.screen.gauge_start(MSG_FORMAT_ROOT, None, None, 1)

        if self.is_serial:
            self.serial_gauge_update(10)
        else:
            self.screen.gauge_update(10)

        if not False:
            ds.format_disk(None, self.targetdisk + "3", fstype2tool["ext4"])
        else:
            time.sleep(3)

        if self.is_serial:
            self.serial_gauge_update(90)
            time.sleep(3)
            self.serial_gauge_update(100, MSG_FORMAT_OK)
            time.sleep(2)
            self.serial_gauge_stop()
        else:
            self.screen.gauge_update(90)
            time.sleep(3)
            self.screen.gauge_update(100, MSG_FORMAT_OK)
            time.sleep(2)
            self.screen.gauge_stop()

        if self.is_serial:
            self.serial_gauge_start(MSG_FORMAT_SWAP)
            self.serial_gauge_update(10)
        else:
            self.screen.gauge_start(MSG_FORMAT_SWAP, None, None, 1)
            self.screen.gauge_update(10)

        if not False:
            ds.format_disk(None, self.targetdisk + "2", fstype2tool["swap"])
        else:
            time.sleep(3)

        if self.is_serial:
            self.serial_gauge_update(90)
            time.sleep(3)
            self.serial_gauge_update(100, MSG_FORMAT_OK)
            time.sleep(2)
            self.serial_gauge_stop()
        else:
            self.screen.gauge_update(90)
            time.sleep(3)
            self.screen.gauge_update(100, MSG_FORMAT_OK)
            time.sleep(2)
            self.screen.gauge_stop()

        return 0

    def transferBSP(self):
        if self.is_serial:
            self.serial_gauge_start(MSG_LOADING_BSP)
        else:
            self.screen.gauge_start(MSG_LOADING_BSP, None, None, 1)

        if self.is_serial:
            self.serial_gauge_update(10)
        else:
            self.screen.gauge_update(10)

        mkdir_p(CDROM_MOUNT)

        if not os.path.ismount(CDROM_MOUNT):
            try:
                run_command(["mount", "-t", "iso9660", CDROM_DEVICE, CDROM_MOUNT], self.log)
            except subprocess.CalledProcessError as error:
                raise RuntimeError(
                    f"No se pudo montar el CDROM {CDROM_DEVICE} en {CDROM_MOUNT}"
                ) from error

        bsp_dir = os.path.join(CDROM_MOUNT, "bsp")
        if not os.path.isdir(bsp_dir):
            raise FileNotFoundError(
                f"No existe el directorio BSP esperado en el CDROM: {bsp_dir}"
            )

        tb = BspImage(BSPFILE, INSTALLDEST, self.targetdisk, self.log)
        tb.load_bsp()
        total = tb.get_total_files()

        if self.is_serial:
            self.serial_gauge_update(10)
        else:
            self.screen.gauge_update(10)

        tb.transfer_files(self.screen if not self.is_serial else None)

        if self.is_serial:
            self.serial_gauge_update(90)
            time.sleep(2)
            self.serial_gauge_update(100, MSG_BSP_OK)
            time.sleep(2)
            self.serial_gauge_stop()
        else:
            self.screen.gauge_update(90)
            time.sleep(2)
            self.screen.gauge_update(100, MSG_BSP_OK)
            time.sleep(2)
            self.screen.gauge_stop()

        return 0

    def installGRUB(self):
        if self.is_serial:
            self.serial_gauge_start(MSG_GRUB)
        else:
            self.screen.gauge_start(MSG_GRUB, None, None, 1)

        time.sleep(2)

        if self.is_serial:
            self.serial_gauge_update(10)
        else:
            self.screen.gauge_update(10)

        grub_cfg_template = """set default=0
        set timeout=5

        set root=(hd0,msdos1)

        menuentry "$menuentry" {
                linux /bzImage root=$dev ro
        }"""

        src = Template(grub_cfg_template)

        menuentry = "Comodoo Point of Sale Operating System"
        root = self.targetdisk + "3"

        d = {'menuentry': menuentry, 'dev': root}

        grubconf = src.substitute(d)

        mkdir_p(INSTALLDEST + "/boot/grub2/")
        grub_file = INSTALLDEST + "/boot/grub2/grub.cfg"

        with open(grub_file, 'w') as f:
            f.write(grubconf)

        grub_install = shutil.which("grub2-install") or "/usr/sbin/grub2-install"
        grub_probe = shutil.which("grub2-probe") or "/usr/sbin/grub2-probe"
        grub_modinfo = "/usr/lib/grub/i386-pc/modinfo.sh"
        grub_directory = os.path.dirname(grub_modinfo)

        missing_bins = []
        for binary in (grub_install, grub_probe):
            if not (os.path.isfile(binary) and os.access(binary, os.X_OK)):
                missing_bins.append(binary)

        if missing_bins:
            msg = (
                "Faltan utilidades de GRUB en initrd: "
                + ", ".join(missing_bins)
                + ". Revisa dra.sh para incluir grub2-tools y dependencias."
            )
            self.log.error(msg)
            raise FileNotFoundError(msg)

        if not os.path.isfile(grub_modinfo):
            msg = (
                "Falta runtime de GRUB BIOS en initrd: "
                f"{grub_modinfo}. "
                "Incluye /usr/lib/grub/i386-pc en dra.sh."
            )
            self.log.error(msg)
            raise FileNotFoundError(msg)

        # grub-install here.
        args = [grub_install,
                "--target=i386-pc",
                f"--directory={grub_directory}",
                f'--boot-directory={INSTALLDEST}/boot/',
                self.targetdisk]

        self.log.info("Ejecutando grub2-install sobre: %s", self.targetdisk)
        try:
            result = run_command(args, self.log, capture=True)
            if result.stdout:
                self.log.info("grub2-install stdout: %s", result.stdout.strip())
            if result.stderr:
                self.log.warning("grub2-install stderr: %s", result.stderr.strip())
        except FileNotFoundError as error:
            self.log.exception("No se encontro grub2-install en el entorno initrd")
            raise RuntimeError("No se encontro grub2-install en initrd") from error
        except subprocess.CalledProcessError as error:
            self.log.error("grub2-install fallo con codigo %s", error.returncode)
            if error.stdout:
                self.log.error("grub2-install stdout: %s", error.stdout.strip())
            if error.stderr:
                self.log.error("grub2-install stderr: %s", error.stderr.strip())
            raise RuntimeError("Fallo al instalar GRUB, revisa /tmp/installer.log") from error
        except Exception:
            self.log.exception("Error inesperado durante installGRUB")
            raise

        if self.is_serial:
            self.serial_gauge_update(50)
            time.sleep(2)
            self.serial_gauge_stop()
        else:
            self.screen.gauge_update(50)
            time.sleep(2)
            self.screen.gauge_stop()

    def finalSteps(self):
        if self.is_serial:
            print(MSG_REBOOT)
        else:
            self.screen.msgbox(MSG_REBOOT, None, None)


def main():

    logging.basicConfig(filename='/tmp/installer.log', level=logging.DEBUG)
    log = logging.getLogger("comodoo")

    log.info("Installer running, good luck!")

    Installer(log)

    return 0

if __name__ == "__main__":
    sys.exit(main())
