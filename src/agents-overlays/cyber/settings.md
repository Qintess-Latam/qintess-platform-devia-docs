# cyber — settings.json

```json
{
  "model": "sonnet",
  "permissions": {
    "allow": [
      "Bash(git status)",
      "Bash(git diff:*)",
      "Bash(git log:*)",
      "Bash(git branch:*)",
      "Bash(git add:*)",
      "Bash(git commit:*)",
      "Bash(semgrep scan:*)",
      "Bash(semgrep --version)",
      "Bash(gitleaks detect:*)",
      "Bash(gitleaks git:*)",
      "Bash(gitleaks dir:*)",
      "Bash(trivy fs:*)",
      "Bash(trivy config:*)",
      "Bash(trivy repo:*)",
      "Bash(trivy image:*)",
      "Bash(trivy sbom:*)"
    ],
    "ask": [
      "Bash(git push:*)",
      "Bash(gh pr create:*)",
      "Bash(gh pr merge:*)",
      "Bash(gh issue create:*)",
      "Bash(zap:*)",
      "Bash(curl:*)"
    ],
    "deny": [
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(./**/*.pem)",
      "Read(./**/*.key)",
      "Read(./secrets/**)",
      "Bash(sudo:*)",
      "Bash(rm -rf:*)",
      "Bash(git push --force:*)",
      "Bash(git push -f:*)",
      "Bash(git reset --hard:*)",
      "Bash(git clean -f:*)",
      "Bash(terraform apply:*)",
      "Bash(terraform destroy:*)",
      "Bash(kubectl apply:*)",
      "Bash(kubectl delete:*)",
      "Bash(nmap:*)",
      "Bash(sqlmap:*)",
      "Bash(hydra:*)"
    ]
  }
}
```
