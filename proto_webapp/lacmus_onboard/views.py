# views.py
import aiohttp_jinja2
from aiohttp import web
import glob
import exif
import fractions

from . import settings


"""
In [7]: image.f_number                                                                                                                                                                                                                 
Out[7]: 8.0

In [8]: image.focal_length                                                                                                                                                                                                             
Out[8]: 16.0

In [9]: image.focal_length_in_35mm_film                                                                                                                                                                                                
Out[9]: 24

In [10]: image.photographic_sensitivity                                                                                                                                                                                                
Out[10]: 800

In [11]: image.exposure_time                                                                                                                                                                                                           
Out[11]: 0.001


['_exif_ifd_pointer', '_gps_ifd_pointer', '_interoperability_ifd_Pointer', '_segments', 'aperture_value', 'artist',
'camera_owner_name', 'color_space', 'components_configuration', 'compressed_bits_per_pixel', 'compression', 'copyright',
'custom_rendered', 'datetime', 'datetime_digitized', 'datetime_original', 'digital_zoom_ratio', 'exif_version',
'exposure_bias_value', 'exposure_mode', 'exposure_time', 'f_number', 'file_source', 'flash', 'flashpix_version',
'focal_length', 'focal_plane_resolution_unit', 'focal_plane_x_resolution', 'focal_plane_y_resolution', 'get',
'get_file', 'gps_version_id', 'has_exif', 'image_description', 'jpeg_interchange_format', 'jpeg_interchange_format_length',
'make', 'maker_note', 'max_aperture_value', 'metering_mode', 'model', 'orientation', 'photographic_sensitivity',
'pixel_x_dimension', 'pixel_y_dimension', 'resolution_unit', 'scene_capture_type', 'sensing_method', 'sensitivity_type',
'shutter_speed_value', 'user_comment', 'white_balance', 'x_resolution', 'y_and_c_positioning', 'y_resolution']


"""

CROP_1_7 = 4.5


@aiohttp_jinja2.template('index.html')
async def index(request):
    search_path = settings.BASE_DIR / 'captures'
    images = []
    for img_path in search_path.glob('*.jpg'):
        im_data = {
            "url" : '/' + '/'.join(img_path.parts[-2:])
        }
        with open(img_path, 'rb') as f:
            exif_img = exif.Image(f)
            im_data['f_number'] = exif_img.f_number
            im_data['focal_length'] = exif_img.focal_length
            im_data['focal_length_35'] = exif_img.focal_length * CROP_1_7
            im_data['iso'] = exif_img.photographic_sensitivity
            im_data['tv'] = fractions.Fraction(exif_img.exposure_time).limit_denominator()
        images.append(im_data)
    return {'images': images}


@aiohttp_jinja2.template('capture.html')
async def capture(request):
    camera = request.app['camera']
    zoom = await camera.get_zoom()
    zoom = zoom.split(':')[-1]
    return {'zoom': zoom}


async def do_capture(request):
    data = await request.post()
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
