# platform — settings.json

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
      "Bash(terraform fmt:*)",
      "Bash(terraform validate:*)",
      "Bash(terraform plan:*)",
      "Bash(terraform init:*)",
      "Bash(terraform show:*)",
      "Bash(terraform output:*)",
      "Bash(terraform providers:*)",
      "Bash(helm lint:*)",
      "Bash(helm template:*)",
      "Bash(helm show:*)",
      "Bash(helm list:*)",
      "Bash(helm status:*)",
      "Bash(kubectl get:*)",
      "Bash(kubectl describe:*)",
      "Bash(kubectl logs:*)",
      "Bash(kubectl diff:*)",
      "Bash(kubectl explain:*)",
      "Bash(yq:*)"
    ],
    "ask": [
      "Bash(git push:*)",
      "Bash(gh pr create:*)",
      "Bash(gh pr merge:*)",
      "Bash(terraform state:*)",
      "Bash(terraform import:*)",
      "Bash(aws:*)",
      "Bash(az:*)"
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
      "Bash(helm install:*)",
      "Bash(helm upgrade:*)",
      "Bash(helm uninstall:*)",
      "Bash(terraform force-unlock:*)",
      "Read(**/kubeconfig*)",
      "Read(~/.kube/config)",
      "Read(~/.aws/credentials)",
      "Read(~/.azure/**)"
    ]
  }
}
```
