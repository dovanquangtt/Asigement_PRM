# Đăng nhập Gmail và đăng xuất trên Pixel

Ứng dụng dùng Google để xác thực danh tính và SQLite để kiểm tra tài khoản,
trạng thái hoạt động, vai trò và quyền. Không tự tạo tài khoản cho Gmail lạ.

## Chuẩn bị Google Cloud

1. Cấu hình OAuth consent screen; thêm Gmail thử nghiệm nếu dự án đang Testing.
2. Tạo OAuth client loại Android với package
   `com.example.quanlinhansunhahang` và SHA-1 đúng khóa ký của bản cài.
   Đọc SHA-1 debug bằng `cd android` rồi `./gradlew.bat signingReport`.
3. Trong cùng Google Cloud project, tạo OAuth client loại Web application.
   Dùng Client ID này làm `GOOGLE_WEB_CLIENT_ID`, không dùng client secret.
4. Admin vào Tài khoản, khai báo Gmail cho tài khoản đang hoạt động và có vai trò.
5. Chạy từ thư mục gốc:

```powershell
flutter run -d emulator-5554 --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

Thay ID thiết bị theo `flutter devices`. Nếu chạy bằng nút Run của IDE, cần truyền
cùng tham số `--dart-define` vào cấu hình chạy. Sau khi đổi tham số hãy dừng và chạy
lại hoàn toàn; hot reload không cập nhật cấu hình bản build.

Project đã có cấu hình VS Code `Flutter - Gmail` trong `.vscode/launch.json`
với Web Client ID được cung cấp. Chọn thiết bị Pixel ở thanh trạng thái, mở
Run and Debug, chọn `Flutter - Gmail` rồi nhấn F5. Cần hoàn tất Android OAuth
client với package/SHA-1 và thêm email thử nghiệm trên Google Cloud trước khi thử.

Tài liệu plugin chính thức:
https://pub.dev/packages/google_sign_in_android#integration

## Thử chức năng

- Ở màn hình đăng nhập, chọn **Đăng nhập bằng Gmail**, chọn Gmail đã được Admin cấp.
  Ứng dụng mở không gian đúng vai trò. Email được so sánh không phân biệt hoa thường.
- Hủy chọn tài khoản: hiển thị thông báo, có thể thử lại.
- Gmail lạ, tài khoản khóa, thiếu vai trò hoặc liên kết Google không khớp:
  từ chối đăng nhập và dọn phiên Google.
- Chọn biểu tượng **Đăng xuất** trên thanh trên cùng hoặc vào **Cá nhân → Đăng xuất**.
  Ứng dụng đăng xuất Google, về màn hình đăng nhập và xóa lịch sử điều hướng;
  nút Back không mở lại không gian phiên trước. Dữ liệu nghiệp vụ vẫn được giữ.

Nếu lỗi xuất hiện ngay sau chọn Gmail, kiểm tra Web Client ID, package Android,
SHA-1 và cấu hình consent screen. Google có thể trả mã hủy cho lỗi cấu hình Android.

## Kiểm thử tự động

```powershell
flutter test --no-pub test/google_auth_test.dart test/widget_test.dart
flutter analyze --no-pub
```

Kiểm thử dùng GoogleAuth giả lập và SQLite thật trong thư mục tạm. Đăng nhập Google
trực tiếp cần Client ID/SHA-1 thật, Internet và Google Play services trên máy Android.
Luồng nút Gmail hiện được cấu hình cho Android; các nền tảng khác có thông báo rõ ràng.
