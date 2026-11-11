package vn.anhemquan.prm.controller;

import vn.anhemquan.prm.service.AccountService;

import java.util.List;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/accounts")
public class AccountController {

    private final AccountService accounts;

    public AccountController(AccountService accounts) {
        this.accounts = accounts;
    }

    public record EmailRequest(String email) {
    }

    public record LinkRequest(long userId) {
    }

    @PutMapping("/users/{userId}/email")
    public void setEmail(@PathVariable long userId, @RequestBody EmailRequest r) {
        accounts.setUserEmail(userId, r.email());
    }

    @GetMapping("/unlinked")
    public List<Map<String, Object>> unlinked() {
        return accounts.unlinkedAccounts();
    }

    @PutMapping("/employees/{employeeId}/user")
    public void link(@PathVariable long employeeId, @RequestBody LinkRequest r) {
        accounts.linkEmployee(employeeId, r.userId());
    }
}
