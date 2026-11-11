package vn.anhemquan.prm.controller;

import vn.anhemquan.prm.service.AuthService;

import jakarta.validation.constraints.NotBlank;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import vn.anhemquan.prm.security.Access;

@RestController
@RequestMapping("/api/auth")
@Validated
public class AuthController {

    private final AuthService auth;
    private final Access access;

    public AuthController(AuthService auth, Access access) {
        this.auth = auth;
        this.access = access;
    }

    public record LoginRequest(@NotBlank String username, @NotBlank String password) {
    }

    public record GoogleLoginRequest(@NotBlank String idToken) {
    }

    public record BootstrapRequest(@NotBlank String username, @NotBlank String password) {
    }

    @PostMapping("/login")
    public AuthService.LoginResponse login(@RequestBody @jakarta.validation.Valid LoginRequest request) {
        return auth.signIn(request.username(), request.password());
    }

    /** Body: the Google ID token obtained by the Flutter google_sign_in plugin. */
    @PostMapping("/google")
    public AuthService.LoginResponse google(@RequestBody @jakarta.validation.Valid GoogleLoginRequest request) {
        return auth.signInGoogle(request.idToken());
    }

    @GetMapping("/bootstrap")
    public Map<String, Boolean> bootstrapStatus() {
        return Map.of("needsFirstAdmin", !auth.hasUsers());
    }

    @PostMapping("/bootstrap")
    @ResponseStatus(HttpStatus.CREATED)
    public void bootstrap(@RequestBody @jakarta.validation.Valid BootstrapRequest request) {
        auth.createFirstAdmin(request.username(), request.password());
    }

    @GetMapping("/me")
    public AuthService.SessionInfo me() {
        return auth.session(access.userId());
    }
}
