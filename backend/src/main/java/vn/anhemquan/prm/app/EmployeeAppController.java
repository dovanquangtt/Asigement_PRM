package vn.anhemquan.prm.app;

import jakarta.validation.Valid;
import java.time.LocalDate;
import java.util.List;
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
import vn.anhemquan.prm.app.AppDto.ActionResponse;
import vn.anhemquan.prm.app.AppDto.Detail;
import vn.anhemquan.prm.app.AppDto.Employee;
import vn.anhemquan.prm.app.AppDto.HistoryItem;
import vn.anhemquan.prm.app.AppDto.MyShift;
import vn.anhemquan.prm.app.AppDto.Page;
import vn.anhemquan.prm.app.AppDto.PunchRequest;
import vn.anhemquan.prm.app.AppDto.Today;

/** Employee endpoints of backend/docs/api-app-contract.md. */
@RestController
@RequestMapping("/api")
public class EmployeeAppController {

    private final EmployeeAppService service;

    public EmployeeAppController(EmployeeAppService service) {
        this.service = service;
    }

    @GetMapping("/employees/me")
    public Employee me() {
        return service.me();
    }

    @GetMapping("/employees/me/shifts")
    public List<MyShift> myShifts(
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to) {
        return service.myShifts(from, to);
    }

    @GetMapping("/attendance/me/today")
    public Today today() {
        return service.today();
    }

    @PostMapping("/attendance/check-in")
    @ResponseStatus(HttpStatus.CREATED)
    public ActionResponse checkIn(@RequestBody @Valid PunchRequest body) {
        return service.checkIn(body);
    }

    @PostMapping("/attendance/check-out")
    @ResponseStatus(HttpStatus.CREATED)
    public ActionResponse checkOut(@RequestBody @Valid PunchRequest body) {
        return service.checkOut(body);
    }

    @GetMapping("/attendance/me/history")
    public Page<HistoryItem> history(
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
            @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "20") int size) {
        return service.history(from, to, page, size);
    }

    @GetMapping("/attendance/me/{attendanceId}")
    public Detail detail(@PathVariable long attendanceId) {
        return service.detail(attendanceId);
    }
}
