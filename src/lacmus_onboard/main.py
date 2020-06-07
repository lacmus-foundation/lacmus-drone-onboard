import argparse
import asyncio
import logging

from .mavlink_service import MAVLinkService

parser = argparse.ArgumentParser(description='Start lacmus onboard service.')

parser.add_argument('--port', type=int, required=True, help='MAVLink UDP port for inbound connection')
parser.add_argument('--log-level', help='Log level', default='INFO')



def run():
    args = parser.parse_args()
    logging.basicConfig(level=args.log_level.upper(), format="%(asctime)s %(levelname)-8s %(name)s: %(message)s")

    async def main():
        # mav_logger = MAVLogger(1, 100, ('127.0.0.1', 14550))
        mav_logger = MAVLinkService(1, 100, ('127.0.0.1', args.port))
        await mav_logger.start()
        while True:
            await asyncio.sleep(5)

    asyncio.run(main())


if __name__ == '__main__':
    run()
