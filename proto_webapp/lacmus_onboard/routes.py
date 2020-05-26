# routes.py
import pathlib

from . import views
from . import settings


PROJECT_ROOT = settings.PROJECT_ROOT


def setup_routes(app):
    app.router.add_get('/', views.index, name='index')
    app.router.add_get('/capture/', views.capture, name='capture')
    app.router.add_post('/capture/', views.do_capture, name='do_capture')
    app.router.add_post('/set_zoom/', views.set_zoom, name='set_zoom')
    setup_static_routes(app)


def setup_static_routes(app):
    app.router.add_static('/static/',
                          path=PROJECT_ROOT / 'static',
                          name='static')

    app.router.add_static('/captures/',
                      path=PROJECT_ROOT.parent / 'captures',
                      name='captures')
