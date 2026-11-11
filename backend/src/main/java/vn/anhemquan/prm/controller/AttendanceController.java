package vn.anhemquan.prm.controller;

import vn.anhemquan.prm.service.AttendanceManagementService;
import vn.anhemquan.prm.service.AttendanceSheetService;
import vn.anhemquan.prm.service.AttendanceService;
import vn.anhemquan.prm.dto.Evidence;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** REST surface of the attendance module. See backend/docs/api-attendance.md. */
@RestController
@RequestMapping("/api")
public class AttendanceController {

    private final AttendanceService attendance;
    private final AttendanceManagementService management;

    private final AttendanceSheetService sheets;

    public AttendanceController(AttendanceService attendance, AttendanceManagementService management,
            AttendanceSheetService sheets) {
        this.attendance = attendance;
        this.management = management;
        this.sheets = sheets;
    }

    public record AdminEditRequest(Instant checkIn, Instant checkOut, String reason) {
    }

    public record VoidRequest(String reason) {
    }

    public record PunchRequest(@NotNull String type, @NotNull @Valid Evidence evidence) {
    }

    public record InspectRequest(@NotNull @Valid Evidence evidence) {
    }

    public record SubmitRequest(@NotNull String type, @NotNull @Valid Evidence evidence, Long selectedDeviceId,
            List<String> collectionIssues) {
    }

    public record ReviewRequest(boolean approve, String note) {
    }

    public record DeviceRegistration(@NotNull String deviceIdentifier, String platform) {
    }

    public record AdjustmentRequest(Instant checkIn, Instant checkOut, @NotNull String reason, String evidencePath) {
    }

    public record CloseDayRequest(@NotNull LocalDate date, String note) {
    }

    public record BranchAttendanceConfig(Double latitude, Double longitude, Integer radiusM, String ssid,
            String bssid, Boolean requireOvertimeApproval) {
    }

    // ---- employee: attendance ------------------------------------------------------------------

    @GetMapping("/attendance/assignments/{id}/context")
    public Map<String, Object> context(@PathVariable long id) {
        return attendance.context(id);
    }

    @PostMapping("/attendance/assignments/{id}/inspect")
    public Map<String, Object> inspect(@PathVariable long id, @RequestBody @Valid InspectRequest body) {
        return attendance.inspect(id, body.evidence());
    }

    @PostMapping("/attendance/assignments/{id}/record")
    public Map<String, Object> record(@PathVariable long id, @RequestBody @Valid PunchRequest body) {
        return attendance.record(id, body.type(), body.evidence());
    }

    @PostMapping("/attendance/assignments/{id}/submit")
    public Map<String, Object> submit(@PathVariable long id, @RequestBody @Valid SubmitRequest body) {
        return Map.of("id", attendance.submit(id, body.type(), body.evidence(), body.selectedDeviceId(),
                body.collectionIssues()));
    }

    @GetMapping("/attendance/history")
    public List<Map<String, Object>> history() {
        return attendance.history();
    }

    // ---- reviewers: exceptions -----------------------------------------------------------------

    @GetMapping("/attendance/submissions")
    public List<Map<String, Object>> submissions() {
        return attendance.submissions();
    }

    @PostMapping("/attendance/submissions/{eventId}/review")
    public void reviewSubmission(@PathVariable long eventId, @RequestBody ReviewRequest body) {
        attendance.reviewSubmission(eventId, body.approve(), body.note());
    }

    // ---- management board ----------------------------------------------------------------------

    @GetMapping("/attendance/management")
    public Map<String, Object> overview(
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date,
            @RequestParam(defaultValue = "false") boolean self) {
        return management.overview(date, self);
    }

    @GetMapping("/attendance/assignments/{id}/detail")
    public Map<String, Object> detail(@PathVariable long id) {
        return management.caseDetail(id);
    }

    @GetMapping("/attendance/notifications/{entity}/{id}/assignment")
    public Map<String, Object> notificationAssignment(@PathVariable String entity, @PathVariable long id) {
        return Map.of("assignment_id", management.notificationAssignment(entity, id));
    }

    @PostMapping("/attendance/assignments/{id}/adjustments")
    public Map<String, Object> requestAdjustment(@PathVariable long id, @RequestBody @Valid AdjustmentRequest body) {
        return Map.of("id", management.requestAdjustment(id, body.checkIn(), body.checkOut(), body.reason(),
                body.evidencePath()));
    }

    @PostMapping("/attendance/adjustments/{id}/review")
    public void reviewAdjustment(@PathVariable long id, @RequestBody ReviewRequest body) {
        management.reviewAdjustment(id, body.approve(), body.note());
    }

    @PostMapping("/attendance/assignments/{id}/overtime/review")
    public void reviewOvertime(@PathVariable long id, @RequestBody ReviewRequest body) {
        management.reviewOvertime(id, body.approve(), body.note());
    }

    @PostMapping("/attendance/days/close")
    public void closeDay(@RequestBody @Valid CloseDayRequest body) {
        management.closeDay(body.date(), body.note());
    }

    // ---- attendance sheet (per employee, date range) ---------------------------------------------

    @GetMapping("/attendance/sheet")
    public Map<String, Object> sheet(@RequestParam(required = false) Long employeeId,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to) {
        return sheets.sheet(employeeId, from, to);
    }

    @GetMapping("/attendance/sheet/employees")
    public List<Map<String, Object>> sheetEmployees() {
        return sheets.sheetEmployees();
    }

    @PostMapping("/attendance/assignments/{id}/admin-edit")
    public Map<String, Object> adminEdit(@PathVariable long id, @RequestBody AdminEditRequest body) {
        return sheets.adminEdit(id, body.checkIn(), body.checkOut(), body.reason());
    }

    @PostMapping("/attendance/assignments/{id}/void")
    public Map<String, Object> voidAttendance(@PathVariable long id, @RequestBody VoidRequest body) {
        return sheets.voidAttendance(id, body.reason());
    }

    // ---- devices -------------------------------------------------------------------------------

    @PostMapping("/devices")
    public void registerDevice(@RequestBody @Valid DeviceRegistration body) {
        attendance.registerDevice(body.deviceIdentifier(), body.platform());
    }

    @GetMapping("/devices/mine")
    public List<Map<String, Object>> myDevices() {
        return attendance.myDevices();
    }

    @GetMapping("/devices")
    public List<Map<String, Object>> devices() {
        return attendance.devices();
    }

    @PostMapping("/devices/{id}/approve")
    public void approveDevice(@PathVariable long id) {
        attendance.reviewDevice(id, false);
    }

    @PostMapping("/devices/{id}/revoke")
    public void revokeDevice(@PathVariable long id) {
        attendance.reviewDevice(id, true);
    }

    // ---- branch setup --------------------------------------------------------------------------

    @PutMapping("/branches/{id}/attendance-config")
    public void configureBranch(@PathVariable long id, @RequestBody BranchAttendanceConfig body) {
        attendance.configureBranch(id, body.latitude(), body.longitude(), body.radiusM(), body.ssid(), body.bssid(),
                body.requireOvertimeApproval());
    }
}
