import logging
import sys

import aiohttp_jinja2
import jinja2
from aiohttp import web

# from lacmus_onboard.db import close_pg, init_pg
from lacmus_onboard.middlewares import setup_middlewares
from lacmus_onboard.routes import setup_routes
from lacmus_onboard.settings import get_config
from lacmus_onboard.camera import camera_init, camera_close


async def init_app(argv=None):

    app = web.Application()

    app['config'] = get_config(argv)

    # setup Jinja2 template renderer
    aiohttp_jinja2.setup(
        app, loader=jinja2.PackageLoader('lacmus_onboard', 'templates'))

    # create db connection on startup, shutdown on exit
    app.on_startup.append(camera_init)
    app.on_cleanup.append(camera_close)

    # setup views and routes
    setup_routes(app)

    setup_middlewares(app)

    return app


def main(argv):
    logging.basicConfig(level=logging.DEBUG)

    app = init_app(argv)

    config = get_config(argv)
    web.run_app(app,
                host=config['host'],
                port=config['port'])


if __name__ == '__main__':
    main(sys.argv[1:])
