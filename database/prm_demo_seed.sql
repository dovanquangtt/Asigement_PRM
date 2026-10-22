-- DU LIEU MAU DAY DU CHO 3 ROLE / 34 BANG.
-- Snapshot cua prm_database.db; anh dung asset URI, khong co duong dan may.
-- CHI CHAY TREN SCHEMA v4 TRONG; KHONG CHAY SAU prm_seed.sql.
-- Tai khoan: admin/Admin@12345, manager/Manager@12345, employee/Employee@12345.
PRAGMA foreign_keys=ON;
BEGIN;

-- roles: 3 rows
INSERT INTO "roles" ("id","code","name") VALUES (1,'admin','Quản trị viên');
INSERT INTO "roles" ("id","code","name") VALUES (2,'manager','Quản lý');
INSERT INTO "roles" ("id","code","name") VALUES (3,'employee','Nhân viên');

-- permissions: 20 rows
INSERT INTO "permissions" ("id","code","description") VALUES (1,'users.manage','Quản lý tài khoản và phân quyền');
INSERT INTO "permissions" ("id","code","description") VALUES (2,'reports.view','Xem báo cáo nhân sự và dashboard');
INSERT INTO "permissions" ("id","code","description") VALUES (3,'employees.manage','Quản lý hồ sơ, bộ phận, chức vụ và hợp đồng');
INSERT INTO "permissions" ("id","code","description") VALUES (4,'shifts.manage','Quản lý và phân ca');
INSERT INTO "permissions" ("id","code","description") VALUES (5,'attendance.review','Duyệt chấm công và điều chỉnh công');
INSERT INTO "permissions" ("id","code","description") VALUES (6,'leave.review','Duyệt nghỉ phép');
INSERT INTO "permissions" ("id","code","description") VALUES (7,'swaps.review','Duyệt đổi ca');
INSERT INTO "permissions" ("id","code","description") VALUES (8,'payroll.manage','Tính và duyệt lương');
INSERT INTO "permissions" ("id","code","description") VALUES (9,'stars.award','Tặng sao');
INSERT INTO "permissions" ("id","code","description") VALUES (10,'closures.review','Duyệt đóng ca');
INSERT INTO "permissions" ("id","code","description") VALUES (11,'notifications.manage','Gửi thông báo trong ứng dụng');
INSERT INTO "permissions" ("id","code","description") VALUES (12,'profile.self','Xem hồ sơ cá nhân');
INSERT INTO "permissions" ("id","code","description") VALUES (13,'schedule.self','Xem lịch ca cá nhân');
INSERT INTO "permissions" ("id","code","description") VALUES (14,'attendance.self','Điểm danh và yêu cầu điều chỉnh công');
INSERT INTO "permissions" ("id","code","description") VALUES (15,'leave.self','Gửi yêu cầu nghỉ phép');
INSERT INTO "permissions" ("id","code","description") VALUES (16,'swaps.self','Gửi và phản hồi đổi ca');
INSERT INTO "permissions" ("id","code","description") VALUES (17,'payslips.self','Xem phiếu lương cá nhân');
INSERT INTO "permissions" ("id","code","description") VALUES (18,'closures.self','Gửi ảnh, ghi chú đóng ca');
INSERT INTO "permissions" ("id","code","description") VALUES (19,'stars.self','Xem sao cá nhân');
INSERT INTO "permissions" ("id","code","description") VALUES (20,'notifications.self','Xem và đọc thông báo');

-- role_permissions: 48 rows
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (1,5);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (1,14);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (1,10);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (1,18);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (1,3);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (1,6);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (1,15);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (1,11);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (1,20);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (1,8);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (1,17);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (1,12);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (1,2);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (1,13);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (1,4);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (1,9);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (1,19);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (1,7);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (1,16);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (1,1);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (2,5);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (2,14);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (2,10);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (2,18);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (2,3);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (2,6);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (2,15);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (2,11);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (2,20);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (2,8);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (2,17);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (2,12);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (2,2);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (2,13);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (2,4);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (2,9);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (2,19);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (2,7);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (2,16);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (3,14);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (3,18);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (3,15);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (3,20);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (3,17);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (3,12);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (3,13);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (3,19);
INSERT INTO "role_permissions" ("role_id","permission_id") VALUES (3,16);

-- users: 3 rows
INSERT INTO "users" ("id","username","password_hash","email","is_active","created_at","google_subject") VALUES (1,'admin','$2a$12$ZqUZJ.zCISUQKfsPLESceupoKSZyeAuOAZF7l5bSzkmqzPGsW178G','admin@moc.example',1,'2026-10-15 09:41:50',NULL);
INSERT INTO "users" ("id","username","password_hash","email","is_active","created_at","google_subject") VALUES (2,'manager','$2a$12$EcfTvYmQlGC2wntz/pNoBezQlPGRDu6E8823yVJ0dNpcIc4jR6SJS','manager@moc.example',1,'2026-10-15 09:41:50',NULL);
INSERT INTO "users" ("id","username","password_hash","email","is_active","created_at","google_subject") VALUES (3,'employee','$2a$12$NEDYhkcpBRpA4mwoZ2c34.KOX7GtUsDzaVgqpPIpWnVvcrMLd4ela','employee@moc.example',1,'2026-10-15 09:41:50',NULL);

-- user_roles: 3 rows
INSERT INTO "user_roles" ("user_id","role_id") VALUES (1,1);
INSERT INTO "user_roles" ("user_id","role_id") VALUES (2,2);
INSERT INTO "user_roles" ("user_id","role_id") VALUES (3,3);

-- branches: 1 rows
INSERT INTO "branches" ("id","code","name","address","latitude","longitude","geofence_radius_m","require_gps","require_wifi","require_registered_device") VALUES (1,'MOC_DEMO','ANH EM QUÁN','TP. Hồ Chí Minh',10.7769,106.7009,100,1,1,1);

-- branch_wifi: 1 rows
INSERT INTO "branch_wifi" ("id","branch_id","ssid","bssid","is_active") VALUES (1,1,'MOC_DEMO_WIFI','02:00:00:00:de:01',1);

-- departments: 3 rows
INSERT INTO "departments" ("id","code","name") VALUES (1,'KITCHEN','Bếp');
INSERT INTO "departments" ("id","code","name") VALUES (2,'SERVICE','Phục vụ');
INSERT INTO "departments" ("id","code","name") VALUES (3,'CASHIER','Thu ngân');

-- positions: 4 rows
INSERT INTO "positions" ("id","code","name") VALUES (1,'MANAGER','Quản lý nhà hàng');
INSERT INTO "positions" ("id","code","name") VALUES (2,'CHEF','Đầu bếp');
INSERT INTO "positions" ("id","code","name") VALUES (3,'WAITER','Nhân viên phục vụ');
INSERT INTO "positions" ("id","code","name") VALUES (4,'CASHIER','Thu ngân');

-- employees: 3 rows
INSERT INTO "employees" ("id","user_id","employee_code","full_name","birth_date","phone","address","branch_id","department_id","position_id","manager_id","hire_date","termination_date","status") VALUES (1,1,'DEMO_ADMIN','Nguyễn Xuân Bắc',NULL,NULL,NULL,1,2,1,NULL,'2026-10-01',NULL,'active');
INSERT INTO "employees" ("id","user_id","employee_code","full_name","birth_date","phone","address","branch_id","department_id","position_id","manager_id","hire_date","termination_date","status") VALUES (2,2,'DEMO_MANAGER','Nguyễn Văn Trường',NULL,NULL,NULL,1,2,1,NULL,'2026-10-01',NULL,'active');
INSERT INTO "employees" ("id","user_id","employee_code","full_name","birth_date","phone","address","branch_id","department_id","position_id","manager_id","hire_date","termination_date","status") VALUES (3,3,'DEMO_EMPLOYEE','Đỗ Văn Quang',NULL,NULL,NULL,1,2,3,NULL,'2026-10-01',NULL,'active');

-- employee_devices: 5 rows
INSERT INTO "employee_devices" ("id","employee_id","device_identifier","platform","registered_at","revoked_at","approved_by") VALUES (1,1,'DEMO_DEVICE_ADMIN','android (mẫu, không phải thiết bị thật)','2026-10-08 00:00:00',NULL,2);
INSERT INTO "employee_devices" ("id","employee_id","device_identifier","platform","registered_at","revoked_at","approved_by") VALUES (2,2,'DEMO_DEVICE_MANAGER','android (mẫu, không phải thiết bị thật)','2026-10-08 00:00:00',NULL,1);
INSERT INTO "employee_devices" ("id","employee_id","device_identifier","platform","registered_at","revoked_at","approved_by") VALUES (3,3,'DEMO_DEVICE_EMPLOYEE','android (mẫu, không phải thiết bị thật)','2026-10-08 00:00:00',NULL,1);
INSERT INTO "employee_devices" ("id","employee_id","device_identifier","platform","registered_at","revoked_at","approved_by") VALUES (4,3,'DEMO_DEVICE_PENDING','android (mẫu chờ duyệt)','2026-10-16 06:59:33',NULL,NULL);
INSERT INTO "employee_devices" ("id","employee_id","device_identifier","platform","registered_at","revoked_at","approved_by") VALUES (5,3,'DEMO_DEVICE_REVOKED','android (mẫu đã thu hồi)','2026-10-16 06:59:33','2026-10-16 06:59:33',2);

-- contracts: 3 rows
INSERT INTO "contracts" ("id","employee_id","contract_number","contract_type","start_date","end_date","salary_basis","base_salary_vnd","hourly_rate_vnd","standard_minutes_per_month","status","document_url") VALUES (1,1,'DEMO_CT_ADMIN','indefinite','2026-10-08',NULL,'monthly',24000000,0,12480,'active',NULL);
INSERT INTO "contracts" ("id","employee_id","contract_number","contract_type","start_date","end_date","salary_basis","base_salary_vnd","hourly_rate_vnd","standard_minutes_per_month","status","document_url") VALUES (2,2,'DEMO_CT_MANAGER','indefinite','2026-10-08',NULL,'monthly',18000000,0,12480,'active',NULL);
INSERT INTO "contracts" ("id","employee_id","contract_number","contract_type","start_date","end_date","salary_basis","base_salary_vnd","hourly_rate_vnd","standard_minutes_per_month","status","document_url") VALUES (3,3,'DEMO_CT_EMPLOYEE','indefinite','2026-10-08',NULL,'monthly',10000000,0,12480,'active',NULL);

-- shift_templates: 4 rows
INSERT INTO "shift_templates" ("id","code","name","start_time","end_time","ends_next_day","break_minutes","late_grace_minutes") VALUES (1,'DEMO_MORNING','Ca sáng','08:00','16:00',0,30,5);
INSERT INTO "shift_templates" ("id","code","name","start_time","end_time","ends_next_day","break_minutes","late_grace_minutes") VALUES (2,'DEMO_EVENING','Ca chiều','17:00','21:00',0,15,5);
INSERT INTO "shift_templates" ("id","code","name","start_time","end_time","ends_next_day","break_minutes","late_grace_minutes") VALUES (3,'DEMO_SHORT','Ca ngắn','21:30','23:00',0,0,5);
INSERT INTO "shift_templates" ("id","code","name","start_time","end_time","ends_next_day","break_minutes","late_grace_minutes") VALUES (4,'DEMO_NIGHT','Ca qua đêm','22:00','06:00',1,30,5);

-- shifts: 13 rows
INSERT INTO "shifts" ("id","branch_id","template_id","starts_at","ends_at","required_staff","status","created_by","note") VALUES (1,1,1,'2026-10-09 01:00:00','2026-10-09 09:00:00',3,'closed',2,'[DEMO HISTORY_0] Dữ liệu mẫu để thử chức năng; giờ Việt Nam.');
INSERT INTO "shifts" ("id","branch_id","template_id","starts_at","ends_at","required_staff","status","created_by","note") VALUES (2,1,1,'2026-10-11 01:00:00','2026-10-11 09:00:00',3,'closed',2,'[DEMO HISTORY_1] Dữ liệu mẫu để thử chức năng; giờ Việt Nam.');
INSERT INTO "shifts" ("id","branch_id","template_id","starts_at","ends_at","required_staff","status","created_by","note") VALUES (3,1,1,'2026-10-15 01:00:00','2026-10-15 09:00:00',2,'in_progress',2,'[DEMO READY_CLOSE] Dữ liệu mẫu để thử chức năng; giờ Việt Nam.');
INSERT INTO "shifts" ("id","branch_id","template_id","starts_at","ends_at","required_staff","status","created_by","note") VALUES (4,1,2,'2026-10-15 10:00:00','2026-10-15 14:00:00',1,'in_progress',2,'[DEMO RETRY_CLOSE] Dữ liệu mẫu để thử chức năng; giờ Việt Nam.');
INSERT INTO "shifts" ("id","branch_id","template_id","starts_at","ends_at","required_staff","status","created_by","note") VALUES (5,1,3,'2026-10-15 14:30:00','2026-10-15 16:00:00',1,'in_progress',2,'[DEMO PENDING_CLOSE] Dữ liệu mẫu để thử chức năng; giờ Việt Nam.');
INSERT INTO "shifts" ("id","branch_id","template_id","starts_at","ends_at","required_staff","status","created_by","note") VALUES (6,1,NULL,'2026-10-16 06:44:33','2026-10-16 14:44:33',2,'scheduled',2,'[DEMO LIVE] Dữ liệu mẫu để thử chức năng; giờ Việt Nam.');
INSERT INTO "shifts" ("id","branch_id","template_id","starts_at","ends_at","required_staff","status","created_by","note") VALUES (7,1,2,'2026-10-17 10:00:00','2026-10-17 14:00:00',2,'scheduled',2,'[DEMO UNASSIGNED] Dữ liệu mẫu để thử chức năng; giờ Việt Nam.');
INSERT INTO "shifts" ("id","branch_id","template_id","starts_at","ends_at","required_staff","status","created_by","note") VALUES (8,1,1,'2026-10-17 01:00:00','2026-10-17 09:00:00',1,'scheduled',2,'[DEMO FUTURE_1] Dữ liệu mẫu để thử chức năng; giờ Việt Nam.');
INSERT INTO "shifts" ("id","branch_id","template_id","starts_at","ends_at","required_staff","status","created_by","note") VALUES (9,1,1,'2026-10-18 01:00:00','2026-10-18 09:00:00',1,'scheduled',2,'[DEMO FUTURE_2] Dữ liệu mẫu để thử chức năng; giờ Việt Nam.');
INSERT INTO "shifts" ("id","branch_id","template_id","starts_at","ends_at","required_staff","status","created_by","note") VALUES (10,1,1,'2026-10-19 01:00:00','2026-10-19 09:00:00',1,'scheduled',2,'[DEMO FUTURE_3] Dữ liệu mẫu để thử chức năng; giờ Việt Nam.');
INSERT INTO "shifts" ("id","branch_id","template_id","starts_at","ends_at","required_staff","status","created_by","note") VALUES (11,1,1,'2026-10-20 01:00:00','2026-10-20 09:00:00',1,'scheduled',2,'[DEMO FUTURE_4] Dữ liệu mẫu để thử chức năng; giờ Việt Nam.');
INSERT INTO "shifts" ("id","branch_id","template_id","starts_at","ends_at","required_staff","status","created_by","note") VALUES (12,1,1,'2026-10-21 01:00:00','2026-10-21 09:00:00',1,'scheduled',2,'[DEMO FUTURE_5] Dữ liệu mẫu để thử chức năng; giờ Việt Nam.');
INSERT INTO "shifts" ("id","branch_id","template_id","starts_at","ends_at","required_staff","status","created_by","note") VALUES (13,1,1,'2026-10-22 01:00:00','2026-10-22 09:00:00',1,'scheduled',2,'[DEMO FUTURE_6] Dữ liệu mẫu để thử chức năng; giờ Việt Nam.');

-- shift_assignments: 18 rows
INSERT INTO "shift_assignments" ("id","shift_id","employee_id","assigned_by","assigned_at","status") VALUES (1,1,1,2,'2026-10-16 06:59:33','completed');
INSERT INTO "shift_assignments" ("id","shift_id","employee_id","assigned_by","assigned_at","status") VALUES (2,1,2,2,'2026-10-16 06:59:33','completed');
INSERT INTO "shift_assignments" ("id","shift_id","employee_id","assigned_by","assigned_at","status") VALUES (3,1,3,2,'2026-10-16 06:59:33','completed');
INSERT INTO "shift_assignments" ("id","shift_id","employee_id","assigned_by","assigned_at","status") VALUES (4,2,1,2,'2026-10-16 06:59:33','completed');
INSERT INTO "shift_assignments" ("id","shift_id","employee_id","assigned_by","assigned_at","status") VALUES (5,2,2,2,'2026-10-16 06:59:33','completed');
INSERT INTO "shift_assignments" ("id","shift_id","employee_id","assigned_by","assigned_at","status") VALUES (6,2,3,2,'2026-10-16 06:59:33','completed');
INSERT INTO "shift_assignments" ("id","shift_id","employee_id","assigned_by","assigned_at","status") VALUES (7,3,3,2,'2026-10-16 06:59:33','assigned');
INSERT INTO "shift_assignments" ("id","shift_id","employee_id","assigned_by","assigned_at","status") VALUES (8,3,2,2,'2026-10-16 06:59:33','assigned');
INSERT INTO "shift_assignments" ("id","shift_id","employee_id","assigned_by","assigned_at","status") VALUES (9,4,3,2,'2026-10-16 06:59:33','assigned');
INSERT INTO "shift_assignments" ("id","shift_id","employee_id","assigned_by","assigned_at","status") VALUES (10,5,3,2,'2026-10-16 06:59:33','assigned');
INSERT INTO "shift_assignments" ("id","shift_id","employee_id","assigned_by","assigned_at","status") VALUES (11,6,3,2,'2026-10-16 06:59:33','assigned');
INSERT INTO "shift_assignments" ("id","shift_id","employee_id","assigned_by","assigned_at","status") VALUES (12,6,2,2,'2026-10-16 06:59:33','assigned');
INSERT INTO "shift_assignments" ("id","shift_id","employee_id","assigned_by","assigned_at","status") VALUES (13,8,3,2,'2026-10-16 06:59:33','assigned');
INSERT INTO "shift_assignments" ("id","shift_id","employee_id","assigned_by","assigned_at","status") VALUES (14,9,2,2,'2026-10-16 06:59:33','assigned');
INSERT INTO "shift_assignments" ("id","shift_id","employee_id","assigned_by","assigned_at","status") VALUES (15,10,3,2,'2026-10-16 06:59:33','assigned');
INSERT INTO "shift_assignments" ("id","shift_id","employee_id","assigned_by","assigned_at","status") VALUES (16,11,2,2,'2026-10-16 06:59:33','assigned');
INSERT INTO "shift_assignments" ("id","shift_id","employee_id","assigned_by","assigned_at","status") VALUES (17,12,3,2,'2026-10-16 06:59:33','assigned');
INSERT INTO "shift_assignments" ("id","shift_id","employee_id","assigned_by","assigned_at","status") VALUES (18,13,2,2,'2026-10-16 06:59:33','assigned');

-- attendance_events: 22 rows
INSERT INTO "attendance_events" ("id","assignment_id","event_type","occurred_at","device_id","latitude","longitude","gps_accuracy_m","wifi_ssid","wifi_bssid","device_valid","gps_valid","wifi_valid","result","rejection_reason","confirmed_at") VALUES (1,1,'check_in','2026-10-09 01:00:00',1,10.7769,106.7009,5.0,'MOC_DEMO_WIFI','02:00:00:00:de:01',1,1,1,'accepted',NULL,'2026-10-09 01:00:00');
INSERT INTO "attendance_events" ("id","assignment_id","event_type","occurred_at","device_id","latitude","longitude","gps_accuracy_m","wifi_ssid","wifi_bssid","device_valid","gps_valid","wifi_valid","result","rejection_reason","confirmed_at") VALUES (2,1,'check_out','2026-10-09 09:00:00',1,10.7769,106.7009,5.0,'MOC_DEMO_WIFI','02:00:00:00:de:01',1,1,1,'accepted',NULL,'2026-10-09 09:00:00');
INSERT INTO "attendance_events" ("id","assignment_id","event_type","occurred_at","device_id","latitude","longitude","gps_accuracy_m","wifi_ssid","wifi_bssid","device_valid","gps_valid","wifi_valid","result","rejection_reason","confirmed_at") VALUES (3,2,'check_in','2026-10-09 01:00:00',2,10.7769,106.7009,5.0,'MOC_DEMO_WIFI','02:00:00:00:de:01',1,1,1,'accepted',NULL,'2026-10-09 01:00:00');
INSERT INTO "attendance_events" ("id","assignment_id","event_type","occurred_at","device_id","latitude","longitude","gps_accuracy_m","wifi_ssid","wifi_bssid","device_valid","gps_valid","wifi_valid","result","rejection_reason","confirmed_at") VALUES (4,2,'check_out','2026-10-09 09:00:00',2,10.7769,106.7009,5.0,'MOC_DEMO_WIFI','02:00:00:00:de:01',1,1,1,'accepted',NULL,'2026-10-09 09:00:00');
INSERT INTO "attendance_events" ("id","assignment_id","event_type","occurred_at","device_id","latitude","longitude","gps_accuracy_m","wifi_ssid","wifi_bssid","device_valid","gps_valid","wifi_valid","result","rejection_reason","confirmed_at") VALUES (5,3,'check_in','2026-10-09 01:00:00',3,10.7769,106.7009,5.0,'MOC_DEMO_WIFI','02:00:00:00:de:01',1,1,1,'accepted',NULL,'2026-10-09 01:00:00');
INSERT INTO "attendance_events" ("id","assignment_id","event_type","occurred_at","device_id","latitude","longitude","gps_accuracy_m","wifi_ssid","wifi_bssid","device_valid","gps_valid","wifi_valid","result","rejection_reason","confirmed_at") VALUES (6,3,'check_out','2026-10-09 09:00:00',3,10.7769,106.7009,5.0,'MOC_DEMO_WIFI','02:00:00:00:de:01',1,1,1,'accepted',NULL,'2026-10-09 09:00:00');
INSERT INTO "attendance_events" ("id","assignment_id","event_type","occurred_at","device_id","latitude","longitude","gps_accuracy_m","wifi_ssid","wifi_bssid","device_valid","gps_valid","wifi_valid","result","rejection_reason","confirmed_at") VALUES (7,4,'check_in','2026-10-11 01:00:00',1,10.7769,106.7009,5.0,'MOC_DEMO_WIFI','02:00:00:00:de:01',1,1,1,'accepted',NULL,'2026-10-11 01:00:00');
INSERT INTO "attendance_events" ("id","assignment_id","event_type","occurred_at","device_id","latitude","longitude","gps_accuracy_m","wifi_ssid","wifi_bssid","device_valid","gps_valid","wifi_valid","result","rejection_reason","confirmed_at") VALUES (8,4,'check_out','2026-10-11 09:00:00',1,10.7769,106.7009,5.0,'MOC_DEMO_WIFI','02:00:00:00:de:01',1,1,1,'accepted',NULL,'2026-10-11 09:00:00');
INSERT INTO "attendance_events" ("id","assignment_id","event_type","occurred_at","device_id","latitude","longitude","gps_accuracy_m","wifi_ssid","wifi_bssid","device_valid","gps_valid","wifi_valid","result","rejection_reason","confirmed_at") VALUES (9,5,'check_in','2026-10-11 01:00:00',2,10.7769,106.7009,5.0,'MOC_DEMO_WIFI','02:00:00:00:de:01',1,1,1,'accepted',NULL,'2026-10-11 01:00:00');
INSERT INTO "attendance_events" ("id","assignment_id","event_type","occurred_at","device_id","latitude","longitude","gps_accuracy_m","wifi_ssid","wifi_bssid","device_valid","gps_valid","wifi_valid","result","rejection_reason","confirmed_at") VALUES (10,5,'check_out','2026-10-11 09:00:00',2,10.7769,106.7009,5.0,'MOC_DEMO_WIFI','02:00:00:00:de:01',1,1,1,'accepted',NULL,'2026-10-11 09:00:00');
INSERT INTO "attendance_events" ("id","assignment_id","event_type","occurred_at","device_id","latitude","longitude","gps_accuracy_m","wifi_ssid","wifi_bssid","device_valid","gps_valid","wifi_valid","result","rejection_reason","confirmed_at") VALUES (11,6,'check_in','2026-10-11 01:00:00',3,10.7769,106.7009,5.0,'MOC_DEMO_WIFI','02:00:00:00:de:01',1,1,1,'accepted',NULL,'2026-10-11 01:00:00');
INSERT INTO "attendance_events" ("id","assignment_id","event_type","occurred_at","device_id","latitude","longitude","gps_accuracy_m","wifi_ssid","wifi_bssid","device_valid","gps_valid","wifi_valid","result","rejection_reason","confirmed_at") VALUES (12,6,'check_out','2026-10-11 10:00:00',3,10.7769,106.7009,5.0,'MOC_DEMO_WIFI','02:00:00:00:de:01',1,1,1,'accepted',NULL,'2026-10-11 10:00:00');
INSERT INTO "attendance_events" ("id","assignment_id","event_type","occurred_at","device_id","latitude","longitude","gps_accuracy_m","wifi_ssid","wifi_bssid","device_valid","gps_valid","wifi_valid","result","rejection_reason","confirmed_at") VALUES (13,3,'check_in','2026-10-09 00:58:00',3,NULL,NULL,NULL,NULL,NULL,1,1,0,'rejected','[DEMO] Không kết nối đúng Wi-Fi chi nhánh.',NULL);
INSERT INTO "attendance_events" ("id","assignment_id","event_type","occurred_at","device_id","latitude","longitude","gps_accuracy_m","wifi_ssid","wifi_bssid","device_valid","gps_valid","wifi_valid","result","rejection_reason","confirmed_at") VALUES (14,3,'check_in','2026-10-09 00:59:00',3,NULL,NULL,NULL,NULL,NULL,1,0,1,'pending_review','[DEMO] GPS thiếu chính xác, chờ kiểm tra.',NULL);
INSERT INTO "attendance_events" ("id","assignment_id","event_type","occurred_at","device_id","latitude","longitude","gps_accuracy_m","wifi_ssid","wifi_bssid","device_valid","gps_valid","wifi_valid","result","rejection_reason","confirmed_at") VALUES (15,7,'check_in','2026-10-15 01:00:00',3,10.7769,106.7009,5.0,'MOC_DEMO_WIFI','02:00:00:00:de:01',1,1,1,'accepted',NULL,'2026-10-15 01:00:00');
INSERT INTO "attendance_events" ("id","assignment_id","event_type","occurred_at","device_id","latitude","longitude","gps_accuracy_m","wifi_ssid","wifi_bssid","device_valid","gps_valid","wifi_valid","result","rejection_reason","confirmed_at") VALUES (16,7,'check_out','2026-10-15 09:30:00',3,10.7769,106.7009,5.0,'MOC_DEMO_WIFI','02:00:00:00:de:01',1,1,1,'accepted',NULL,'2026-10-15 09:30:00');
INSERT INTO "attendance_events" ("id","assignment_id","event_type","occurred_at","device_id","latitude","longitude","gps_accuracy_m","wifi_ssid","wifi_bssid","device_valid","gps_valid","wifi_valid","result","rejection_reason","confirmed_at") VALUES (17,8,'check_in','2026-10-15 01:00:00',2,10.7769,106.7009,5.0,'MOC_DEMO_WIFI','02:00:00:00:de:01',1,1,1,'accepted',NULL,'2026-10-15 01:00:00');
INSERT INTO "attendance_events" ("id","assignment_id","event_type","occurred_at","device_id","latitude","longitude","gps_accuracy_m","wifi_ssid","wifi_bssid","device_valid","gps_valid","wifi_valid","result","rejection_reason","confirmed_at") VALUES (18,8,'check_out','2026-10-15 09:00:00',2,10.7769,106.7009,5.0,'MOC_DEMO_WIFI','02:00:00:00:de:01',1,1,1,'accepted',NULL,'2026-10-15 09:00:00');
INSERT INTO "attendance_events" ("id","assignment_id","event_type","occurred_at","device_id","latitude","longitude","gps_accuracy_m","wifi_ssid","wifi_bssid","device_valid","gps_valid","wifi_valid","result","rejection_reason","confirmed_at") VALUES (19,9,'check_in','2026-10-15 10:00:00',3,10.7769,106.7009,5.0,'MOC_DEMO_WIFI','02:00:00:00:de:01',1,1,1,'accepted',NULL,'2026-10-15 10:00:00');
INSERT INTO "attendance_events" ("id","assignment_id","event_type","occurred_at","device_id","latitude","longitude","gps_accuracy_m","wifi_ssid","wifi_bssid","device_valid","gps_valid","wifi_valid","result","rejection_reason","confirmed_at") VALUES (20,9,'check_out','2026-10-15 14:00:00',3,10.7769,106.7009,5.0,'MOC_DEMO_WIFI','02:00:00:00:de:01',1,1,1,'accepted',NULL,'2026-10-15 14:00:00');
INSERT INTO "attendance_events" ("id","assignment_id","event_type","occurred_at","device_id","latitude","longitude","gps_accuracy_m","wifi_ssid","wifi_bssid","device_valid","gps_valid","wifi_valid","result","rejection_reason","confirmed_at") VALUES (21,10,'check_in','2026-10-15 14:30:00',3,10.7769,106.7009,5.0,'MOC_DEMO_WIFI','02:00:00:00:de:01',1,1,1,'accepted',NULL,'2026-10-15 14:30:00');
INSERT INTO "attendance_events" ("id","assignment_id","event_type","occurred_at","device_id","latitude","longitude","gps_accuracy_m","wifi_ssid","wifi_bssid","device_valid","gps_valid","wifi_valid","result","rejection_reason","confirmed_at") VALUES (22,10,'check_out','2026-10-15 16:00:00',3,10.7769,106.7009,5.0,'MOC_DEMO_WIFI','02:00:00:00:de:01',1,1,1,'accepted',NULL,'2026-10-15 16:00:00');

-- attendance_records: 10 rows
INSERT INTO "attendance_records" ("id","assignment_id","check_in_at","check_out_at","worked_minutes","overtime_minutes","late_minutes","status","approved_by","approved_at") VALUES (1,1,'2026-10-09 01:00:00','2026-10-09 09:00:00',450,0,0,'present',2,'2026-10-09 09:00:00');
INSERT INTO "attendance_records" ("id","assignment_id","check_in_at","check_out_at","worked_minutes","overtime_minutes","late_minutes","status","approved_by","approved_at") VALUES (2,2,'2026-10-09 01:00:00','2026-10-09 09:00:00',450,0,0,'present',1,'2026-10-09 09:00:00');
INSERT INTO "attendance_records" ("id","assignment_id","check_in_at","check_out_at","worked_minutes","overtime_minutes","late_minutes","status","approved_by","approved_at") VALUES (3,3,'2026-10-09 01:00:00','2026-10-09 09:00:00',450,0,0,'present',1,'2026-10-09 09:00:00');
INSERT INTO "attendance_records" ("id","assignment_id","check_in_at","check_out_at","worked_minutes","overtime_minutes","late_minutes","status","approved_by","approved_at") VALUES (4,4,'2026-10-11 01:00:00','2026-10-11 09:00:00',450,0,0,'present',2,'2026-10-11 09:00:00');
INSERT INTO "attendance_records" ("id","assignment_id","check_in_at","check_out_at","worked_minutes","overtime_minutes","late_minutes","status","approved_by","approved_at") VALUES (5,5,'2026-10-11 01:00:00','2026-10-11 09:00:00',450,0,0,'present',1,'2026-10-11 09:00:00');
INSERT INTO "attendance_records" ("id","assignment_id","check_in_at","check_out_at","worked_minutes","overtime_minutes","late_minutes","status","approved_by","approved_at") VALUES (6,6,'2026-10-11 01:00:00','2026-10-11 10:00:00',510,60,0,'adjusted',1,'2026-10-11 10:00:00');
INSERT INTO "attendance_records" ("id","assignment_id","check_in_at","check_out_at","worked_minutes","overtime_minutes","late_minutes","status","approved_by","approved_at") VALUES (7,7,'2026-10-15 01:00:00','2026-10-15 09:30:00',480,30,0,'present',1,'2026-10-15 09:30:00');
INSERT INTO "attendance_records" ("id","assignment_id","check_in_at","check_out_at","worked_minutes","overtime_minutes","late_minutes","status","approved_by","approved_at") VALUES (8,8,'2026-10-15 01:00:00','2026-10-15 09:00:00',450,0,0,'present',1,'2026-10-15 09:00:00');
INSERT INTO "attendance_records" ("id","assignment_id","check_in_at","check_out_at","worked_minutes","overtime_minutes","late_minutes","status","approved_by","approved_at") VALUES (9,9,'2026-10-15 10:00:00','2026-10-15 14:00:00',225,0,0,'present',1,'2026-10-15 14:00:00');
INSERT INTO "attendance_records" ("id","assignment_id","check_in_at","check_out_at","worked_minutes","overtime_minutes","late_minutes","status","approved_by","approved_at") VALUES (10,10,'2026-10-15 14:30:00','2026-10-15 16:00:00',90,0,0,'present',1,'2026-10-15 16:00:00');

-- attendance_adjustment_requests: 2 rows
INSERT INTO "attendance_adjustment_requests" ("id","attendance_id","requested_by","requested_check_in","requested_check_out","reason","status","reviewed_by","reviewed_at","review_note","created_at") VALUES (1,3,3,'2026-10-09 01:00:00','2026-10-09 09:00:00','[DEMO] Xin kiểm tra lại giờ vào ca.','pending',NULL,NULL,NULL,'2026-10-16 06:59:33');
INSERT INTO "attendance_adjustment_requests" ("id","attendance_id","requested_by","requested_check_in","requested_check_out","reason","status","reviewed_by","reviewed_at","review_note","created_at") VALUES (2,6,3,'2026-10-11 01:00:00','2026-10-11 10:00:00','[DEMO] Đã đối chiếu và xác nhận lại giờ công.','approved',1,'2026-10-16 06:59:33','[DEMO] Giữ nguyên công sau khi đối chiếu.','2026-10-16 06:59:33');

-- leave_types: 3 rows
INSERT INTO "leave_types" ("id","code","name","is_paid") VALUES (1,'ANNUAL','Nghỉ phép năm',1);
INSERT INTO "leave_types" ("id","code","name","is_paid") VALUES (2,'UNPAID','Nghỉ không lương',0);
INSERT INTO "leave_types" ("id","code","name","is_paid") VALUES (3,'SICK','Nghỉ ốm',0);

-- leave_balances: 3 rows
INSERT INTO "leave_balances" ("employee_id","leave_type_id","year","granted_minutes","used_minutes") VALUES (1,1,2026,5760,0);
INSERT INTO "leave_balances" ("employee_id","leave_type_id","year","granted_minutes","used_minutes") VALUES (2,1,2026,5760,480);
INSERT INTO "leave_balances" ("employee_id","leave_type_id","year","granted_minutes","used_minutes") VALUES (3,1,2026,5760,0);

-- leave_requests: 3 rows
INSERT INTO "leave_requests" ("id","employee_id","leave_type_id","starts_at","ends_at","requested_minutes","reason","status","reviewed_by","reviewed_at","review_note","created_at") VALUES (1,3,1,'2026-10-26 01:00:00','2026-10-26 09:00:00',480,'[DEMO] Nghỉ giải quyết việc gia đình.','pending',NULL,NULL,NULL,'2026-10-16 06:59:33');
INSERT INTO "leave_requests" ("id","employee_id","leave_type_id","starts_at","ends_at","requested_minutes","reason","status","reviewed_by","reviewed_at","review_note","created_at") VALUES (2,2,1,'2026-10-27 01:00:00','2026-10-27 09:00:00',480,'[DEMO] Nghỉ giải quyết việc gia đình.','approved',1,'2026-10-16 06:59:33',NULL,'2026-10-16 06:59:33');
INSERT INTO "leave_requests" ("id","employee_id","leave_type_id","starts_at","ends_at","requested_minutes","reason","status","reviewed_by","reviewed_at","review_note","created_at") VALUES (3,3,1,'2026-10-28 01:00:00','2026-10-28 09:00:00',480,'[DEMO] Nghỉ giải quyết việc gia đình.','rejected',1,'2026-10-16 06:59:33',NULL,'2026-10-16 06:59:33');

-- shift_swap_requests: 3 rows
INSERT INTO "shift_swap_requests" ("id","from_assignment_id","to_assignment_id","requested_by","reason","counterpart_status","status","reviewed_by","reviewed_at","review_note","created_at","from_employee_id","to_employee_id") VALUES (1,13,14,3,'[DEMO] Xin đổi ca do lịch cá nhân.','pending','pending',NULL,NULL,NULL,'2026-10-16 06:59:33',3,2);
INSERT INTO "shift_swap_requests" ("id","from_assignment_id","to_assignment_id","requested_by","reason","counterpart_status","status","reviewed_by","reviewed_at","review_note","created_at","from_employee_id","to_employee_id") VALUES (2,15,16,3,'[DEMO] Xin đổi ca do lịch cá nhân.','accepted','pending',NULL,NULL,NULL,'2026-10-16 06:59:33',3,2);
INSERT INTO "shift_swap_requests" ("id","from_assignment_id","to_assignment_id","requested_by","reason","counterpart_status","status","reviewed_by","reviewed_at","review_note","created_at","from_employee_id","to_employee_id") VALUES (3,17,18,3,'[DEMO] Xin đổi ca do lịch cá nhân.','rejected','rejected',1,'2026-10-16 06:59:33',NULL,'2026-10-16 06:59:33',3,2);

-- payroll_periods: 2 rows
INSERT INTO "payroll_periods" ("id","code","starts_on","ends_on","status","approved_by","approved_at") VALUES (1,'DEMO_PAID','2026-10-08','2026-10-14','paid',1,'2026-10-14 11:00:00');
INSERT INTO "payroll_periods" ("id","code","starts_on","ends_on","status","approved_by","approved_at") VALUES (2,'DEMO_OPEN','2026-10-15','2026-11-13','calculating',NULL,NULL);

-- payroll_policies: 2 rows
INSERT INTO "payroll_policies" ("period_id","overtime_multiplier","created_by") VALUES (1,1.5,2);
INSERT INTO "payroll_policies" ("period_id","overtime_multiplier","created_by") VALUES (2,1.5,2);

-- payslips: 6 rows
INSERT INTO "payslips" ("id","period_id","employee_id","contract_id","regular_minutes","overtime_minutes","base_pay_vnd","overtime_pay_vnd","status","calculated_at","approved_by","approved_at","paid_at") VALUES (1,1,1,1,900,0,1730769,0,'paid','2026-10-16 06:59:33',1,'2026-10-14 11:00:00','2026-10-14 12:00:00');
INSERT INTO "payslips" ("id","period_id","employee_id","contract_id","regular_minutes","overtime_minutes","base_pay_vnd","overtime_pay_vnd","status","calculated_at","approved_by","approved_at","paid_at") VALUES (2,1,2,2,900,0,1298077,0,'paid','2026-10-16 06:59:33',1,'2026-10-14 11:00:00','2026-10-14 12:00:00');
INSERT INTO "payslips" ("id","period_id","employee_id","contract_id","regular_minutes","overtime_minutes","base_pay_vnd","overtime_pay_vnd","status","calculated_at","approved_by","approved_at","paid_at") VALUES (3,1,3,3,900,60,721154,72115,'paid','2026-10-16 06:59:33',1,'2026-10-14 11:00:00','2026-10-14 12:00:00');
INSERT INTO "payslips" ("id","period_id","employee_id","contract_id","regular_minutes","overtime_minutes","base_pay_vnd","overtime_pay_vnd","status","calculated_at","approved_by","approved_at","paid_at") VALUES (4,2,1,1,0,0,0,0,'draft','2026-10-16 06:59:33',NULL,NULL,NULL);
INSERT INTO "payslips" ("id","period_id","employee_id","contract_id","regular_minutes","overtime_minutes","base_pay_vnd","overtime_pay_vnd","status","calculated_at","approved_by","approved_at","paid_at") VALUES (5,2,2,2,450,0,649038,0,'draft','2026-10-16 06:59:33',NULL,NULL,NULL);
INSERT INTO "payslips" ("id","period_id","employee_id","contract_id","regular_minutes","overtime_minutes","base_pay_vnd","overtime_pay_vnd","status","calculated_at","approved_by","approved_at","paid_at") VALUES (6,2,3,3,765,30,612981,36058,'draft','2026-10-16 06:59:33',NULL,NULL,NULL);

-- payslip_items: 30 rows
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (1,1,'MEAL','Phụ cấp ăn','allowance',100000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (2,1,'PERFORMANCE','Thưởng hiệu suất','bonus',50000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (3,1,'INSURANCE','Bảo hiểm mẫu','insurance',30000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (4,1,'TAX','Thuế mẫu','tax',10000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (5,1,'OTHER','Khấu trừ mẫu','deduction',5000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (6,2,'MEAL','Phụ cấp ăn','allowance',100000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (7,2,'PERFORMANCE','Thưởng hiệu suất','bonus',50000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (8,2,'INSURANCE','Bảo hiểm mẫu','insurance',30000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (9,2,'TAX','Thuế mẫu','tax',10000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (10,2,'OTHER','Khấu trừ mẫu','deduction',5000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (11,3,'MEAL','Phụ cấp ăn','allowance',100000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (12,3,'PERFORMANCE','Thưởng hiệu suất','bonus',50000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (13,3,'INSURANCE','Bảo hiểm mẫu','insurance',30000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (14,3,'TAX','Thuế mẫu','tax',10000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (15,3,'OTHER','Khấu trừ mẫu','deduction',5000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (16,4,'MEAL','Phụ cấp ăn','allowance',100000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (17,4,'PERFORMANCE','Thưởng hiệu suất','bonus',50000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (18,4,'INSURANCE','Bảo hiểm mẫu','insurance',30000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (19,4,'TAX','Thuế mẫu','tax',10000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (20,4,'OTHER','Khấu trừ mẫu','deduction',5000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (21,5,'MEAL','Phụ cấp ăn','allowance',100000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (22,5,'PERFORMANCE','Thưởng hiệu suất','bonus',50000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (23,5,'INSURANCE','Bảo hiểm mẫu','insurance',30000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (24,5,'TAX','Thuế mẫu','tax',10000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (25,5,'OTHER','Khấu trừ mẫu','deduction',5000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (26,6,'MEAL','Phụ cấp ăn','allowance',100000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (27,6,'PERFORMANCE','Thưởng hiệu suất','bonus',50000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (28,6,'INSURANCE','Bảo hiểm mẫu','insurance',30000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (29,6,'TAX','Thuế mẫu','tax',10000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');
INSERT INTO "payslip_items" ("id","payslip_id","code","name","item_type","amount_vnd","note") VALUES (30,6,'OTHER','Khấu trừ mẫu','deduction',5000,'[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.');

-- payroll_calculation_steps: 12 rows
INSERT INTO "payroll_calculation_steps" ("id","period_id","step_number","name","status","executed_by","executed_at","detail") VALUES (1,1,1,'Kiểm tra kỳ lương và hồ sơ','completed',2,'2026-10-16 06:59:33','[DEMO] Đã kiểm tra 3 hồ sơ mẫu.');
INSERT INTO "payroll_calculation_steps" ("id","period_id","step_number","name","status","executed_by","executed_at","detail") VALUES (2,1,2,'Kiểm tra hợp đồng và đơn giá','completed',2,'2026-10-16 06:59:33','[DEMO] Đã kiểm tra 3 hồ sơ mẫu.');
INSERT INTO "payroll_calculation_steps" ("id","period_id","step_number","name","status","executed_by","executed_at","detail") VALUES (3,1,3,'Tổng hợp công hợp lệ','completed',2,'2026-10-16 06:59:33','[DEMO] Đã kiểm tra 3 hồ sơ mẫu.');
INSERT INTO "payroll_calculation_steps" ("id","period_id","step_number","name","status","executed_by","executed_at","detail") VALUES (4,1,4,'Tính lương thường và tăng ca','completed',2,'2026-10-16 06:59:33','[DEMO] Đã kiểm tra 3 hồ sơ mẫu.');
INSERT INTO "payroll_calculation_steps" ("id","period_id","step_number","name","status","executed_by","executed_at","detail") VALUES (5,1,5,'Tổng hợp khoản cộng/trừ','completed',2,'2026-10-16 06:59:33','[DEMO] Đã kiểm tra 3 hồ sơ mẫu.');
INSERT INTO "payroll_calculation_steps" ("id","period_id","step_number","name","status","executed_by","executed_at","detail") VALUES (6,1,6,'Kiểm tra và lưu phiếu lương','completed',2,'2026-10-16 06:59:33','[DEMO] Đã kiểm tra 3 hồ sơ mẫu.');
INSERT INTO "payroll_calculation_steps" ("id","period_id","step_number","name","status","executed_by","executed_at","detail") VALUES (7,2,1,'Kiểm tra kỳ lương và hồ sơ','completed',2,'2026-10-16 06:59:33','[DEMO] Đã kiểm tra 3 hồ sơ mẫu.');
INSERT INTO "payroll_calculation_steps" ("id","period_id","step_number","name","status","executed_by","executed_at","detail") VALUES (8,2,2,'Kiểm tra hợp đồng và đơn giá','completed',2,'2026-10-16 06:59:33','[DEMO] Đã kiểm tra 3 hồ sơ mẫu.');
INSERT INTO "payroll_calculation_steps" ("id","period_id","step_number","name","status","executed_by","executed_at","detail") VALUES (9,2,3,'Tổng hợp công hợp lệ','completed',2,'2026-10-16 06:59:33','[DEMO] Đã kiểm tra 3 hồ sơ mẫu.');
INSERT INTO "payroll_calculation_steps" ("id","period_id","step_number","name","status","executed_by","executed_at","detail") VALUES (10,2,4,'Tính lương thường và tăng ca','completed',2,'2026-10-16 06:59:33','[DEMO] Đã kiểm tra 3 hồ sơ mẫu.');
INSERT INTO "payroll_calculation_steps" ("id","period_id","step_number","name","status","executed_by","executed_at","detail") VALUES (11,2,5,'Tổng hợp khoản cộng/trừ','completed',2,'2026-10-16 06:59:33','[DEMO] Đã kiểm tra 3 hồ sơ mẫu.');
INSERT INTO "payroll_calculation_steps" ("id","period_id","step_number","name","status","executed_by","executed_at","detail") VALUES (12,2,6,'Kiểm tra và lưu phiếu lương','completed',2,'2026-10-16 06:59:33','[DEMO] Đã kiểm tra 3 hồ sơ mẫu.');

-- employee_payroll_checks: 36 rows
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (1,1,1,'Kiểm tra kỳ lương và hồ sơ','[DEMO] Kỳ DEMO_PAID • DEMO_ADMIN','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (1,1,2,'Kiểm tra hợp đồng và đơn giá','Hợp đồng DEMO_CT_ADMIN • 1923.08 VND/phút','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (1,1,3,'Tổng hợp công hợp lệ','900 phút thường, 0 phút tăng ca','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (1,1,4,'Tính lương thường và tăng ca','1730769 VND + 0 VND; hệ số 1.5','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (1,1,5,'Tổng hợp khoản cộng/trừ','Cộng 150000 VND, trừ 45000 VND','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (1,1,6,'Kiểm tra và lưu phiếu lương','Phiếu #1 • thực lĩnh 1835769 VND','2026-10-16 06:59:33','05957c532486ed41bbc496b79662b68d321f8a198484c03e674f1483ac16487d');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (1,2,1,'Kiểm tra kỳ lương và hồ sơ','[DEMO] Kỳ DEMO_PAID • DEMO_MANAGER','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (1,2,2,'Kiểm tra hợp đồng và đơn giá','Hợp đồng DEMO_CT_MANAGER • 1442.31 VND/phút','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (1,2,3,'Tổng hợp công hợp lệ','900 phút thường, 0 phút tăng ca','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (1,2,4,'Tính lương thường và tăng ca','1298077 VND + 0 VND; hệ số 1.5','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (1,2,5,'Tổng hợp khoản cộng/trừ','Cộng 150000 VND, trừ 45000 VND','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (1,2,6,'Kiểm tra và lưu phiếu lương','Phiếu #2 • thực lĩnh 1403077 VND','2026-10-16 06:59:33','99a97558021d854eb01c1a25e1457e7185605e291c84e9d3faf3d4c3062abd02');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (1,3,1,'Kiểm tra kỳ lương và hồ sơ','[DEMO] Kỳ DEMO_PAID • DEMO_EMPLOYEE','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (1,3,2,'Kiểm tra hợp đồng và đơn giá','Hợp đồng DEMO_CT_EMPLOYEE • 801.28 VND/phút','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (1,3,3,'Tổng hợp công hợp lệ','900 phút thường, 60 phút tăng ca','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (1,3,4,'Tính lương thường và tăng ca','721154 VND + 72115 VND; hệ số 1.5','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (1,3,5,'Tổng hợp khoản cộng/trừ','Cộng 150000 VND, trừ 45000 VND','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (1,3,6,'Kiểm tra và lưu phiếu lương','Phiếu #3 • thực lĩnh 898269 VND','2026-10-16 06:59:33','864dabc962a075070ca526f0e2d3fd74ece1474e4d6753c514cc30d8c4af4574');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (2,1,1,'Kiểm tra kỳ lương và hồ sơ','[DEMO] Kỳ DEMO_OPEN • DEMO_ADMIN','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (2,1,2,'Kiểm tra hợp đồng và đơn giá','Hợp đồng DEMO_CT_ADMIN • 1923.08 VND/phút','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (2,1,3,'Tổng hợp công hợp lệ','0 phút thường, 0 phút tăng ca','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (2,1,4,'Tính lương thường và tăng ca','0 VND + 0 VND; hệ số 1.5','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (2,1,5,'Tổng hợp khoản cộng/trừ','Cộng 150000 VND, trừ 45000 VND','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (2,1,6,'Kiểm tra và lưu phiếu lương','Phiếu #4 • thực lĩnh 105000 VND','2026-10-16 06:59:33','2e472a499769d73e00bbf0beea2bec7a81e9fb56ec7104ae4a512c9c5cd5b404');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (2,2,1,'Kiểm tra kỳ lương và hồ sơ','[DEMO] Kỳ DEMO_OPEN • DEMO_MANAGER','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (2,2,2,'Kiểm tra hợp đồng và đơn giá','Hợp đồng DEMO_CT_MANAGER • 1442.31 VND/phút','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (2,2,3,'Tổng hợp công hợp lệ','450 phút thường, 0 phút tăng ca','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (2,2,4,'Tính lương thường và tăng ca','649038 VND + 0 VND; hệ số 1.5','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (2,2,5,'Tổng hợp khoản cộng/trừ','Cộng 150000 VND, trừ 45000 VND','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (2,2,6,'Kiểm tra và lưu phiếu lương','Phiếu #5 • thực lĩnh 754038 VND','2026-10-16 06:59:33','4a9dd6e4059d461836562bce1ae31e380f4c1abc641377d1d973107366b60d82');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (2,3,1,'Kiểm tra kỳ lương và hồ sơ','[DEMO] Kỳ DEMO_OPEN • DEMO_EMPLOYEE','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (2,3,2,'Kiểm tra hợp đồng và đơn giá','Hợp đồng DEMO_CT_EMPLOYEE • 801.28 VND/phút','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (2,3,3,'Tổng hợp công hợp lệ','765 phút thường, 30 phút tăng ca','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (2,3,4,'Tính lương thường và tăng ca','612981 VND + 36058 VND; hệ số 1.5','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (2,3,5,'Tổng hợp khoản cộng/trừ','Cộng 150000 VND, trừ 45000 VND','2026-10-16 06:59:33','');
INSERT INTO "employee_payroll_checks" ("period_id","employee_id","step_number","name","detail","checked_at","source_hash") VALUES (2,3,6,'Kiểm tra và lưu phiếu lương','Phiếu #6 • thực lĩnh 754039 VND','2026-10-16 06:59:33','b8e97bf6079c1a82c9ac22d95ca7a6a8e2a917745e021a9d68cc8a30ea3ec366');

-- star_events: 4 rows
INSERT INTO "star_events" ("id","employee_id","assignment_id","stars_delta","reason","awarded_by","created_at") VALUES (1,3,NULL,3,'[DEMO] Hoàn thành tốt ca làm',1,'2026-10-16 06:59:33');
INSERT INTO "star_events" ("id","employee_id","assignment_id","stars_delta","reason","awarded_by","created_at") VALUES (2,3,NULL,-1,'[DEMO] Đi muộn trong tình huống mẫu',1,'2026-10-16 06:59:33');
INSERT INTO "star_events" ("id","employee_id","assignment_id","stars_delta","reason","awarded_by","created_at") VALUES (3,2,NULL,5,'[DEMO] Điều phối ca tốt',1,'2026-10-16 06:59:33');
INSERT INTO "star_events" ("id","employee_id","assignment_id","stars_delta","reason","awarded_by","created_at") VALUES (4,1,NULL,2,'[DEMO] Hỗ trợ đội ngũ',2,'2026-10-16 06:59:33');

-- shift_closures: 9 rows
INSERT INTO "shift_closures" ("id","assignment_id","submitted_by","note","submitted_at","status","reviewed_by","reviewed_at","review_note") VALUES (1,1,1,'[DEMO] Đã vệ sinh khu vực, kiểm tra dụng cụ và bàn giao ca.','2026-10-09 09:05:00','approved',2,'2026-10-09 09:10:00',NULL);
INSERT INTO "shift_closures" ("id","assignment_id","submitted_by","note","submitted_at","status","reviewed_by","reviewed_at","review_note") VALUES (2,2,2,'[DEMO] Đã vệ sinh khu vực, kiểm tra dụng cụ và bàn giao ca.','2026-10-09 09:05:00','approved',1,'2026-10-09 09:10:00',NULL);
INSERT INTO "shift_closures" ("id","assignment_id","submitted_by","note","submitted_at","status","reviewed_by","reviewed_at","review_note") VALUES (3,3,3,'[DEMO] Đã vệ sinh khu vực, kiểm tra dụng cụ và bàn giao ca.','2026-10-09 09:05:00','approved',1,'2026-10-09 09:10:00',NULL);
INSERT INTO "shift_closures" ("id","assignment_id","submitted_by","note","submitted_at","status","reviewed_by","reviewed_at","review_note") VALUES (4,4,1,'[DEMO] Đã vệ sinh khu vực, kiểm tra dụng cụ và bàn giao ca.','2026-10-11 09:05:00','approved',2,'2026-10-11 09:10:00',NULL);
INSERT INTO "shift_closures" ("id","assignment_id","submitted_by","note","submitted_at","status","reviewed_by","reviewed_at","review_note") VALUES (5,5,2,'[DEMO] Đã vệ sinh khu vực, kiểm tra dụng cụ và bàn giao ca.','2026-10-11 09:05:00','approved',1,'2026-10-11 09:10:00',NULL);
INSERT INTO "shift_closures" ("id","assignment_id","submitted_by","note","submitted_at","status","reviewed_by","reviewed_at","review_note") VALUES (6,6,3,'[DEMO] Đã vệ sinh khu vực, kiểm tra dụng cụ và bàn giao ca.','2026-10-11 10:05:00','approved',1,'2026-10-11 10:10:00',NULL);
INSERT INTO "shift_closures" ("id","assignment_id","submitted_by","note","submitted_at","status","reviewed_by","reviewed_at","review_note") VALUES (7,8,2,'[DEMO] Đã vệ sinh khu vực, kiểm tra dụng cụ và bàn giao ca.','2026-10-15 09:05:00','submitted',NULL,NULL,NULL);
INSERT INTO "shift_closures" ("id","assignment_id","submitted_by","note","submitted_at","status","reviewed_by","reviewed_at","review_note") VALUES (8,9,3,'[DEMO] Đã vệ sinh khu vực, kiểm tra dụng cụ và bàn giao ca.','2026-10-15 14:05:00','rejected',1,'2026-10-15 14:10:00','[DEMO] Cần bổ sung ghi chú và chụp ảnh bàn giao rõ hơn.');
INSERT INTO "shift_closures" ("id","assignment_id","submitted_by","note","submitted_at","status","reviewed_by","reviewed_at","review_note") VALUES (9,10,3,'[DEMO] Đã vệ sinh khu vực, kiểm tra dụng cụ và bàn giao ca.','2026-10-15 16:05:00','submitted',NULL,NULL,NULL);

-- shift_closure_photos: 9 rows
INSERT INTO "shift_closure_photos" ("id","closure_id","file_url","captured_at","caption") VALUES (1,1,'asset:database/demo_assets/closure_sample.png','2026-10-09 09:05:00','Ảnh minh họa dữ liệu DEMO, không phải ảnh chụp thực tế.');
INSERT INTO "shift_closure_photos" ("id","closure_id","file_url","captured_at","caption") VALUES (2,2,'asset:database/demo_assets/closure_sample.png','2026-10-09 09:05:00','Ảnh minh họa dữ liệu DEMO, không phải ảnh chụp thực tế.');
INSERT INTO "shift_closure_photos" ("id","closure_id","file_url","captured_at","caption") VALUES (3,3,'asset:database/demo_assets/closure_sample.png','2026-10-09 09:05:00','Ảnh minh họa dữ liệu DEMO, không phải ảnh chụp thực tế.');
INSERT INTO "shift_closure_photos" ("id","closure_id","file_url","captured_at","caption") VALUES (4,4,'asset:database/demo_assets/closure_sample.png','2026-10-11 09:05:00','Ảnh minh họa dữ liệu DEMO, không phải ảnh chụp thực tế.');
INSERT INTO "shift_closure_photos" ("id","closure_id","file_url","captured_at","caption") VALUES (5,5,'asset:database/demo_assets/closure_sample.png','2026-10-11 09:05:00','Ảnh minh họa dữ liệu DEMO, không phải ảnh chụp thực tế.');
INSERT INTO "shift_closure_photos" ("id","closure_id","file_url","captured_at","caption") VALUES (6,6,'asset:database/demo_assets/closure_sample.png','2026-10-11 10:05:00','Ảnh minh họa dữ liệu DEMO, không phải ảnh chụp thực tế.');
INSERT INTO "shift_closure_photos" ("id","closure_id","file_url","captured_at","caption") VALUES (7,7,'asset:database/demo_assets/closure_sample.png','2026-10-15 09:05:00','Ảnh minh họa dữ liệu DEMO, không phải ảnh chụp thực tế.');
INSERT INTO "shift_closure_photos" ("id","closure_id","file_url","captured_at","caption") VALUES (8,8,'asset:database/demo_assets/closure_sample.png','2026-10-15 14:05:00','Ảnh minh họa dữ liệu DEMO, không phải ảnh chụp thực tế.');
INSERT INTO "shift_closure_photos" ("id","closure_id","file_url","captured_at","caption") VALUES (9,9,'asset:database/demo_assets/closure_sample.png','2026-10-15 16:05:00','Ảnh minh họa dữ liệu DEMO, không phải ảnh chụp thực tế.');

-- notifications: 3 rows
INSERT INTO "notifications" ("id","title","body","notification_type","created_by","created_at","related_entity","related_id") VALUES (1,'Lịch ca DEMO đã sẵn sàng','[DEMO] Mở lịch ca để thử điểm danh, đổi ca và đóng ca.','schedule',1,'2026-10-16 06:59:33',NULL,NULL);
INSERT INTO "notifications" ("id","title","body","notification_type","created_by","created_at","related_entity","related_id") VALUES (2,'Phiếu lương mẫu','[DEMO] Đã có kỳ DEMO_PAID và DEMO_OPEN để xem/tính lại.','payroll',1,'2026-10-16 06:59:33',NULL,NULL);
INSERT INTO "notifications" ("id","title","body","notification_type","created_by","created_at","related_entity","related_id") VALUES (3,'Cấu hình thật trước khi điểm danh','[DEMO] GPS/Wi-Fi và mã thiết bị DEMO không thay cho cấu hình, thiết bị thật.','system',1,'2026-10-16 06:59:33',NULL,NULL);

-- notification_recipients: 9 rows
INSERT INTO "notification_recipients" ("notification_id","user_id","read_at") VALUES (1,1,NULL);
INSERT INTO "notification_recipients" ("notification_id","user_id","read_at") VALUES (1,2,NULL);
INSERT INTO "notification_recipients" ("notification_id","user_id","read_at") VALUES (1,3,NULL);
INSERT INTO "notification_recipients" ("notification_id","user_id","read_at") VALUES (2,1,NULL);
INSERT INTO "notification_recipients" ("notification_id","user_id","read_at") VALUES (2,2,NULL);
INSERT INTO "notification_recipients" ("notification_id","user_id","read_at") VALUES (2,3,NULL);
INSERT INTO "notification_recipients" ("notification_id","user_id","read_at") VALUES (3,1,NULL);
INSERT INTO "notification_recipients" ("notification_id","user_id","read_at") VALUES (3,2,NULL);
INSERT INTO "notification_recipients" ("notification_id","user_id","read_at") VALUES (3,3,NULL);

-- audit_logs: 1 rows
INSERT INTO "audit_logs" ("id","actor_user_id","action","entity_type","entity_id","before_json","after_json","created_at") VALUES (1,1,'sample.features.v1','sample_dataset',NULL,NULL,'{"reference_utc":"2026-10-16 06:59:33","live_shift":"DEMO LIVE","tables":34,"note":"Dữ liệu mẫu, không thay cấu hình bảo mật hoặc danh tính Google."}','2026-10-16 06:59:33');
PRAGMA user_version=4;
COMMIT;
