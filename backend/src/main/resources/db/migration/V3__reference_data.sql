INSERT INTO roles (code, name) VALUES
    ('admin', 'Quản trị viên'), ('manager', 'Quản lý'), ('employee', 'Nhân viên');
INSERT INTO departments (code, name) VALUES ('KITCHEN', 'Bếp'), ('SERVICE', 'Phục vụ'), ('CASHIER', 'Thu ngân');
INSERT INTO positions (code, name) VALUES
    ('MANAGER', 'Quản lý nhà hàng'), ('CHEF', 'Đầu bếp'), ('WAITER', 'Nhân viên phục vụ'), ('CASHIER', 'Thu ngân');
INSERT INTO leave_types (code, name, is_paid) VALUES
    ('ANNUAL', 'Nghỉ phép năm', TRUE), ('UNPAID', 'Nghỉ không lương', FALSE), ('SICK', 'Nghỉ ốm', FALSE);
INSERT INTO permissions (code, description) VALUES
    ('users.manage', 'Quản lý tài khoản và phân quyền'),
    ('reports.view', 'Xem báo cáo nhân sự và dashboard'),
    ('employees.manage', 'Quản lý hồ sơ, bộ phận, chức vụ và hợp đồng'),
    ('shifts.manage', 'Quản lý và phân ca'),
    ('attendance.review', 'Duyệt chấm công và điều chỉnh công'),
    ('leave.review', 'Duyệt nghỉ phép'),
    ('swaps.review', 'Duyệt đổi ca'),
    ('payroll.manage', 'Tính và duyệt lương'),
    ('stars.award', 'Tặng sao'),
    ('closures.review', 'Duyệt đóng ca'),
    ('notifications.manage', 'Gửi thông báo trong ứng dụng'),
    ('profile.self', 'Xem hồ sơ cá nhân'),
    ('schedule.self', 'Xem lịch ca cá nhân'),
    ('attendance.self', 'Điểm danh và yêu cầu điều chỉnh công'),
    ('leave.self', 'Gửi yêu cầu nghỉ phép'),
    ('swaps.self', 'Gửi và phản hồi đổi ca'),
    ('payslips.self', 'Xem phiếu lương cá nhân'),
    ('closures.self', 'Gửi ảnh, ghi chú đóng ca'),
    ('stars.self', 'Xem sao cá nhân'),
    ('notifications.self', 'Xem và đọc thông báo');
INSERT INTO role_permissions SELECT r.id, p.id FROM roles r CROSS JOIN permissions p WHERE r.code = 'admin';
INSERT INTO role_permissions SELECT r.id, p.id FROM roles r CROSS JOIN permissions p WHERE r.code = 'manager' AND p.code <> 'users.manage';
INSERT INTO role_permissions SELECT r.id, p.id FROM roles r CROSS JOIN permissions p WHERE r.code = 'employee' AND p.code LIKE '%.self';
