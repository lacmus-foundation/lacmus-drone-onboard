import asyncio
import datetime
import logging
import math
import struct

# from pymavlink.dialects.v20 import common as mavlink2
from .mavlink.dialects import lacmus as mavlink2

logger = logging.getLogger(__name__)


MAV_SYS_ID = b'MAV_SYS_ID'
ID_OM = b'ID_OM'



class MAVLinkServerProtocol:

    def __init__(self, parser, msgs_queue):
        self.msgs_queue = msgs_queue
        self.remote_addr = None
        self.parser = parser

    def connection_made(self, transport):
        self.transport = transport

    def connection_lost(self, exc):
        logger.info('Connection lost: %s', exc)

    def datagram_received(self, data, addr):
        if addr != self.remote_addr:
            logger.info("New remote address: %s", addr)
            self.remote_addr = addr
        try:
            all_msgs = self.parser.parse_buffer(data) or []
        except Exception as e:
            logger.warning("MAVLink Parser error: %s", e)
        else:
            for msg in all_msgs:

                self.msgs_queue.put_nowait(msg)

    def error_received(self, exc):
        logger.error('Error received: %s', exc)


class TransportFile:
    def __init__(self, transport, proto):
        self.transport = transport
        self.proto = proto

    def write(self, data):
        if self.proto.remote_addr:
            self.transport.sendto(data, self.proto.remote_addr)


class LoggerStatus:
    WAIT_DATA = 'WAIT_DATA'
    DATA_RECEIVED = 'DATA_RECEIVED'
    DATA_LINK_LOST = 'DATA_LINK_LOST'


class MAVLinkService:

    MESSAGE_IDS = (
        mavlink2.MAVLINK_MSG_ID_HEARTBEAT,
        mavlink2.MAVLINK_MSG_ID_CAMERA_IMAGE_CAPTURED,
        mavlink2.MAV_CMD_REQUEST_CAMERA_SETTINGS,
        mavlink2.MAVLINK_MSG_ID_CAMERA_TRIGGER,
        mavlink2.MAVLINK_MSG_ID_CAMERA_CAPTURE_STATUS,
        mavlink2.MAV_CMD_IMAGE_START_CAPTURE,
        mavlink2.MAV_CMD_IMAGE_STOP_CAPTURE,
        mavlink2.MAV_CMD_DO_DIGICAM_CONTROL,
    )

    def __init__(self, system_id, component_id, udp_endpoint):
        # TODO: implement DATA_LINK_LOST status on timeouts
        self.loop = asyncio.get_event_loop()
        self.udp_endpoint = udp_endpoint
        self.system_id = system_id
        self.component_id = component_id
        self.running = False
        self.tasks = []
        self.queue = asyncio.Queue()
        self.mav = mavlink2.MAVLink(None, srcSystem=system_id, srcComponent=component_id)
        self.transport = None
        self.status = None
        self.local_timestamp = None

    def __str__(self):
        return "MAVLinkService({},{})".format(self.system_id, self.component_id)

    async def start(self):
        logger.info("Starting %s, udp_endpoint: %s, system_id: %s",
                    self, self.udp_endpoint, self.system_id)
        self.running = True
        transport, protocol = await self.loop.create_datagram_endpoint(
            lambda: MAVLinkServerProtocol(self.mav, self.queue),
            local_addr=self.udp_endpoint,
        )
        self.transport = transport
        self.mav.file = TransportFile(transport, protocol)
        consume_task = self.loop.create_task(self.consume())
        heartbeat_task = self.loop.create_task(self.heartbeat())
        self.tasks.append(consume_task)
        self.tasks.append(heartbeat_task)
        self.status = LoggerStatus.WAIT_DATA
        logger.info("Started %s", self)

    async def stop(self):
        logger.info("Stopping %s", self)
        self.running = False
        for task in self.tasks:
            task.cancel()
        await asyncio.wait(self.tasks)
        self.transport.close()
        logger.info("Stopped %s", self)

    async def process_message(self, msg):
        mid = msg.get_msgId()
        if mid in self.MESSAGE_IDS:
            print(msg.get_srcSystem(), msg.get_srcComponent(), msg.to_dict())
        if mid == mavlink2.MAVLINK_MSG_ID_CAMERA_TRIGGER:
            capture = {
                "time_boot_ms": 100,                  # : Timestamp (time since system boot). [ms] (type:uint32_t)
                "time_utc": 1234,                     # : Timestamp (time since UNIX epoch) in UTC. 0 for unknown. [us] (type:uint64_t)
                "camera_id": 1,                       # : Camera ID (1 for first, 2 for second, etc.) (type:uint8_t)
                "lat": 1231233,                       # : Latitude where image was taken [degE7] (type:int32_t)
                "lon": 3321312,                       # : Longitude where capture was taken [degE7] (type:int32_t)
                "alt": 12,                            # : Altitude (MSL) where image was taken [mm] (type:int32_t)
                "relative_alt": 22,                   # : Altitude above ground [mm] (type:int32_t)
                "q": (0, 0, 0, 0),                    # : Quaternion of camera orientation (w, x, y, z order, zero-rotation is 0, 0, 0, 0) (type:float)
                "image_index": 7,                     # : Zero based index of this image (image count since armed -1) (type:int32_t)
                "capture_result": True,               # : Boolean indicating success (1) or failure (0) while capturing this image. (type:int8_t)
                "file_url": b'/captures/image_7.jpg',  # : URL of image taken. Either local storage or http://foo.jpg if camera provides an HTTP interface. (type:char)
            }
            self.mav.camera_image_captured_send(**capture)

            detection = {
                "time_boot_ms": 100,                  # : Timestamp (time since system boot). [ms] (type:uint32_t)
                "time_utc": 1234,                     # : Timestamp (time since UNIX epoch) in UTC. 0 for unknown. [us] (type:uint64_t)
                "camera_id": 1,                       # : Camera ID (1 for first, 2 for second, etc.) (type:uint8_t)
                "lat": 1231233,                       # : Latitude where image was taken [degE7] (type:int32_t)
                "lon": 3321312,                       # : Longitude where capture was taken [degE7] (type:int32_t)
                "alt": 12,                            # : Altitude (MSL) where image was taken [mm] (type:int32_t)
                "relative_alt": 22,                   # : Altitude above ground [mm] (type:int32_t)
                "bbox": (12, 12, 200, 200),                 # : Bound box of detected object (type:uint16_t)
                "source_image_index": 7,                     # : Zero based index of this image (image count since armed -1) (type:int32_t)
                "file_url": b'/detections/7/image_7.jpg',  # : URL of image taken. Either local storage or http://foo.jpg if camera provides an HTTP interface. (type:char)
            }
            self.mav.lacmus_object_detected_send(**detection)

    async def consume(self):
        logger.info('Start consume task for %s', self)
        while self.running:
            try:
                msg = await self.queue.get()
                logger.debug('Consuming message queue %s', msg.get_msgId())
                await self.process_message(msg)

            except Exception as e:
                logger.exception("Error: %s", e)
        logger.info('Exit from consume task for %s', self)

    async def heartbeat(self):
        logger.info('Start heartbeat task for %s', self)
        while self.running:
            self.mav.heartbeat_send(mavlink2.MAV_TYPE_ONBOARD_CONTROLLER,
                                    mavlink2.MAV_AUTOPILOT_INVALID, 0, 0, mavlink2.MAV_STATE_ACTIVE)
            await asyncio.sleep(1)
        logger.info('Exit from heartbeat task for %s', self)


if __name__ == '__main__':
    async def main():
        # mav_logger = MAVLogger(1, 100, ('127.0.0.1', 14550))
        mav_logger = MAVLogger(1, 100, ('127.0.0.1', 5555))
        await mav_logger.start()
        await asyncio.sleep(30)
    #iloop = asyncio.get_event_loop()
    asyncio.run(main())

