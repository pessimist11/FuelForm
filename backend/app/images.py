from io import BytesIO
import warnings
from PIL import Image, ImageOps, UnidentifiedImageError
from pillow_heif import register_heif_opener
from .providers import ProviderError
register_heif_opener()
Image.MAX_IMAGE_PIXELS = 24_000_000

def normalize_image(data: bytes) -> bytes:
    try:
        with warnings.catch_warnings():
            warnings.simplefilter('error', Image.DecompressionBombWarning)
            with Image.open(BytesIO(data)) as image:
                if image.format not in ('JPEG', 'PNG', 'HEIF', 'HEIC', 'WEBP'):
                    raise ValueError('unsupported format')
                if image.width < 32 or image.height < 32 or image.width * image.height > 24_000_000:
                    raise ValueError('invalid dimensions')
                image.load()  # Verify actual decode, not just filename or MIME
                image = ImageOps.exif_transpose(image)
                image.thumbnail((1600, 1600))
                if image.mode in ('RGBA', 'LA'):
                    background = Image.new('RGB', image.size, 'white')
                    background.paste(image, mask=image.getchannel('A')); image = background
                else:
                    image = image.convert('RGB')
                output = BytesIO(); image.save(output, 'JPEG', quality=85)  # Strips EXIF, incl GPS
                return output.getvalue()
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError, Image.DecompressionBombWarning):
        raise ProviderError('invalid_image', '图片无法解码、格式不支持或尺寸不合理；请使用 JPEG、PNG、HEIC 或 WebP', 422) from None
