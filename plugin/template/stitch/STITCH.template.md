# STITCH — {GROUP_ID}

> Cross-repo binding for this product group. Tables only, not narrative.
> Last verified: YYYY-MM-DD | Drift source: {DRIFT_SOURCE}

## 1. Group identity

| Field | Value |
|-------|-------|
| Group tag | `{GROUP_ID}` |
| Backend repo | `{BACKEND_FOLDER}` @ `{BACKEND_SHA}` |
| Frontend repo(s) | `{FRONTEND_FOLDERS}` @ `{FE_SHAS}` |
| CODEMAP paths | `{BACKEND_FOLDER}/CODEMAP.md`, `{FRONTEND_FOLDER}/CODEMAP.md`, … |
| STITCH output | `{STITCH_FILE}` |

---

## 2. Auth stitch

Token path from frontend login through backend auth middleware.

| Step | Location | Notes |
|------|----------|-------|
| Login / token storage | FE: … | … |
| Interceptor / refresh | FE: … | … |
| Middleware / JWT validation | BE: … | … |

*(Mermaid diagram optional; keep minimal — use only if it clarifies non-obvious auth flow.)*

---

## 3. Endpoint stitch

FE → BE API call table. One row per `(method, path)` pair.

| FE hook / client | HTTP | FE file | Path | BE urls module | View / handler | Permission | Notes |
|------------------|------|---------|------|----------------|----------------|------------|-------|
| … | … | … | … | … | … | … | … |

---

## 4. Entity stitch

Model → serializer → FE type mapping.

| Domain | FE type / schema | BE serializer | Model | Notes |
|--------|------------------|---------------|-------|-------|
| … | … | … | … | … |

---

## 5. Integration stitch

External services consumed by the backend; FE usage noted where relevant.

| Service | Env keys | Owner repo | Files | FE usage |
|---------|----------|------------|-------|----------|
| … | … | backend | … | … |

---

## 6. Drift log

> Drift source: {DRIFT_SOURCE}
> (e.g., *"CODEMAPs (sections: URLConf tree, API client)"* or *"user script (analyze-stitch.sh)"* or *"fallback grep — CODEMAPs incomplete"*)

### FE orphans — FE calls missing BE routes

| FE call | FE file | Notes |
|---------|---------|-------|
| … | … | … |

### BE orphans — BE routes unused by FE

| BE route | BE file | Notes |
|----------|---------|-------|
| … | … | … |

### Drift remediation

Each orphan is a candidate for one of:
- **Fix** — align FE/BE (missing implementation, wrong path, etc.)
- **Remove** — dead code to be deleted
- **Document** — intentional divergence; add note in row + optional entry in an adjacent ADR

Re-run `/stitch diff <group>` after remediation to verify clean drift state.

---

## Analyze script contract (optional)

For sharper drift detection, place `analyze-stitch.sh` or `analyze-stitch.py` at workspace root.

**Stdin (JSON):**
```json
{
  "backend_root": "<absolute path>",
  "frontend_roots": ["<absolute path>", "..."],
  "group": "<group tag>"
}
```

**Stdout (JSON):**
```json
{
  "fe_orphans": [
    {"call": "/api/v1/users", "file": "web/src/hooks/use-users.ts"},
    ...
  ],
  "be_orphans": [
    {"route": "/api/v1/legacy", "file": "backend/user/urls.py"},
    ...
  ]
}
```

Script is owned by the user's workspace, not shipped by ARIA.
