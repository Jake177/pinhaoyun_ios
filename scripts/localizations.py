#!/usr/bin/env python3
import json
from pathlib import Path
strings={
'Library':'图库','Transfers':'传输','Account':'我的','Photo':'照片','Video':'视频','Photos':'照片','Videos':'视频',
'Sign in':'登录','Sign out':'退出登录','Email':'邮箱','Password':'密码','New password':'新密码','Current password':'当前密码',
'Create an account':'注册账号','Create account':'注册','Forgot password?':'忘记密码？','Back to sign in':'返回登录',
'Nickname':'昵称','Given name':'名字','Family name':'姓氏','Gender':'性别','Prefer not to say / Other':'不愿透露／其他','Female':'女','Male':'男',
'Verification code':'验证码','Verify your email':'验证邮箱','Verify email':'验证邮箱','Send a new code':'重新发送验证码',
'Reset password':'重设密码','Set a new password':'设置新密码','Send reset code':'发送重设验证码','Save new password':'保存新密码',
'Your photos and videos, together.':'把照片与视频，收藏在一起。',
'Use at least 8 characters with uppercase, lowercase, a number and a symbol.':'密码至少 8 位，包含大写字母、小写字母、数字和符号。',
'I agree to the terms and have read the privacy notice.':'我同意服务条款，并已阅读隐私说明。',
'Terms of use':'服务条款','Privacy notice':'隐私说明','Done':'完成','Try again':'重试',
'Load terms and privacy notice':'加载服务条款和隐私说明',
'Invited beta · Keep an independent copy of important originals.':'受邀测试版 · 请为重要原件保留独立备份。',
'Enter the code sent to your email.':'请输入发送到你邮箱的验证码。','Email verified. You can now sign in.':'邮箱验证成功，现在可以登录。',
'Password updated. Sign in with your new password.':'密码已更新，请使用新密码登录。','A new code has been sent.':'新验证码已发送。',
'Before you continue':'继续之前','Please review the current terms and privacy notice for your PinHaoYun account.':'请阅读适用于你的 PinHaoYun 账号的最新服务条款与隐私说明。',
'Agree and continue':'同意并继续','Your account':'你的账号',
'Your library starts here':'从这里开始收藏','Add photos, videos and Live Photos. Your originals stay on your device.':'添加照片、视频和实况照片。手机里的原件会保留。',
'Add photos and videos':'添加照片和视频','Filter library':'筛选图库','Media type':'媒体类型','All media':'全部媒体','Load more':'加载更多','Date unknown':'日期未知',
'Open Live Photo':'查看实况照片','Open media':'查看媒体','No transfers yet':'还没有传输任务',
'Add photos and videos from your library. Uploads and retries appear here.':'从图库添加照片和视频，在这里查看上传进度与重试。',
'Uploading':'上传中','Finishing':'即将完成','Completed':'已完成','Needs attention':'需要处理','Cancelled':'已取消','Waiting':'等待中',
'Retry':'重试','Cancel upload':'取消上传','Upload progress':'上传进度',
'Background transfers resume when iOS allows. Reopen the app after force quitting.':'后台传输会在 iOS 允许时继续；强制关闭 App 后，请重新打开以恢复。',
'Loading original':'正在加载原件','Unable to load media':'暂时无法加载','Try refreshing this item.':'请刷新此项目后重试。','Refresh access':'刷新访问链接',
'Save original to Photos':'保存原件到相册','Save to Files or share':'存储到文件或分享','Media details':'媒体详情',
'Delete cloud copy':'删除云端副本','Delete this cloud copy?':'删除这个云端副本？',
'This removes the cloud original and thumbnail. Photos on your device are kept.':'此操作将删除云端原件和缩略图，手机相册不受影响。',
'Live Photo. Touch and hold to play.':'实况照片，长按播放。',
'Allow Photos access in Settings, or use Save to Files.':'请在系统设置中允许相册访问，或选择“存储到文件”。','Original saved to Photos.':'原件已保存到相册。',
'File name':'文件名','Date':'日期','Size':'大小','Resolution':'分辨率','Device':'拍摄设备','Location':'位置',
'Storage':'存储空间','Storage used':'已用存储空间','Plan':'当前方案','Privacy and account':'隐私与账号',
'Delete account':'注销账号','Delete your PinHaoYun account?':'注销你的 PinHaoYun 账号？',
'This deletes the account shared by Web and iOS. Access stops immediately and cloud photos, videos and account data will be deleted within 30 days.':'注销作用于 Web 与 iOS 共用账号。访问会立即停止，云端照片、视频和账号资料将在 30 天内删除。',
'Photos on your device are kept. Download any cloud originals you need before continuing.':'手机相册会保留。继续之前，请先下载你需要的云端原件。',
'Confirm your identity':'验证身份','Delete account and cloud data':'注销账号并删除云端资料','Permanently delete your account?':'永久注销账号？',
'Confirm account deletion':'确认注销账号','There is no recovery promise after deletion begins.':'删除开始后，不提供恢复承诺。',
'Account deleted':'账号已删除','Account deletion requested':'已提交注销申请','Account deletion':'账号注销',
'Cloud data will be deleted within 30 days. Photos on your device are kept.':'云端资料将在 30 天内删除，手机相册不受影响。',
'Delete by':'最迟删除时间','Check deletion status':'查看注销进度','Return to sign in':'返回登录',
'Each original must be smaller than 2 GB.':'每个原始文件不得超过 2 GB。','This original format is not supported yet.':'暂不支持这种原始文件格式。',
'The local original is unavailable. Add this item again.':'本地原件暂时不可用，请重新添加此项目。',
'Connection interrupted. Check your connection, then retry.':'连接已中断，请检查网络后重试。',
'Secure storage is unavailable. Unlock your device and try again.':'安全存储暂时不可用，请解锁设备后重试。',
'Verify your email before signing in.':'请先验证邮箱再登录。',
'Your email or password is incorrect, or your session has expired.':'邮箱或密码不正确，或登录状态已过期。',
'The code is incorrect or has expired. Request a new one.':'验证码不正确或已过期，请重新获取。',
'This email already has an account. Sign in instead.':'这个邮箱已经注册，请直接登录。',
'The service is temporarily unavailable. Please try again later.':'服务暂时无法连接，请稍后重试。','Please sign in again.':'请重新登录。',
'The request failed. Please try again.':'操作未完成，请重试。',
'Loading your account':'正在加载账号',
'Waiting for network':'等待网络',
'Checking deletion request':'正在确认注销申请',
'%@ of %@ used':'已用 %@，共 %@',
'Free':'免费版',
'PinHaoYun · Beta 0.1\nYour device\'s Photos library is never removed by account deletion.':'PinHaoYun · 测试版 0.1\n注销账号不会删除手机相册。'
}
output={'sourceLanguage':'en','strings':{en:{'localizations':{'zh-Hans':{'stringUnit':{'state':'translated','value':zh}}}} for en,zh in strings.items()},'version':'1.0'}
root=Path(__file__).resolve().parents[1]
(root/'App/Resources/Localizable.xcstrings').write_text(json.dumps(output,ensure_ascii=False,indent=2)+'\n')
for lang,photo,add in [('en','Choose originals and Live Photos to upload to your private PinHaoYun library.','Save your cloud originals and Live Photos to your device\'s Photos library.'),('zh-Hans','选择照片、视频和实况照片原件，上传到你的私人 PinHaoYun 图库。','将云端照片、视频和实况照片原件保存到手机相册。')]:
 folder=root/f'App/Resources/{lang}.lproj';folder.mkdir(parents=True,exist_ok=True)
 (folder/'InfoPlist.strings').write_text('"NSPhotoLibraryUsageDescription" = '+json.dumps(photo,ensure_ascii=False)+';\n"NSPhotoLibraryAddUsageDescription" = '+json.dumps(add,ensure_ascii=False)+';\n')
print(f'Wrote {len(strings)} Simplified Chinese translations.')
