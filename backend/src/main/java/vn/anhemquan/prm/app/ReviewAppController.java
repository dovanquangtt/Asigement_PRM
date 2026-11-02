package vn.anhemquan.prm.app;

import java.time.LocalDate;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import vn.anhemquan.prm.app.AppDto.AdminSummary;
import vn.anhemquan.prm.app.AppDto.DeviceItem;
import vn.anhemquan.prm.app.AppDto.ExceptionItem;
import vn.anhemquan.prm.app.AppDto.ListItem;
import vn.anhemquan.prm.app.AppDto.ManagerSummary;
import vn.anhemquan.prm.app.AppDto.Page;
import vn.anhemquan.prm.app.AppDto.Report;
import vn.anhemquan.prm.app.AppDto.RevokeRequest;
import vn.anhemquan.prm.app.AppDto.ReviewDetail;

/** Manager and Admin endpoints of backend/docs/api-app-contract.md. */
@RestController
@RequestMapping("/api")
public class ReviewAppController {

    private final ReviewAppService service;

    public ReviewAppController(ReviewAppService service) {
        this.service = service;
    }

    // ---- manager -------------------------------------------------------------------------------

    @GetMapping("/manager/attendance/summary")
    public ManagerSummary managerSummary(
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date,
            @RequestParam(required = false) Long branchId) {
        return service.managerSummary(date, branchId);
    }

    @GetMapping("/manager/attendance")
    public Page<ListItem> managerList(
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date,
            @RequestParam(required = false) Long branchId, @RequestParam(required = false) Long shiftId,
            @RequestParam(required = false) String status, @RequestParam(required = false) String q,
            @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "20") int size) {
        return service.list(false, date, branchId, shiftId, status, q, page, size);
    }

    @GetMapping("/manager/attendance/exceptions")
    public Page<ExceptionItem> managerExceptions(
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date,
            @RequestParam(required = false) Long branchId, @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return service.exceptions(false, date, branchId, page, size);
    }

    @GetMapping("/manager/attendance/{attendanceId}")
    public ReviewDetail managerDetail(@PathVariable long attendanceId) {
        return service.detail(false, attendanceId);
    }

    // ---- admin ---------------------------------------------------------------------------------

    @GetMapping("/admin/attendance/summary")
    public AdminSummary adminSummary(
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date,
            @RequestParam(required = false) Long branchId) {
        return service.adminSummary(date, branchId);
    }

    @GetMapping("/admin/attendance")
    public Page<ListItem> adminList(
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date,
            @RequestParam(required = false) Long branchId, @RequestParam(required = false) Long shiftId,
            @RequestParam(required = false) String status, @RequestParam(required = false) String q,
            @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "20") int size) {
        return service.list(true, date, branchId, shiftId, status, q, page, size);
    }

    @GetMapping("/admin/attendance/{attendanceId}")
    public ReviewDetail adminDetail(@PathVariable long attendanceId) {
        return service.detail(true, attendanceId);
    }

    @GetMapping("/admin/devices")
    public Page<DeviceItem> devices(@RequestParam(required = false) String status,
            @RequestParam(required = false) String q, @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return service.devices(status, q, page, size);
    }

    @PostMapping("/admin/devices/{id}/revoke")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void revoke(@PathVariable long id, @RequestBody(required = false) RevokeRequest body) {
        service.revokeDevice(id, body == null ? null : body.reason());
    }

    @PostMapping("/admin/devices/{id}/approve")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void approve(@PathVariable long id) {
        service.approveDevice(id);
    }

    @GetMapping("/admin/reports/attendance")
    public Report report(
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
            @RequestParam(required = false) String groupBy, @RequestParam(required = false) Long branchId) {
        return service.report(from, to, groupBy, branchId);
    }
}
