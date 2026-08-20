# iOS 앱 아이콘은 알파 채널이 있으면 App Store 업로드가 거부된다.
# gen_app_icons_test.dart 실행 후 이 스크립트로 iOS 아이콘만 RGB로 평탄화한다.
import glob
from PIL import Image

for p in glob.glob('ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png'):
    im = Image.open(p)
    if im.mode != 'RGB':
        Image.merge('RGB', im.convert('RGBA').split()[:3]).save(p)
        print('flattened', p)
