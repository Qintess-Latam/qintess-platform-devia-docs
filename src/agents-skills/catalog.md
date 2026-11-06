# catalog.yaml — skills

```yaml
# Fuente de verdad del catálogo de skills — ver CONTRIBUTING.md.
# validate_skill.py chequea que esto coincida 1:1 con skills/<equipo>/<nombre>/SKILL.md
# (sin huérfanos en ningún lado) y que tier/owner coincidan con el metadata real.
teams:
  architect:
    domain: architecture
    skills:
      - name: architecture-review
        tier: T2
        owner: qintess-platform
        compatible: [claude, copilot]
      - name: spec-from-jira
        tier: T2
        owner: qintess-platform
        compatible: [claude, copilot]

  developer:
    domain: engineering
    skills:
      - name: claude-md-updater
        tier: T1
        owner: qintess-platform
        compatible: [claude, copilot]
      - name: code-review-security
        tier: T2
        owner: qintess-platform
        compatible: [claude, copilot]
      - name: spec-implementer
        tier: T2
        owner: qintess-platform
        compatible: [claude, copilot]
      - name: framer-motion
        tier: T2
        owner: qintess-platform
        compatible: [claude, copilot]
      # vendored (metadata.author) — sin tier/owner Qintess
      - name: design-system
        vendor: claudekit
        compatible: [claude, copilot]
      - name: ui-styling
        vendor: claudekit
        compatible: [claude, copilot]
      - name: ui-ux-pro-max
        vendor: "Next Level Builder"
        compatible: [claude, copilot]

  qa:
    domain: qa
    skills:
      - name: bdd-test-generation
        tier: T2
        owner: qintess-platform
        compatible: [claude, copilot]
      - name: coverage-gap-analysis
        tier: T2
        owner: qintess-platform
        compatible: [claude, copilot]
      - name: mutation-testing
        tier: T2
        owner: qintess-platform
        compatible: [claude, copilot]
      - name: unit-test-generation
        tier: T2
        owner: qintess-platform
        compatible: [claude, copilot]
```
