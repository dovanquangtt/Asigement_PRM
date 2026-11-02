package vn.anhemquan.prm.closures;

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
@RequestMapping("/api/closures")
public class ClosureController {

    private final ClosureService closures;

    public ClosureController(ClosureService closures) {
        this.closures = closures;
    }

    public record SubmitRequest(long assignmentId, String note, String photoUrl) {
    }

    public record ReviewRequest(boolean approve) {
    }

    @GetMapping
    public List<Map<String, Object>> list() {
        return closures.closures();
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Long> submit(@RequestBody SubmitRequest r) {
        return Map.of("id", closures.closeAssignment(r.assignmentId(), r.note(), r.photoUrl()));
    }

    @PostMapping("/{id}/review")
    public void review(@PathVariable long id, @RequestBody ReviewRequest r) {
        closures.reviewClosure(id, r.approve());
    }
}
