package vn.anhemquan.prm.controller;

import vn.anhemquan.prm.service.ScheduleService;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/schedule")
public class ScheduleController {

    private final ScheduleService service;

    public ScheduleController(ScheduleService service) {
        this.service = service;
    }

    public record CreateShiftRequest(long branchId, OffsetDateTime start, OffsetDateTime end,
            Integer requiredStaff, String note) {
    }

    public record AssignRequest(long employeeId) {
    }

    public record LeaveRequestBody(long leaveTypeId, OffsetDateTime start, OffsetDateTime end, String reason) {
    }

    public record SwapRequestBody(long fromAssignmentId, long toAssignmentId, String reason) {
    }

    public record SwapDecision(boolean accept) {
    }

    public record ShiftResponse(boolean accept, String note) {
    }

    @GetMapping("/branches")
    public List<Map<String, Object>> branches() {
        return service.branches();
    }

    /** Roster rows (assignment per row): everything for managers, own rows for employees. */
    @GetMapping("/shifts")
    public List<Map<String, Object>> shifts() {
        return service.shifts();
    }

    @GetMapping("/shifts/all")
    public List<Map<String, Object>> allShifts() {
        return service.allShifts();
    }

    @GetMapping("/shifts/overview")
    public List<Map<String, Object>> overview(@RequestParam(required = false) Long branchId) {
        return service.managerShiftOverview(branchId);
    }

    @PostMapping("/shifts")
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Long> createShift(@RequestBody CreateShiftRequest r) {
        long id = service.createShift(r.branchId(), r.start(), r.end(),
                r.requiredStaff() == null ? 1 : r.requiredStaff(), r.note());
        return Map.of("id", id);
    }

    @GetMapping("/shifts/{id}")
    public Map<String, Object> shiftDetail(@PathVariable long id) {
        return service.shiftDetail(id);
    }

    @GetMapping("/shifts/{id}/eligible-employees")
    public List<Map<String, Object>> eligible(@PathVariable long id) {
        return service.eligibleEmployeesForShift(id);
    }

    @PostMapping("/shifts/{id}/assignments")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void assign(@PathVariable long id, @RequestBody AssignRequest r) {
        service.assignShift(id, r.employeeId());
    }

    @DeleteMapping("/shifts/{id}/assignments/{employeeId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void unassign(@PathVariable long id, @PathVariable long employeeId) {
        service.unassignShift(id, employeeId);
    }

    @PostMapping("/shifts/{id}/cancel")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void cancel(@PathVariable long id) {
        service.cancelShift(id);
    }

    @GetMapping("/my-schedule")
    public List<Map<String, Object>> mySchedule(@RequestParam(required = false) Long employeeId) {
        return service.employeeSchedule(employeeId);
    }

    /** The assigned employee accepts or rejects (reason required) a shift. */
    @PostMapping("/assignments/{id}/respond")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void respondToShift(@PathVariable long id, @RequestBody ShiftResponse r) {
        service.respondToAssignment(id, r.accept(), r.note());
    }

    /** Employees whose shift table the caller may open. */
    @GetMapping("/employees")
    public List<Map<String, Object>> employees() {
        return service.scheduleEmployees();
    }

    /** Table of every shift of one employee (managers and admins). */
    @GetMapping("/employees/{employeeId}/shifts")
    public Map<String, Object> employeeShifts(@PathVariable long employeeId,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to) {
        return service.employeeShiftTable(employeeId, from, to);
    }

    @GetMapping("/leave-types")
    public List<Map<String, Object>> leaveTypes() {
        return service.leaveTypes();
    }

    @GetMapping("/leave-requests")
    public List<Map<String, Object>> leaveRequests() {
        return service.employeeLeaveRequests();
    }

    @PostMapping("/leave-requests")
    @ResponseStatus(HttpStatus.CREATED)
    public void createLeave(@RequestBody LeaveRequestBody r) {
        service.createLeaveRequest(r.leaveTypeId(), r.start(), r.end(), r.reason());
    }

    /** Own leave balances (days granted / used / left) of the current year. */
    @GetMapping("/leave-balances")
    public List<Map<String, Object>> leaveBalances() {
        return service.leaveBalances();
    }

    /** Leave requests of the manager's branch (all branches for Admin), pending first. */
    @GetMapping("/leave-requests/review")
    public List<Map<String, Object>> leaveRequestsForReview() {
        return service.leaveRequestsForReview();
    }

    /** Approves or rejects a pending leave request; a reason is required to reject. */
    @PostMapping("/leave-requests/{id}/review")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void reviewLeave(@PathVariable long id, @RequestBody LeaveDecision d) {
        service.reviewLeaveRequest(id, d.approve(), d.note());
    }

    public record LeaveDecision(boolean approve, String note) {
    }

    @GetMapping("/assignments/{id}/swap-options")
    public List<Map<String, Object>> swapOptions(@PathVariable long id) {
        return service.swapOptions(id);
    }

    @GetMapping("/swaps")
    public List<Map<String, Object>> swaps() {
        return service.swaps();
    }

    @PostMapping("/swaps")
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Long> requestSwap(@RequestBody SwapRequestBody r) {
        return Map.of("id", service.requestSwap(r.fromAssignmentId(), r.toAssignmentId(), r.reason()));
    }

    /** The counterpart accepts or rejects the swap. */
    @PostMapping("/swaps/{id}/respond")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void respond(@PathVariable long id, @RequestBody SwapDecision d) {
        service.respondSwap(id, d.accept(), false);
    }

    /** A non-involved manager approves or rejects the swap. */
    @PostMapping("/swaps/{id}/review")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void review(@PathVariable long id, @RequestBody SwapDecision d) {
        service.respondSwap(id, d.accept(), true);
    }
}
