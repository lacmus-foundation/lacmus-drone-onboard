
import asyncio
from asyncio import subprocess
import time
import os.path
import logging

from . import settings

logger = logging.getLogger(__name__)


CHDKPTP_ROOT = settings.CHDKPTP_BASE_PATH
SHOOT_SCRIPT_PATH = os.path.join(CHDKPTP_ROOT, 'shoot.lua')


class Camera:
    """
    Camera control for Canon S100/S110 using CHDK and chdkptp
    """

    def __init__(self):
        self.proc = None
        self.counter = 0

    async def send_command(self, cmd, single_read=True, fin=False):
        self.proc.stdin.write(cmd.encode() + b'\n')
        await self.proc.stdin.drain()
        ret = await self.proc.stdout.readline()
        if single_read is False:
            logger.info("Cmd: %s, ret x:%s", cmd, ret)
            ret = await self.proc.stdout.readline()
        if fin:
            await self.proc.stdout.readline()
        logger.info("Cmd: %s, ret:%s", cmd, ret)
        return ret

    async def init(self):
        proc_cmd = '{}/chdkptp.sh -i'.format(CHDKPTP_ROOT)
        logger.info("Starting chkptp subprocess: %s", proc_cmd)
        self.proc = await asyncio.create_subprocess_shell(
            proc_cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE)
        logger.info("Chkptp subprocess started with pid: %s", self.proc.pid)
        await self.send_command("set usb_reset_on_close=true")
        await self.send_command("connect", single_read=False)
        await asyncio.sleep(1)
        await self.send_command("rec")  # TODO: move to separate call - rec/display mode switch 
        await asyncio.sleep(1)
        logger.info("Camera init done")

    async def close(self):
        self.proc.terminate()

    async def capture(self, params):
        fname = self.make_fname(self.counter)

        focus_distance = params.get('focus_distance')
        if params.get('focus_mode') == 'MF':
            ret = await self.send_command('=set_mf(1)')
            await asyncio.sleep(0.1)
            if focus_distance:
                ret = await self.send_command('=set_focus({})'.format(focus_distance))
                await asyncio.sleep(0.1)
        else:
            ret = await self.send_command('=set_mf(0)')

        cmd_params = "-script={}".format(SHOOT_SCRIPT_PATH)

        cmd = 'rs {} {}\n'.format(fname, cmd_params)
        ret = await self.send_command(cmd, single_read=False, fin=True)

        wfname = fname + '.jpg'
        while not os.path.exists(wfname):
            await asyncio.sleep(0.1)  # TODO:  add wait timeout
        self.counter += 1
        return wfname

    async def set_zoom(self, value):
        await self.send_command('=set_zoom({})'.format(value))

    async def get_zoom(self):
        zoom = await self.send_command('=return get_zoom()', single_read=False)
        return zoom.decode()

    def make_fname(self, n):
        fname = 'captures/img_{}'.format(n)
        return fname


async def camera_init(app):
    camera = Camera()
    await camera.init()
    app['camera'] = camera


async def camera_close(app):
    await app['camera'].close()