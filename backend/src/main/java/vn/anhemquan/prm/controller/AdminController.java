package vn.anhemquan.prm.controller;

import vn.anhemquan.prm.service.AdminService;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
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
@RequestMapping("/api")
public class AdminController {

    private final AdminService service;

    public AdminController(AdminService service) {
        this.service = service;
    }

    /** Account plus its employee profile: {@code fullName} is required, the rest is optional. */
    public record CreateUserRequest(@NotBlank String username, @NotBlank String password, @NotBlank String role,
            String fullName, Long branchId, String phone, Long monthlySalary) {
    }

    public record CreateEmployeeRequest(@NotBlank String code, @NotBlank String name, String phone) {
    }

    @GetMapping("/notifications")
    public List<Map<String, Object>> notifications() {
        return service.notifications();
    }

    @PostMapping("/notifications/{id}/read")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void markRead(@PathVariable long id) {
        service.markNotificationRead(id);
    }

    @GetMapping("/users")
    public List<Map<String, Object>> users() {
        return service.users();
    }

    @PostMapping("/users")
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Long> createUser(@RequestBody @Valid CreateUserRequest request) {
        return Map.of("employeeId", service.createUser(request.username(), request.password(), request.role(),
                request.fullName(), request.branchId(), request.phone(), request.monthlySalary()));
    }

    @GetMapping("/employees")
    public List<Map<String, Object>> employees() {
        return service.employees();
    }

    @PostMapping("/employees")
    @ResponseStatus(HttpStatus.CREATED)
    public void createEmployee(@RequestBody @Valid CreateEmployeeRequest request) {
        service.createEmployee(request.code(), request.name(), request.phone());
    }

    @GetMapping("/profile")
    public Map<String, Object> profile() {
        return service.profile();
    }

    @GetMapping("/overview")
    public Map<String, Object> overview() {
        return service.overview();
    }
}
