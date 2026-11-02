package vn.anhemquan.prm.payroll;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/payroll")
public class PayrollController {

    private final PayrollService payroll;

    public PayrollController(PayrollService payroll) {
        this.payroll = payroll;
    }

    public record PeriodRequest(String code, LocalDate startsOn, LocalDate endsOn, double overtimeMultiplier) {
    }

    public record ContractRequest(long employeeId, String contractNumber, long monthlySalary, int standardMinutes,
            LocalDate startsOn) {
    }

    public record CalculateRequest(Long employeeId) {
    }

    public record PayItemRequest(String code, String name, String type, long amount) {
    }

    @GetMapping("/periods")
    public List<Map<String, Object>> periods() {
        return payroll.periods();
    }

    @PostMapping("/periods")
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Long> createPeriod(@RequestBody PeriodRequest r) {
        return Map.of("id", payroll.createPeriod(r.code(), r.startsOn(), r.endsOn(), r.overtimeMultiplier()));
    }

    @PostMapping("/contracts")
    @ResponseStatus(HttpStatus.CREATED)
    public void saveContract(@RequestBody ContractRequest r) {
        payroll.saveContract(r.employeeId(), r.contractNumber(), r.monthlySalary(), r.standardMinutes(),
                r.startsOn());
    }

    @GetMapping("/payslips")
    public List<Map<String, Object>> payslips() {
        return payroll.payslips();
    }

    @GetMapping("/payslips/{id}")
    public Map<String, Object> payslip(@PathVariable long id) {
        return payroll.payslipDetail(id);
    }

    @PostMapping("/payslips/{id}/items")
    @ResponseStatus(HttpStatus.CREATED)
    public void addItem(@PathVariable long id, @RequestBody PayItemRequest r) {
        payroll.addPayItem(id, r.code(), r.name(), r.type(), r.amount());
    }

    /** Body is optional: {"employeeId": n} limits the calculation to one employee. */
    @PostMapping("/periods/{id}/calculate")
    public Map<String, Object> calculate(@PathVariable long id,
            @RequestBody(required = false) CalculateRequest r) {
        return payroll.calculatePay(id, r == null ? null : r.employeeId());
    }

    @PostMapping("/periods/{id}/approve")
    public void approve(@PathVariable long id) {
        payroll.approvePayroll(id);
    }
}
