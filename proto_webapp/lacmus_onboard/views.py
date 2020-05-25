# views.py
import aiohttp_jinja2
from aiohttp import web




@aiohttp_jinja2.template('index.html')
async def index(request):
    images = []
    return {'images': images}


@aiohttp_jinja2.template('capture.html')
async def capture(request):
    camera = request.app['camera']
    zoom = await camera.get_zoom()
    zoom = zoom.split(':')[-1]
    return {'zoom': zoom}


async def do_capture(request):
    data = await request.post()
    print("DATA", data)
    camera = request.app['camera']
    img_path = await camera.capture(data)
    router = request.app.router
    url = '/' + img_path
    return web.HTTPFound(location=url)


async def set_zoom(request):
    data = await request.post()
    camera = request.app['camera']
    await camera.set_zoom(data['zoom'])
    router = request.app.router
    url = router['capture'].url_for()
    return web.HTTPFound(location=url)
